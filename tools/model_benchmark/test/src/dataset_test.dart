import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/scoring.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Набор содержит 200 уникальных текстов и 40 примеров для разработки',
    () {
      final cases = File('../../benchmarks/cases-v1.jsonl')
          .readAsLinesSync()
          .where((line) => line.isNotEmpty)
          .map((line) => jsonDecode(line) as JsonMap)
          .toList();
      expect(cases, hasLength(200));
      expect(cases.map((item) => item['id']).toSet(), hasLength(200));
      expect(cases.map((item) => item['text']).toSet(), hasLength(200));
      expect(cases.where((item) => item['split'] == 'dev'), hasLength(40));
      expect(cases.where((item) => item['split'] == 'test'), hasLength(160));
      expect(
        cases.where((item) => (item['edits'] as List<dynamic>).isEmpty),
        hasLength(80),
      );
      for (final item in cases) {
        final expected = item['edits'] as List<dynamic>;
        final score = scoreCase(item['text'] as String, expected, expected);
        expect(score['exact'], true, reason: item['id'] as String);
        expect(score['tp'], expected.length, reason: item['id'] as String);
        expect(score['fp'], 0, reason: item['id'] as String);
      }
    },
  );
}
