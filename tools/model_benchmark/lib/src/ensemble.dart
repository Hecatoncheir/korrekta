import 'dart:convert';

import 'dictionary_checker.dart';
import 'hunspell_choices.dart';
import 'text_diff.dart';
import 'text_guard.dart';

// Общий словарь распознаёт слова из обоих источников; подсказки независимы.
class SharedLexicon implements WordDictionary {
  SharedLexicon(this.primary, this.other);
  final WordDictionary primary;
  final WordDictionary other;
  @override
  Future<bool> knows(String word, String language) async =>
      await primary.knows(word, language) || await other.knows(word, language);
  @override
  Future<List<String>> suggest(String word) => primary.suggest(word);
}

class Proposal {
  Proposal(this.edits, this.source, this.rank);
  final List<Edit> edits;
  final String source;
  final int rank;
  int get start => edits.first.start;
  int get end => edits.last.end;
}

class EnsemblePool {
  EnsemblePool(this.text, this.slots, this.evidence, this.rejected);
  final String text;
  final List<WordChoices> slots;
  final List<List<Set<String>>> evidence;
  final List<Map<String, dynamic>> rejected;

  Map<String, dynamic> payload() => {
    'text': text,
    'slots': [
      for (var i = 0; i < slots.length; i++)
        {
          'id': i,
          ...slots[i].toJson(),
          'sources': evidence[i].map((s) => s.toList()..sort()).toList(),
        },
    ],
  };

  String apply(List<int> choices, String current) =>
      selectEnsembleChoices(text, slots, choices).applyTo(current);
}

SelectedText selectEnsembleChoices(
  String text,
  List<WordChoices> slots,
  List<int> choices,
) {
  if (slots.length != choices.length) {
    throw const FormatException('Другая длина выбора');
  }
  final edits = <Edit>[];
  var end = 0;
  var previousStart = -1;
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    if (slot.start < end ||
        slot.start == previousStart ||
        slot.end > text.length ||
        slot.options.isEmpty ||
        slot.options.first != slot.original ||
        text.substring(slot.start, slot.end) != slot.original ||
        !_boundary(text, slot.start) ||
        !_boundary(text, slot.end)) {
      throw const FormatException('Неверный диапазон общего выбора');
    }
    final choice = choices[i];
    if (choice < 0 || choice >= slot.options.length) {
      throw const FormatException('Вариант вне списка');
    }
    if (choice != 0) {
      edits.add(Edit(slot.start, slot.original, slot.options[choice]));
    }
    previousStart = slot.start;
    end = slot.end;
  }
  return SelectedText(text, List.unmodifiable(edits));
}

bool _boundary(String text, int position) =>
    position == text.length ||
    text.codeUnitAt(position) < 0xdc00 ||
    text.codeUnitAt(position) > 0xdfff;

bool _overlaps(Proposal left, Proposal right) =>
    left.start == right.start ||
    (left.start < right.end && right.start < left.end);

List<Proposal> _guarded(
  String text,
  String output,
  String source,
  int rank,
  List<String> names,
  List<Map<String, dynamic>> rejected, {
  bool atomic = false,
}) {
  final guard = guardText(text, output, names: names);
  if (guard.failure != null || guard.rejected.isNotEmpty) {
    rejected.add({
      'source': source,
      'failure': guard.failure,
      'reasons': guard.rejected.map((r) => r.reason).toList(),
    });
  }
  // Составной вариант одного правила LT не разрешается применять частично.
  if (guard.failure != null || (atomic && guard.rejected.isNotEmpty)) return [];
  if (guard.accepted.isEmpty) return [];
  if (atomic) return [Proposal(guard.accepted, source, rank)];
  return [
    for (final edit in guard.accepted) Proposal([edit], source, rank),
  ];
}

List<Proposal> _ltProposals(
  String text,
  List<dynamic> matches,
  List<String> names,
  List<Map<String, dynamic>> rejected,
) {
  final proposals = <Proposal>[];
  for (final value in matches) {
    final match = value as Map<String, dynamic>;
    final start = match['offset'] as int;
    final end = start + (match['length'] as int);
    if (start < 0 || end < start || end > text.length) {
      throw const FormatException('Неправильный диапазон LT');
    }
    final replacements = match['replacements'] as List<dynamic>;
    for (var i = 0; i < replacements.length && i < 8; i++) {
      final replacement =
          (replacements[i] as Map<String, dynamic>)['value'] as String;
      final output = text.replaceRange(start, end, replacement);
      proposals.addAll(
        _guarded(
          text,
          output,
          'languagetool',
          i,
          names,
          rejected,
          atomic: true,
        ),
      );
    }
  }
  return proposals;
}

EnsemblePool buildEnsemble(
  String text, {
  required List<WordChoices> hunspell,
  required List<WordChoices> symspell,
  required List<dynamic> matches,
  required String gigaOutput,
  List<String> names = const [],
}) {
  if (text.runes.length > 1200) {
    throw const FormatException(
      'Для общего режима нужен фрагмент до 1200 символов',
    );
  }
  final rejected = <Map<String, dynamic>>[];
  final proposals = _ltProposals(text, matches, names, rejected);
  final sources = {'hunspell': hunspell, 'symspell': symspell};
  for (final entry in sources.entries) {
    for (final slot in entry.value) {
      for (var i = 1; i < slot.options.length; i++) {
        final output = selectChoices(text, [slot], [i]).output;
        proposals.addAll(
          _guarded(text, output, entry.key, i - 1, names, rejected),
        );
      }
    }
  }
  proposals.addAll(_guarded(text, gigaOutput, 'gigachat', 0, names, rejected));
  proposals.sort((a, b) => a.start.compareTo(b.start));
  final groups = <List<Proposal>>[];
  for (final proposal in proposals) {
    if (groups.isNotEmpty && groups.last.any((p) => _overlaps(p, proposal))) {
      groups.last.add(proposal);
    } else {
      groups.add([proposal]);
    }
  }
  if (groups.length > 32) {
    throw const FormatException(
      'Больше 32 спорных фрагментов; разделите текст',
    );
  }
  final slots = <WordChoices>[];
  final evidence = <List<Set<String>>>[];
  for (final group in groups) {
    group.sort(_priority);
    final start = group.map((p) => p.start).reduce((a, b) => a < b ? a : b);
    final end = group.map((p) => p.end).reduce((a, b) => a > b ? a : b);
    final original = text.substring(start, end);
    final options = <String, Set<String>>{original: <String>{}};
    for (final proposal in group) {
      final local = [
        for (final edit in proposal.edits)
          Edit(edit.start - start, edit.original, edit.replacement),
      ];
      final option = applyEdits(original, local);
      options.putIfAbsent(option, () => <String>{}).add(proposal.source);
    }
    // Ничего не обрезаем молча: при превышении лимита нужна меньшая порция.
    if (options.length > 33) {
      throw const FormatException('Больше 32 вариантов фрагмента');
    }
    slots.add(WordChoices(start, original, options.keys));
    evidence.add(options.values.toList());
  }
  return EnsemblePool(text, List.unmodifiable(slots), evidence, rejected);
}

int _priority(Proposal a, Proposal b) {
  const order = {
    'languagetool': 0,
    'hunspell': 1,
    'symspell': 2,
    'gigachat': 3,
  };
  final bySource = order[a.source]!.compareTo(order[b.source]!);
  return bySource == 0 ? a.rank.compareTo(b.rank) : bySource;
}

// Точная двухсообщенческая форма официального шаблона ревизии 8a607531.
String gigaPrompt(String system, Map<String, dynamic> payload) =>
    '<s>$system<|message_sep|>user<|role_sep|>${jsonEncode(payload)}'
    '<|message_sep|>available functions<|role_sep|>[]<|message_sep|>'
    'assistant<|role_sep|>';
