import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

class Edit {
  const Edit(this.start, this.original, this.replacement);
  final int start;
  final String original;
  final String replacement;
  int get end => start + original.length;
}

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

String applyEdits(String text, List<Edit> edits) {
  var result = text;
  for (final edit in edits.reversed) {
    if (text.substring(edit.start, edit.end) != edit.original) {
      throw StateError('Исходный текст изменился');
    }
    result = result.replaceRange(edit.start, edit.end, edit.replacement);
  }
  return result;
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
Set<String> diffKeys(String before, String after) {
  final left = before.runes.toList(), right = after.runes.toList();
  final lengths = List.generate(
    left.length + 1,
    (_) => List<int>.filled(right.length + 1, 0),
  );
  for (var i = left.length - 1; i >= 0; i--) {
    for (var j = right.length - 1; j >= 0; j--) {
      lengths[i][j] = left[i] == right[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] > lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  var i = 0, j = 0, offset = 0;
  int? start;
  var insertion = <int>[];
  final keys = <String>{};
  void flush() {
    if (start == null) return;
    keys.add(jsonEncode([start, offset, String.fromCharCodes(insertion)]));
    start = null;
    insertion = [];
  }

  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] == right[j]) {
      flush();
      offset += left[i] > 0xffff ? 2 : 1;
      i++;
      j++;
    } else if (j < right.length &&
        (i == left.length || lengths[i][j + 1] >= lengths[i + 1][j])) {
      start ??= offset;
      insertion.add(right[j++]);
    } else {
      start ??= offset;
      offset += left[i] > 0xffff ? 2 : 1;
      i++;
    }
  }
  flush();
  return keys;
}

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
