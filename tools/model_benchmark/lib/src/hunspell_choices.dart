import 'dart:convert';
import 'dart:math';

import 'dictionary_checker.dart';
import 'symspell.dart';
import 'text_diff.dart';

class WordChoices {
  WordChoices(this.start, this.original, Iterable<String> options)
    : options = List.unmodifiable(options);
  final int start;
  final String original;
  final List<String> options;
  int get end => start + original.length;

  Map<String, dynamic> toJson() => {
    'start': start,
    'original': original,
    'options': options,
  };

  factory WordChoices.fromJson(Map<String, dynamic> value) => WordChoices(
    value['start'] as int,
    value['original'] as String,
    (value['options'] as List<dynamic>).cast<String>(),
  );
}

class _RecordingDictionary implements WordDictionary {
  _RecordingDictionary(this.source);
  final WordDictionary source;
  final suggestions = <String, List<String>>{};
  @override
  Future<bool> knows(String word, String language) =>
      source.knows(word, language);
  @override
  Future<List<String>> suggest(String word) async {
    final values = await source.suggest(word);
    suggestions[word] = values;
    return values;
  }
}

// Повторяет фильтр замен dictionary-v1; исходный модуль не меняется.
bool _allowed(String before, String after) {
  if (!RegExp(r'^[а-яё]+$').hasMatch(after)) return false;
  if ('ё'.allMatches(before).length > 'ё'.allMatches(after).length) {
    return false;
  }
  final limit = min(2, (max(before.length, after.length) * .4).floor());
  return spellingDistance(dictionaryKey(before), dictionaryKey(after)) <= limit;
}

Future<List<WordChoices>> collectHunspellChoices(
  String text,
  WordDictionary dictionary, {
  bool layout = false,
  List<String> names = const [],
}) async {
  final recording = _RecordingDictionary(dictionary);
  final checked = await checkDictionaryText(
    text,
    recording,
    layout: layout,
    names: names,
  );
  final slots = <WordChoices>[];
  for (final decision in checked.decisions) {
    final original = decision['original'] as String;
    final values = <String>{};
    if (decision.containsKey('suggestions')) {
      values.addAll(
        (recording.suggestions[original.toLowerCase()] ?? const []).where(
          (word) => word != original && _allowed(original, word),
        ),
      );
    } else if (decision['reason'] == 'layout') {
      values.add(decision['replacement'] as String);
    }
    if (values.isEmpty) continue;
    slots.add(
      WordChoices(decision['start'] as int, original, [
        original,
        ...values.take(12),
      ]),
    );
  }
  slots.sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(slots.take(16));
}

class SelectedText {
  const SelectedText(this.original, this.edits);
  final String original;
  final List<Edit> edits;
  String applyTo(String current) {
    if (current != original) {
      throw StateError('Выбор относится к другому снимку');
    }
    return applyEdits(current, edits);
  }

  String get output => applyTo(original);
}

SelectedText selectChoices(
  String text,
  List<WordChoices> slots,
  List<int> choices,
) {
  if (slots.length != choices.length) {
    throw const FormatException('Другая длина choices');
  }
  final edits = <Edit>[];
  var previousEnd = 0;
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    final choice = choices[i];
    if (slot.start < previousEnd ||
        slot.original.isEmpty ||
        slot.end > text.length ||
        slot.options.isEmpty ||
        slot.options.first != slot.original ||
        text.substring(slot.start, slot.end) != slot.original) {
      throw const FormatException('Неправильный или устаревший диапазон');
    }
    if (choice < 0 || choice >= slot.options.length) {
      throw const FormatException('Вариант вне списка Hunspell');
    }
    if (choice != 0) {
      edits.add(Edit(slot.start, slot.original, slot.options[choice]));
    }
    previousEnd = slot.end;
  }
  return SelectedText(text, List.unmodifiable(edits));
}

List<int> parseChoices(String content, int count) {
  final value = jsonDecode(content);
  if (value is! Map<String, dynamic> || value.length != count) {
    throw const FormatException('Нужны только числовые поля c0..cN');
  }
  final choices = <int>[];
  for (var i = 0; i < count; i++) {
    final choice = value['c$i'];
    if (choice is! int) {
      throw const FormatException('Отсутствует целый номер варианта');
    }
    choices.add(choice);
  }
  return choices;
}

Map<String, dynamic> choicesSchema(List<WordChoices> slots) => {
  'type': 'object',
  'properties': {
    for (var i = 0; i < slots.length; i++)
      'c$i': {
        'type': 'integer',
        'enum': List.generate(slots[i].options.length, (index) => index),
      },
  },
  'required': [for (var i = 0; i < slots.length; i++) 'c$i'],
  'additionalProperties': false,
};
