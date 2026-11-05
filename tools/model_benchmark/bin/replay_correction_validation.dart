import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/correction_response.dart';

Future<void> main() async {
  const base = '../../benchmarks/results/2026-11-05';
  final cases = await rows('../../benchmarks/app-quality/cases-v1.jsonl');
  final byId = {for (final item in cases) item['id']: item['text'] as String};
  final wire = await rows('$base/app-quality/wire.jsonl');
  final results = <Map<String, Object>>[];
  for (final row in wire.where((row) => row['case'] != null)) {
    final response = jsonDecode(row['responseBody'] as String) as Map;
    final content = response['response'] as String;
    String? error;
    try {
      readCorrectionText(byId[row['case']]!, content);
    } on FormatException catch (failure) {
      error = failure.message;
    }
    results.add({
      'case': row['case'] as String,
      'model': row['model'] as String,
      'literalBrace': (jsonDecode(content) as Map)['text'] == '{',
      'rejected': error != null,
      'reason': ?error,
    });
  }
  final braces = results.where((row) => row['literalBrace'] == true).toList();
  final report = {
    'baselineCases': results.length,
    'literalBraceCases': braces.length,
    'literalBraceRejected': braces
        .where((row) => row['rejected'] == true)
        .length,
    'otherRejected': results
        .where((row) => row['literalBrace'] != true && row['rejected'] == true)
        .length,
    'cases': results.where((row) => row['rejected'] == true).toList(),
  };
  await File('$base/text-response-fix/replayed-validation.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    flush: true,
  );
  stdout.writeln(jsonEncode({...report}..remove('cases')));
  if (braces.length != 26 || braces.any((row) => row['rejected'] != true)) {
    throw StateError('Не все 26 сохранённых непригодных ответов отклонены');
  }
}

Future<List<Map<String, dynamic>>> rows(String path) async =>
    (await File(path).readAsLines())
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
