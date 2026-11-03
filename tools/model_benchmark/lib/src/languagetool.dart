import 'scoring.dart';

// В исследовании выбирается первый вариант каждого непересекающегося замечания.
JsonMap applyLanguageTool(String text, List<dynamic> matches) {
  final edits = <Edit>[];
  final rejected = <String>[];
  var withoutReplacement = 0;
  for (final item in matches) {
    if (item is! JsonMap ||
        item['offset'] is! int ||
        item['length'] is! int ||
        item['replacements'] is! List<dynamic>) {
      throw const FormatException('Неправильная структура замечания');
    }
    final start = item['offset'] as int, length = item['length'] as int;
    if (start < 0 || length < 0 || start + length > text.length) {
      throw const FormatException('Диапазон замечания вне текста');
    }
    final replacements = item['replacements'] as List<dynamic>;
    if (replacements.isEmpty) {
      withoutReplacement++;
      continue;
    }
    final first = replacements.first;
    if (first is! JsonMap || first['value'] is! String) {
      throw const FormatException('Неправильная структура замены');
    }
    final edit = Edit(
      start,
      text.substring(start, start + length),
      first['value'] as String,
    );
    if (edit.original == edit.replacement) {
      rejected.add('Замена ничего не меняет');
    } else if (edits.any((e) => _overlaps(e, edit))) {
      rejected.add('Замены пересекаются или повторяются');
    } else {
      edits.add(edit);
    }
  }
  edits.sort((a, b) => a.start.compareTo(b.start));
  return {
    'output': applyEdits(text, edits),
    'applied_count': edits.length,
    'notice_count': matches.length,
    'without_replacement': withoutReplacement,
    'rejected': rejected,
  };
}

bool _overlaps(Edit left, Edit right) {
  if (left.start == right.start) return true;
  if (left.original.isEmpty) {
    return left.start > right.start && left.start < right.end;
  }
  if (right.original.isEmpty) {
    return right.start > left.start && right.start < left.end;
  }
  return left.start < right.end && right.start < left.end;
}
