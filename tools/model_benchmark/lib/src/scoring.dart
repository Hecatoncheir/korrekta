import 'dart:convert';

import 'text_diff.dart';
export 'text_diff.dart' show Edit, applyEdits, diffEdits;

typedef JsonMap = Map<String, dynamic>;

class LocatedEdits {
  const LocatedEdits(this.edits, this.rejected);
  final List<Edit> edits;
  final List<String> rejected;
}

LocatedEdits locateEdits(String text, List<dynamic> items) {
  final accepted = <Edit>[];
  final rejected = <String>[];
  for (final item in items) {
    if (item is! JsonMap ||
        item['original'] is! String ||
        item['replacement'] is! String) {
      rejected.add('Неправильная структура замены');
      continue;
    }
    final original = item['original'] as String;
    final replacement = item['replacement'] as String;
    final start = original.isEmpty ? -1 : text.indexOf(original);
    if (start < 0 || original == replacement) {
      rejected.add('Фрагмент не найден или замена ничего не меняет');
      continue;
    }
    if (text.indexOf(original, start + 1) >= 0) {
      rejected.add('Исходный фрагмент неоднозначен');
      continue;
    }
    accepted.add(Edit(start, original, replacement));
  }
  accepted.sort((a, b) => a.start.compareTo(b.start));
  final disjoint = <Edit>[];
  for (final edit in accepted) {
    if (disjoint.isNotEmpty && edit.start < disjoint.last.end) {
      rejected.add('Замены пересекаются или повторяются');
      continue;
    }
    disjoint.add(edit);
  }
  return LocatedEdits(disjoint, rejected);
}

JsonMap scoreCase(
  String text,
  List<dynamic> expected,
  List<dynamic> predicted,
) {
  final gold = locateEdits(text, expected);
  if (gold.rejected.isNotEmpty) {
    throw FormatException('Ошибка эталона: ${gold.rejected}');
  }
  final actual = locateEdits(text, predicted);
  final output = applyEdits(text, actual.edits);
  final goldEffects = gold.edits
      .map((edit) => diffKeys(text, applyEdits(text, [edit])))
      .toList();
  final allGold = goldEffects.expand((keys) => keys).toSet();
  final actualEffects = diffKeys(text, output);
  final matched = goldEffects
      .where((keys) => keys.difference(actualEffects).isEmpty)
      .length;
  final correctPredictions = actual.edits.where((edit) {
    final keys = diffKeys(text, applyEdits(text, [edit]));
    return keys.isNotEmpty && keys.difference(allGold).isEmpty;
  }).length;
  return {
    'tp': matched,
    'correct_predictions': correctPredictions,
    'fp': actual.edits.length - correctPredictions,
    'fn': gold.edits.length - matched,
    'rejected': actual.rejected,
    'control': expected.isEmpty,
    'false_notice': expected.isEmpty && predicted.isNotEmpty,
    'exact': output == applyEdits(text, gold.edits) && actual.rejected.isEmpty,
    'output': output,
  };
}

// Одинаковый эффект оценивается одинаково при разной ширине контекста правки.
Set<String> diffKeys(String before, String after) => {
  for (final edit in diffEdits(before, after))
    jsonEncode([edit.start, edit.end, edit.replacement]),
};

bool validSchema(Object? value) {
  if (value is! JsonMap || value['edits'] is! List<dynamic>) return false;
  final edits = value['edits'] as List<dynamic>;
  if (edits.length > 8) return false;
  return edits.every(
    (item) =>
        item is JsonMap &&
        item['original'] is String &&
        item['replacement'] is String &&
        item['explanation'] is String &&
        const {
          'grammar',
          'spelling',
          'punctuation',
          'typography',
        }.contains(item['category']),
  );
}
