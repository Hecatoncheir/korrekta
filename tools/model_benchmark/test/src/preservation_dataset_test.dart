import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('Отложенные пары промптов исправляют ошибку и сохраняют защиту', () {
    final rows = File('../../benchmarks/gigachat-prompts/holdout-v1.jsonl')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as JsonMap)
        .toList();
    expect(rows, hasLength(80));
    expect(rows.map((row) => row['id']).toSet(), hasLength(80));
    final controls = {
      for (final row in rows)
        if ((row['edits'] as List<dynamic>).isEmpty) row['pair']: row,
    };
    expect(controls, hasLength(40));
    for (final row in rows.where(
      (row) => (row['edits'] as List<dynamic>).isNotEmpty,
    )) {
      final text = row['text'] as String;
      final edits = locateEdits(text, row['edits'] as List<dynamic>);
      expect(edits.rejected, isEmpty);
      final target = controls[row['pair']]!['text'] as String;
      expect(applyEdits(text, edits.edits), target);
      for (final part in row['protected'] as List<dynamic>) {
        expect(text.split(part as String).length, target.split(part).length);
      }
    }
  });
  test('Новые пары исправляют только ошибку вне защищённых фрагментов', () {
    final cases = File('../../benchmarks/preservation/cases-v1.jsonl')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as JsonMap)
        .toList();
    final oldTexts = File('../../benchmarks/cases-v1.jsonl')
        .readAsLinesSync()
        .map((line) => (jsonDecode(line) as JsonMap)['text'])
        .toSet();
    expect(cases, hasLength(120));
    expect(cases.map((row) => row['id']).toSet(), hasLength(120));
    expect(cases.map((row) => row['text']).toSet(), hasLength(120));
    expect(cases.every((row) => !oldTexts.contains(row['text'])), true);
    final pairs = <int, List<JsonMap>>{};
    for (final row in cases) {
      pairs.putIfAbsent(row['pair'] as int, () => []).add(row);
    }
    expect(pairs, hasLength(60));
    for (final pair in pairs.values) {
      expect(pair, hasLength(2));
      final correct = pair.singleWhere(
        (row) => (row['edits'] as List<dynamic>).isEmpty,
      );
      final error = pair.singleWhere(
        (row) => (row['edits'] as List<dynamic>).isNotEmpty,
      );
      final text = error['text'] as String;
      final expected = error['edits'] as List<dynamic>;
      expect(expected, hasLength(1));
      final edits = locateEdits(text, expected);
      expect(edits.rejected, isEmpty);
      expect(applyEdits(text, edits.edits), correct['text']);
      expect(error['protected'], correct['protected']);
      for (final part in error['protected'] as List<dynamic>) {
        final fragment = part as String;
        expect(fragment, isNotEmpty);
        final count = text.split(fragment).length - 1;
        expect(count, greaterThan(0));
        expect((correct['text'] as String).split(fragment).length - 1, count);
      }
    }
  });
}
