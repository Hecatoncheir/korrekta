import 'dart:convert';

import 'dictionary_checker.dart';
import 'ensemble.dart';
import 'hunspell_choices.dart';
import 'symspell.dart';
import 'text_guard.dart';

const roleProfiles = ['context', 'agreement', 'clauses', 'inflections'];

bool _word(String value) => RegExp(r'^[а-яё]+$').hasMatch(value);

Future<bool> _known(WordDictionary lexicon, String value) async =>
    _word(value.toLowerCase()) &&
    await lexicon.knows(value.toLowerCase(), 'ru');

List<Map<String, dynamic>> _ltEffects(String text, List<dynamic> matches) {
  final effects = <Map<String, dynamic>>[];
  for (final value in matches.cast<Map<String, dynamic>>()) {
    final start = value['offset'] as int;
    final end = start + (value['length'] as int);
    final rule = value['rule'] as Map<String, dynamic>;
    final category = (rule['category'] as Map<String, dynamic>)['id'];
    final replacements = value['replacements'] as List<dynamic>;
    for (var i = 0; i < replacements.length && i < 8; i++) {
      final target =
          (replacements[i] as Map<String, dynamic>)['value'] as String;
      final guard = guardText(text, text.replaceRange(start, end, target));
      if (guard.failure != null || guard.rejected.isNotEmpty) continue;
      effects.add({
        'output': guard.output,
        'category': category,
        'rule': rule['id'],
        'preferred': i == 0,
        'style_risk': RegExp(
          r'простореч|разговор|устар|канцеляр|синоним|стилист',
          caseSensitive: false,
        ).hasMatch(rule['description'] as String),
      });
    }
  }
  return effects;
}

bool _grammarAlert(Map<String, dynamic> slot, List<dynamic> matches) {
  final start = slot['start'] as int;
  final end = start + (slot['original'] as String).length;
  return matches.cast<Map<String, dynamic>>().any((match) {
    final rule = match['rule'] as Map<String, dynamic>;
    final category = (rule['category'] as Map<String, dynamic>)['id'];
    final offset = match['offset'] as int;
    return category == 'GRAMMAR' &&
        offset < end &&
        offset + (match['length'] as int) > start;
  });
}

Future<List<Map<String, dynamic>>> roleFeatures(
  Map<String, dynamic> row,
  WordDictionary lexicon,
) async {
  final text = row['text'] as String;
  final matches =
      (row['lt_response'] as Map<String, dynamic>)['matches'] as List<dynamic>;
  final effects = _ltEffects(text, matches);
  final result = <Map<String, dynamic>>[];
  for (final slot
      in (row['slots'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final choices = WordChoices.fromJson(slot);
    final options = <Map<String, dynamic>>[];
    for (var i = 0; i < choices.options.length; i++) {
      final output = selectEnsembleChoices(text, [choices], [i]).output;
      final matched = effects
          .where((effect) => effect['output'] == output)
          .toList();
      options.add({
        'known': await _known(lexicon, choices.options[i]),
        'lt_categories': matched.map((e) => e['category']).toSet().toList(),
        'lt_rules': matched.map((e) => e['rule']).toSet().toList(),
        'lt_preferred': matched.any((e) => e['preferred'] == true),
        'style_risk': matched.any((e) => e['style_risk'] == true),
      });
    }
    result.add({
      'grammar_alert': _grammarAlert(slot, matches),
      'options': options,
    });
  }
  return result;
}

bool _nameContext(String text, WordChoices slot) {
  final left = text.substring(0, slot.start).toLowerCase();
  return RegExp(
    r'(?:имя|именем|ник|никнейм|пользователь|автор|участник|участница|персонаж|проект|термин)\s+$',
  ).hasMatch(left);
}

bool _variableAgreement(String text, WordChoices slot, String replacement) {
  final verb = RegExp(r'(?:л[аои]?|[еёи][тм]|[ую]т|[ая]т|ете|ите|ешь|ишь)$');
  if (!verb.hasMatch(slot.original) || !verb.hasMatch(replacement)) {
    return false;
  }
  return RegExp(
    r'(?<![а-яё])(?:большинство|меньшинство|часть|ряд|половина|треть|четверть|два|две|три|четыре|пять|шесть|семь|восемь|девять|десять)(?![а-яё])|\d',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _inflection(String before, String after) {
  var common = 0;
  while (common < before.length &&
      common < after.length &&
      before[common] == after[common]) {
    common++;
  }
  return common >= 3 &&
      spellingDistance(dictionaryKey(before), dictionaryKey(after)) <= 2;
}

bool _clauseComma(String text, WordChoices slot, String target) {
  if (slot.original.isNotEmpty || target != ',') return false;
  final left = text.substring(0, slot.start).toLowerCase();
  final right = text.substring(slot.start).trimLeft().toLowerCase();
  // Не отделяем вторую часть составного союза от первой.
  if (RegExp(r'(?:потому|так|тем|оттого)\s*$').hasMatch(left)) return false;
  if (RegExp(
    r'^(?:что|чтобы|если|когда|который|которая|которое|которые|хотя|поскольку|потому что)(?![а-яё])',
  ).hasMatch(right)) {
    return true;
  }
  if (RegExp(r'^чем(?![а-яё])').hasMatch(left) &&
      RegExp(r'^тем(?![а-яё])').hasMatch(right)) {
    return true;
  }
  final leading = RegExp(r'^(?:когда|пока|если|хотя|чтобы|поскольку)(?![а-яё])')
      .hasMatch(left);
  return leading &&
      !left.contains(',') &&
      RegExp(r'^(?:я|ты|он|она|оно|мы|вы|они|то)(?![а-яё])').hasMatch(right);
}

bool _gigaAllowed(
  String text,
  WordChoices slot,
  Map<String, dynamic> feature,
  Map<String, dynamic> option,
  Set<String> sources,
  String target,
  String profile,
) {
  if (option['style_risk'] == true) return false;
  if ('ё'.allMatches(slot.original).length > 'ё'.allMatches(target).length) {
    return false;
  }
  if (!_word(slot.original) || !_word(target)) {
    final categories = (option['lt_categories'] as List<dynamic>)
        .cast<String>();
    return categories.contains('PUNCTUATION') ||
        (profile != 'agreement' && _clauseComma(text, slot, target));
  }
  if (_variableAgreement(text, slot, target)) return false;
  final supported = sources.any((s) => s != 'gigachat');
  if (supported || feature['grammar_alert'] == true) return true;
  final originalKnown =
      ((feature['options'] as List<dynamic>).first
          as Map<String, dynamic>)['known'] ==
      true;
  return profile == 'inflections' &&
      originalKnown &&
      option['known'] == true &&
      _inflection(slot.original, target);
}

List<int> _agreedOptions(
  List<Set<String>> sources,
  List<Map<String, dynamic>> options,
) => [
  for (var i = 1; i < sources.length; i++)
    if (sources[i].containsAll({'hunspell', 'symspell', 'languagetool'}) &&
        options[i]['known'] == true)
      i,
];

int _preserveForm(
  WordChoices slot,
  int candidate,
  List<Set<String>> sources,
  List<Map<String, dynamic>> options,
) {
  final target = slot.options[candidate];
  for (var i = 1; i < slot.options.length; i++) {
    if (dictionaryKey(slot.options[i]) == dictionaryKey(target) &&
        'ё'.allMatches(slot.options[i]).length >=
            'ё'.allMatches(slot.original).length) {
      candidate = i;
      break;
    }
  }
  final distance = spellingDistance(
    dictionaryKey(slot.original),
    dictionaryKey(slot.options[candidate]),
  );
  final closer = _agreedOptions(sources, options)
      .where(
        (i) =>
            spellingDistance(
              dictionaryKey(slot.original),
              dictionaryKey(slot.options[i]),
            ) <
            distance,
      )
      .toList();
  return closer.length == 1 ? closer.single : candidate;
}

int _chooseRole(
  String text,
  Map<String, dynamic> raw,
  Map<String, dynamic> feature,
  String profile,
) {
  final slot = WordChoices.fromJson(raw);
  final sources = (raw['sources'] as List<dynamic>)
      .map((s) => (s as List<dynamic>).cast<String>().toSet())
      .toList();
  final options = (feature['options'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final giga = [
    for (var i = 1; i < sources.length; i++)
      if (sources[i].contains('gigachat')) i,
  ];
  if (profile == 'context') return giga.isEmpty ? 1 : giga.first;
  if (options.first['known'] != true && _nameContext(text, slot)) return 0;
  for (final proposed in giga) {
    final i = _preserveForm(slot, proposed, sources, options);
    if (_gigaAllowed(
      text,
      slot,
      feature,
      options[i],
      sources[i],
      slot.options[i],
      profile,
    )) {
      return i;
    }
  }
  final grammar = [
    for (var i = 1; i < sources.length; i++)
      if ((options[i]['lt_categories'] as List<dynamic>).contains('GRAMMAR') &&
          options[i]['lt_preferred'] == true &&
          options[i]['style_risk'] != true &&
          !_variableAgreement(text, slot, slot.options[i]))
        i,
  ];
  if (grammar.length == 1) return grammar.single;
  final agreement = _agreedOptions(sources, options);
  return agreement.length == 1 ? agreement.single : 0;
}

Map<String, dynamic> chooseRoles(Map<String, dynamic> row, String profile) {
  if (!roleProfiles.contains(profile)) {
    throw ArgumentError('Неизвестный профиль');
  }
  final text = row['text'] as String;
  final slots = (row['slots'] as List<dynamic>).cast<Map<String, dynamic>>();
  final features = (row['role_features'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  if (slots.length != features.length) {
    throw const FormatException('Неполные признаки вариантов');
  }
  final choices = [
    for (var i = 0; i < slots.length; i++)
      _chooseRole(text, slots[i], features[i], profile),
  ];
  final selected = selectEnsembleChoices(
    text,
    slots.map(WordChoices.fromJson).toList(),
    choices,
  );
  return {
    'output': selected.output,
    'choices': choices,
    'profile': profile,
    'decision_key': jsonEncode(choices),
  };
}
