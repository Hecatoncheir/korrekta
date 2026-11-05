import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final study = studyArgument(args);
  final directory = Directory('../benchmarks/results/2026-11-05/$study');
  final partial = args.contains('--partial');
  final dataset = await rows(File('../benchmarks/app-quality/cases-v1.jsonl'));
  final ids = dataset.map((row) => row['id'] as String).toSet();
  final summaries = <String, Object?>{};
  final review = <Map<String, dynamic>>[];
  final paired = <Map<String, dynamic>>[];
  for (final model in ['quality', 'balanced']) {
    final data = await rows(File(p.join(directory.path, '$model.jsonl')));
    final present = data.map((row) => row['id'] as String).toSet();
    if (data.length != present.length || !ids.containsAll(present)) {
      throw StateError('Повтор или неизвестный случай: $model');
    }
    if (!partial && present.length != ids.length) {
      throw StateError(
        'Прогон не завершён: $model ${present.length}/${ids.length}',
      );
    }
    final primary = data.where((row) => row['profile'] == 'empty').toList();
    final personal = data.where((row) => row['profile'] == 'personal').toList();
    summaries[model] = {
      'recorded': data.length,
      'expected': ids.length,
      'primary': summarize(primary),
      'personal': summarize(personal),
      'groups': {
        for (final group in [
          'grammar',
          'names',
          'format',
          'style',
          'technical',
        ])
          group: summarize(
            primary.where((row) => row['group'] == group).toList(),
          ),
      },
    };
    review.addAll(
      primary.where(needsReview).map((row) => {'profileModel': model, ...row}),
    );
    paired.addAll(pairRows(model, primary, personal));
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summaries));
  if (partial) return;
  await writeJson(File(p.join(directory.path, 'summary.json')), summaries);
  await writeJson(File(p.join(directory.path, 'review.json')), review);
  await writeJson(
    File(p.join(directory.path, 'personal-comparison.json')),
    paired,
  );
}

String studyArgument(List<String> args) =>
    args.where((arg) => arg.startsWith('--study=')).firstOrNull?.substring(8) ??
    'app-quality';

Future<List<Map<String, dynamic>>> rows(File file) async {
  if (!await file.exists()) return [];
  return (await file.readAsLines())
      .where((line) => line.isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();
}

Map<String, Object?> summarize(List<Map<String, dynamic>> data) {
  final errors = data.where((row) => row['kind'] == 'error').toList();
  final controls = data.where((row) => row['kind'] == 'control').toList();
  final durations = data.map((row) => row['elapsedMs'] as int).toList()..sort();
  return {
    'total': data.length,
    'errors': errors.length,
    'controls': controls.length,
    'cleanErrors': errors.where(clean).length,
    'unchangedErrors': errors
        .where((row) => row['output'] == row['text'])
        .length,
    'changedWrongErrors': errors
        .where((row) => row['output'] != row['text'] && !clean(row))
        .length,
    'changedControls': controls
        .where((row) => row['output'] != row['text'])
        .length,
    'fullyCheckedUnchangedControls': controls.where(clean).length,
    'incomplete': data.where((row) => row['complete'] != true).length,
    'protectedFailures': data
        .where(
          (row) => (metrics(row)['protectedLost'] as List<dynamic>).isNotEmpty,
        )
        .length,
    'whitespaceFailures': data
        .where((row) => metrics(row)['whitespacePreserved'] != true)
        .length,
    'markupFailures': data
        .where((row) => metrics(row)['markupPreserved'] != true)
        .length,
    'controlsWithCards': controls
        .where((row) => (row['cards'] as List<dynamic>).isNotEmpty)
        .length,
    'controlsWithRecommendations': controls
        .where((row) => (row['recommendedCount'] as int) > 0)
        .length,
    'recommendedButUnchanged': data
        .where(
          (row) =>
              (row['recommendedCount'] as int) > 0 &&
              row['output'] == row['text'],
        )
        .length,
    'wireModelVerified': data.every((row) => row['wireModelVerified'] == true),
    'medianMs': percentile(durations, .5),
    'p95Ms': percentile(durations, .95),
  };
}

Map<String, dynamic> metrics(Map<String, dynamic> row) =>
    row['score'] as Map<String, dynamic>;
bool clean(Map<String, dynamic> row) => metrics(row)['clean'] == true;
bool needsReview(Map<String, dynamic> row) =>
    !clean(row) ||
    row['kind'] == 'control' && (row['cards'] as List<dynamic>).isNotEmpty;
int? percentile(List<int> sorted, double fraction) =>
    sorted.isEmpty ? null : sorted[((sorted.length - 1) * fraction).round()];

Iterable<Map<String, dynamic>> pairRows(
  String model,
  List<Map<String, dynamic>> primary,
  List<Map<String, dynamic>> personal,
) sync* {
  final byId = {for (final row in primary) row['id']: row};
  for (final after in personal) {
    final before = byId[after['sourceId']];
    if (before == null) throw StateError('Нет исходного случая парного опыта');
    yield {
      'model': model,
      'id': after['sourceId'],
      'text': after['text'],
      'expected': after['expected'],
      'emptyOutput': before['output'],
      'personalOutput': after['output'],
      'emptyComplete': before['complete'],
      'personalComplete': after['complete'],
      'emptyScore': before['score'],
      'personalScore': after['score'],
    };
  }
}

Future<void> writeJson(File file, Object value) async => file.writeAsString(
  '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  flush: true,
);
