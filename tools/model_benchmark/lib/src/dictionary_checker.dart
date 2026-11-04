import 'dart:math';

import 'protected_spans.dart';
import 'symspell.dart';
import 'text_diff.dart';

abstract interface class WordDictionary {
  Future<bool> knows(String word, String language);
  Future<List<String>> suggest(String word);
}

class DictionaryResult {
  const DictionaryResult(this.original, this.edits, this.decisions);
  final String original;
  final List<Edit> edits;
  final List<Map<String, dynamic>> decisions;
  String applyTo(String current) {
    if (current != original) throw StateError('Снимок текста изменился');
    return applyEdits(current, edits);
  }

  String get output => applyTo(original);
}

final _tokens = RegExp(r"[A-Za-zА-Яа-яЁё]+(?:[;'\[\],.\-][A-Za-zА-Яа-яЁё]+)*");
final _russian = RegExp(r'^[а-яё]+$');
final _english = RegExp(r'^[a-z]+$');
const _latinKeys = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
const _russianKeys = 'ёйцукенгшщзхъфывапролджэячсмитьбю';

String swapKeyboard(String word, {required bool toRussian}) {
  final from = toRussian ? _latinKeys : _russianKeys;
  final to = toRussian ? _russianKeys : _latinKeys;
  return word.split('').map((letter) {
    final index = from.indexOf(letter.toLowerCase());
    if (index < 0) return letter;
    final replacement = to[index];
    return letter != letter.toLowerCase() && letter == letter.toUpperCase()
        ? replacement.toUpperCase()
        : replacement;
  }).join();
}

bool _overlaps(RegExpMatch token, ProtectedSpan span) =>
    token.start < span.end && token.end > span.start;

bool _identifierBoundary(String text, RegExpMatch token) {
  final around =
      '${token.start == 0 ? '' : text[token.start - 1]}'
      '${token.end == text.length ? '' : text[token.end]}';
  return RegExp(r'[0-9_]').hasMatch(around);
}

bool _smallReplacement(String before, String after) {
  if (!_russian.hasMatch(after)) return false;
  if ('ё'.allMatches(before).length > 'ё'.allMatches(after).length) {
    return false;
  }
  final allowed = min(2, (max(before.length, after.length) * .4).floor());
  return spellingDistance(dictionaryKey(before), dictionaryKey(after)) <=
      allowed;
}

Future<String?> _layoutCandidate(
  String value,
  WordDictionary dictionary,
) async {
  if (value.length < 2 || value == value.toUpperCase()) return null;
  final lower = value.toLowerCase();
  final toRussian = RegExp(r'^[a-z;\[\],.]+$').hasMatch(lower);
  final sourceLanguage = toRussian ? 'en' : 'ru';
  if (!toRussian && !_russian.hasMatch(lower)) return null;
  if (await dictionary.knows(lower, sourceLanguage)) return null;
  final replacement = swapKeyboard(value, toRussian: toRussian);
  final target = replacement.toLowerCase();
  if (!(toRussian ? _russian : _english).hasMatch(target)) return null;
  if (!await dictionary.knows(target, toRussian ? 'ru' : 'en')) return null;
  return replacement;
}

/// Решения принимаются только по исходнику, словарям и личному списку имён.
Future<DictionaryResult> checkDictionaryText(
  String text,
  WordDictionary dictionary, {
  bool layout = false,
  List<String> names = const [],
}) async {
  final spans = protectedSpans(text, names: names);
  final edits = <Edit>[];
  final decisions = <Map<String, dynamic>>[];
  for (final token in _tokens.allMatches(text)) {
    final original = token.group(0)!;
    final lower = original.toLowerCase();
    if (original.contains('-') || _identifierBoundary(text, token)) continue;
    final protected = spans.where((span) => _overlaps(token, span)).toList();
    if (protected.any((span) => span.reason != 'name_candidate')) continue;
    String? replacement;
    var reason = 'spelling';
    if (layout) {
      replacement = await _layoutCandidate(original, dictionary);
      if (replacement != null) reason = 'layout';
    }
    if (replacement == null && protected.isEmpty && _russian.hasMatch(lower)) {
      if (await dictionary.knows(lower, 'ru')) continue;
      final suggestions = await dictionary.suggest(lower);
      final allowed = suggestions.where(
        (word) => _smallReplacement(lower, word),
      );
      if (allowed.isNotEmpty) replacement = allowed.first;
      decisions.add({
        'start': token.start,
        'original': original,
        'suggestions': suggestions.take(5).toList(),
        'status': replacement == null ? 'unknown' : 'suggested',
      });
    }
    if (replacement == null || replacement == original) continue;
    edits.add(Edit(token.start, original, replacement));
    decisions.add({
      'start': token.start,
      'original': original,
      'replacement': replacement,
      'reason': reason,
    });
  }
  return DictionaryResult(
    text,
    List.unmodifiable(edits),
    List.unmodifiable(decisions),
  );
}
