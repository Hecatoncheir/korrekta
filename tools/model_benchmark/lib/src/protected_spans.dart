/// Диапазон исходного текста в индексах UTF-16.
class ProtectedSpan {
  const ProtectedSpan(this.start, this.end, this.reason);
  final int start;
  final int end;
  final String reason;
}

final wordPattern = RegExp(r'[\p{L}\p{M}]+', unicode: true);
final _capital = RegExp(r'\p{Lu}', unicode: true);
final _latin = RegExp(r'[A-Za-z]');
final _wordCharacter = RegExp(r'[\p{L}\p{M}\p{N}_]', unicode: true);

final _patterns = <String, RegExp>{
  'whitespace': RegExp(r'\s+', unicode: true),
  'spacing': RegExp(r'[:;,.!?] {2,}'),
  'code': RegExp(r'```[\s\S]*?(?:```|$)|`[^`\r\n]*(?:`|$)'),
  'json': RegExp(r'\{[^\r\n]*\}'),
  'url': RegExp(r'''(?:https?://|www\.)[^\s<>"«»]+'''),
  'email': RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
  'path': RegExp(r'''[A-Za-z]:\\[^\s<>"«»]+|(?:/[\w.\-]+){2,}'''),
  'technical': RegExp(
    r'[A-Za-z0-9_]+(?:[.\-][A-Za-z0-9_]+)+|[A-Za-z0-9]+_[A-Za-z0-9_]+',
  ),
  'quoted': RegExp('«[^»]*»|„[^“]*“|“[^”]*”|"[^"\\r\\n]*"|‘[^’]*’'),
  'quote': RegExp('[«»„“”"‘’\u0027]'),
  'markup': RegExp(r'\*\*[^*\r\n]*\*\*|__[^_\r\n]*__|~~[^~\r\n]*~~'),
  'line_marker': RegExp(
    r'^[ \t]*(?:[-*+] |[0-9]+[.)] |> ?|#{1,6} )',
    multiLine: true,
  ),
  'symbol': RegExp(r'[\p{So}\p{Sk}\p{M}\p{Cf}]+', unicode: true),
  'combining': RegExp(r'\p{L}\p{M}+|[0-9#*]\uFE0F?\u20E3', unicode: true),
};

/// Определяет защиту только по исходнику и личному словарю, без эталонов.
List<ProtectedSpan> protectedSpans(
  String text, {
  List<String> names = const [],
}) {
  final spans = <ProtectedSpan>[];
  for (final entry in _patterns.entries) {
    for (final match in entry.value.allMatches(text)) {
      spans.add(ProtectedSpan(match.start, match.end, entry.key));
    }
  }
  for (final word in wordPattern.allMatches(text)) {
    final value = word.group(0)!;
    if (_capital.hasMatch(value) || _latin.hasMatch(value)) {
      spans.add(ProtectedSpan(word.start, word.end, 'name_candidate'));
    }
  }
  for (final name in names) {
    if (name.trim().isEmpty) throw ArgumentError('Имя не должно быть пустым');
    final pattern = RegExp(
      RegExp.escape(name),
      caseSensitive: false,
      unicode: true,
    );
    for (final match in pattern.allMatches(text)) {
      if (_isWordAt(text, match.start - 1) || _isWordAt(text, match.end)) {
        continue;
      }
      spans.add(ProtectedSpan(match.start, match.end, 'personal_name'));
    }
  }
  spans.sort((left, right) => left.start.compareTo(right.start));
  return List.unmodifiable(spans);
}

bool _isWordAt(String text, int offset) {
  if (offset < 0 || offset >= text.length) return false;
  var start = offset;
  final unit = text.codeUnitAt(start);
  if (unit >= 0xdc00 && unit <= 0xdfff && start > 0) start--;
  final first = text.codeUnitAt(start);
  final length = first >= 0xd800 && first <= 0xdbff ? 2 : 1;
  return _wordCharacter.hasMatch(text.substring(start, start + length));
}
