import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'scoring.dart';
import 'text_scoring.dart';

Future<int> runTextComparison(List<String> paths) async {
  if (paths.isEmpty) {
    stderr.writeln('Передайте пути к результатам JSONL одного набора и split.');
    return 64;
  }
  try {
    final results = <JsonMap>[];
    Map<String, String>? reference;
    for (final path in paths) {
      final rows = (await File(path).readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as JsonMap)
          .where((row) => row['type'] == 'case')
          .toList();
      if (rows.isEmpty) throw const FormatException('Нет результатов');
      final signature = {
        for (final row in rows)
          row['id'] as String: jsonEncode([row['text'], row['expected']]),
      };
      reference ??= signature;
      if (signature.length != rows.length ||
          signature.length != reference.length ||
          signature.entries.any((e) => reference![e.key] != e.value)) {
        throw FormatException('Наборы примеров не совпадают: $path');
      }
      final scored = [
        for (final row in rows)
          {
            'id': row['id'],
            'category': row['category'],
            ...scoreText(
              row['text'] as String,
              row['expected'] as List<dynamic>,
              row['output'] as String,
            ),
          },
      ];
      final times = rows.map((row) => row['seconds'] as num).toList()..sort();
      results.add({
        'path': path,
        ...summarizeTexts(scored),
        'median_seconds': times.length.isOdd
            ? times[times.length ~/ 2]
            : (times[times.length ~/ 2 - 1] + times[times.length ~/ 2]) / 2,
        'p95_seconds': times[max(0, (times.length * .95).ceil() - 1)],
        'categories': {
          for (final category in scored.map((row) => row['category']).toSet())
            category as String: summarizeTexts(
              scored.where((row) => row['category'] == category).toList(),
            ),
        },
        'cases': scored,
      });
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'metric': 'text-effects-v1',
        'description':
            'Общий Unicode LCS diff итогового текста без нормализации',
        'results': results,
      }),
    );
    return 0;
  } catch (error) {
    stderr.writeln(error);
    return 65;
  }
}

JsonMap summarizeTexts(List<JsonMap> rows) {
  int sum(String key) => rows.fold(0, (n, row) => n + (row[key] as int));
  double? ratio(int n, int d) => d == 0 ? null : n / d;
  final tp = sum('atomic_tp'), fp = sum('atomic_fp'), fn = sum('atomic_fn');
  final matched = sum('matched_corrections'), gold = sum('gold_corrections');
  final controls = rows.where((row) => row['control'] == true).length;
  final changed = rows.where((row) => row['changed_control'] == true).length;
  final exact = rows.where((row) => row['exact'] == true).length;
  return {
    'count': rows.length,
    'atomic_tp': tp,
    'atomic_fp': fp,
    'atomic_fn': fn,
    'atomic_precision': ratio(tp, tp + fp),
    'atomic_recall': ratio(tp, tp + fn),
    'matched_corrections': matched,
    'gold_corrections': gold,
    'correction_recall': ratio(matched, gold),
    'controls': controls,
    'changed_controls': changed,
    'changed_control_rate': ratio(changed, controls),
    'exact_count': exact,
    'exact_rate': ratio(exact, rows.length),
  };
}
