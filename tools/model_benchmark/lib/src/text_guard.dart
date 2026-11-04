import 'dart:math';

import 'protected_spans.dart';
import 'text_diff.dart';

class RejectedEdit {
  const RejectedEdit(this.edit, this.reason);
  final Edit edit;
  final String reason;
}

/// Результат связан с точным снимком исходного текста.
class GuardResult {
  const GuardResult(
    this.original,
    this.accepted,
    this.rejected,
    this.spans, {
    this.failure,
  });
  final String original;
  final List<Edit> accepted;
  final List<RejectedEdit> rejected;
  final List<ProtectedSpan> spans;
  final String? failure;

  String applyTo(String current) {
    if (current != original) {
      throw StateError('Результат относится к другой версии текста');
    }
    return applyEdits(current, accepted);
  }

  String get output => applyTo(original);
}

final _letters = RegExp(r'^[\p{L}\p{M}]*$', unicode: true);
final _punctuation = RegExp(r'^[,:;]*$');

/// Допускает небольшие замены слов и внутреннюю пунктуацию вне защиты.
/// Не использует ожидаемые исправления или разметку проверочного набора.
GuardResult guardText(
  String text,
  String proposed, {
  List<String> names = const [],
}) {
  if (!_wellFormed(text) || !_wellFormed(proposed)) {
    return GuardResult(
      text,
      const [],
      const [],
      const [],
      failure: 'invalid_unicode',
    );
  }
  if (text.runes.length > 4000 ||
      proposed.runes.length > 4000 ||
      (text.runes.length + 1) * (proposed.runes.length + 1) > 4000000) {
    return GuardResult(
      text,
      const [],
      const [],
      const [],
      failure: 'diff_limit',
    );
  }
  final spans = protectedSpans(text, names: names);
  final words = wordPattern.allMatches(text).toList();
  final grouped = <int, List<Edit>>{};
  final candidates = <Edit>[];
  final rejected = <RejectedEdit>[];
  for (final edit in diffEdits(text, proposed)) {
    final word = _wordIndex(edit, words);
    if (word != null) {
      grouped.putIfAbsent(word, () => []).add(edit);
    } else if (_isPunctuation(edit, text, words)) {
      candidates.add(edit);
    } else {
      rejected.add(RejectedEdit(edit, 'nonlocal_or_formatting'));
    }
  }
  for (final entry in grouped.entries) {
    final word = words[entry.key];
    final edits = [
      for (final edit in entry.value)
        Edit(edit.start - word.start, edit.original, edit.replacement),
    ];
    candidates.add(
      Edit(word.start, word.group(0)!, applyEdits(word.group(0)!, edits)),
    );
  }
  candidates.sort((left, right) => left.start.compareTo(right.start));
  final accepted = <Edit>[];
  for (final edit in candidates) {
    final reason = _reason(edit, spans);
    if (reason == null) {
      accepted.add(edit);
    } else {
      rejected.add(RejectedEdit(edit, reason));
    }
  }
  if (!_preservesSpans(text, accepted, spans)) {
    return GuardResult(
      text,
      const [],
      List.unmodifiable(rejected),
      spans,
      failure: 'protection_invariant',
    );
  }
  return GuardResult(
    text,
    List.unmodifiable(accepted),
    List.unmodifiable(rejected),
    spans,
  );
}

bool _preservesSpans(String text, List<Edit> edits, List<ProtectedSpan> spans) {
  final output = applyEdits(text, edits);
  int shifted(int position, {required bool includeInsertion}) {
    var result = position;
    for (final edit in edits) {
      if (edit.end > position) continue;
      if (edit.original.isEmpty &&
          edit.start == position &&
          !includeInsertion) {
        continue;
      }
      result += edit.replacement.length - edit.original.length;
    }
    return result;
  }

  return spans.every(
    (span) =>
        output.substring(
          shifted(span.start, includeInsertion: true),
          shifted(span.end, includeInsertion: false),
        ) ==
        text.substring(span.start, span.end),
  );
}

int? _wordIndex(Edit edit, List<RegExpMatch> words) {
  if (!_letters.hasMatch(edit.original) ||
      !_letters.hasMatch(edit.replacement)) {
    return null;
  }
  for (var index = 0; index < words.length; index++) {
    final word = words[index];
    if (edit.start >= word.start && edit.end <= word.end) return index;
  }
  return null;
}

bool _isPunctuation(Edit edit, String text, List<RegExpMatch> words) {
  if (!_punctuation.hasMatch(edit.original) ||
      !_punctuation.hasMatch(edit.replacement)) {
    return false;
  }
  if (edit.start == 0 || edit.end >= text.trimRight().length) return false;
  if (edit.original.isEmpty && !words.any((word) => word.end == edit.start)) {
    return false;
  }
  if (edit.original.isEmpty && words.any((word) => word.start == edit.start)) {
    return false;
  }
  if (words.any((word) => word.start < edit.start && edit.start < word.end)) {
    return false;
  }
  return words.any((word) => word.end <= edit.start) &&
      words.any((word) => word.start >= edit.end);
}

String? _reason(Edit edit, List<ProtectedSpan> spans) {
  for (final span in spans) {
    final overlaps = edit.start < span.end && edit.end > span.start;
    final insertionInside =
        edit.original.isEmpty &&
        span.start < edit.start &&
        edit.start < span.end;
    final joinsBoundary =
        edit.original.isEmpty &&
        (edit.start == span.start || edit.start == span.end) &&
        !_punctuation.hasMatch(edit.replacement);
    if (overlaps || insertionInside || joinsBoundary) {
      return 'protected_${span.reason}';
    }
  }
  if (_punctuation.hasMatch(edit.original) &&
      _punctuation.hasMatch(edit.replacement)) {
    return null;
  }
  if (edit.replacement.isEmpty ||
      edit.replacement.toLowerCase() != edit.replacement) {
    return 'word_shape';
  }
  if (edit.original.replaceAll('ё', 'е') ==
      edit.replacement.replaceAll('ё', 'е')) {
    return 'optional_yo';
  }
  final allowed = min(
    2,
    (max(edit.original.runes.length, edit.replacement.runes.length) * 0.4)
        .floor(),
  );
  if (_distance(edit.original, edit.replacement) > allowed) {
    return 'large_word_change';
  }
  return null;
}

int _distance(String left, String right) {
  final a = left.runes.toList(), b = right.runes.toList();
  var previous = List.generate(b.length + 1, (index) => index);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      current.add(
        min(
          min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + (a[i] == b[j] ? 0 : 1),
        ),
      );
    }
    previous = current;
  }
  return previous.last;
}

bool _wellFormed(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xdc00 && unit <= 0xdfff) return false;
    if (unit < 0xd800 || unit > 0xdbff) continue;
    if (++i >= text.length) return false;
    final next = text.codeUnitAt(i);
    if (next < 0xdc00 || next > 0xdfff) return false;
  }
  return true;
}
