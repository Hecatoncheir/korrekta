import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../integration_test/support/quality_data.dart';
import 'evaluate_app_quality.dart' show rows, writeJson, studyArgument;

Future<void> main(List<String> args) async {
  final study = studyArgument(args);
  final resultPath = '../benchmarks/results/2026-11-05/$study';
  await verifyQualityFreeze('..', study: study);
  final cases = await rows(File('../benchmarks/app-quality/cases-v1.jsonl'));
  final protocol = jsonDecode(
    await File('../benchmarks/$study/protocol-v1.json').readAsString(),
  ) as Map<String, dynamic>;
  final wire = await rows(File(p.join(resultPath, 'wire.jsonl')));
  final reports = <String, Object?>{};
  for (final (index, name) in ['quality', 'balanced'].indexed) {
    final data = await rows(File(p.join(resultPath, '$name.jsonl')));
    final model = (protocol['models'] as List<dynamic>)[index] as String;
    reports[name] = auditModel(cases, data, wire, model);
  }
  final report = {
    'datasetAndProductionHashesVerified': true,
    'productionSourceFiles': (protocol['sourceSha256'] as Map).length,
    'datasetSha256': await fileHash(
      File('../benchmarks/app-quality/cases-v1.jsonl'),
    ),
    'models': reports,
  };
  await writeJson(File(p.join(resultPath, 'audit.json')), report);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

Map<String, Object?> auditModel(
  List<Map<String, dynamic>> cases,
  List<Map<String, dynamic>> data,
  List<Map<String, dynamic>> wire,
  String model,
) {
  final byId = {for (final row in cases) row['id']: row};
  final present = data.map((row) => row['id']).toSet();
  require(
    data.length == cases.length && present.length == cases.length,
    'Неполный или повторный набор результатов: $model',
  );
  final calls = wire
      .where((row) => row['case'] != null && row['model'] == model)
      .toList();
  require(calls.length == cases.length, 'Другое число запросов: $model');
  for (final row in data) {
    final item = byId[row['id']];
    require(item != null, 'Неизвестный случай: ${row['id']}');
    auditRow(item!, row, calls, model);
  }
  final responses = calls.map(responseOf).toList();
  final seconds =
      responses
          .where((row) => row['total_duration'] is num)
          .map((row) => (row['total_duration'] as num) / 1e9)
          .toList()
        ..sort();
  return {
    'cases': data.length,
    'caseGenerationRequests': calls.length,
    'apis': {
      for (final api
          in calls.map((row) => row['api'] ?? '/api/generate').toSet())
        api as String: calls
            .where((row) => (row['api'] ?? '/api/generate') == api)
            .length,
    },
    'unchangedInputGoldAndMetadata': true,
    'recomputedScoresMatch': true,
    'requestHashModelContextVerified': true,
    'http200': calls.where((row) => row['responseStatus'] == 200).length,
    'modelStopped': responses
        .where((row) => row['done_reason'] == 'stop')
        .length,
    'modelLengthLimit': responses
        .where((row) => row['done_reason'] == 'length')
        .length,
    'medianOllamaSeconds': seconds[seconds.length ~/ 2],
    'rawModelPrimaryDiagnostic': rawSafety(
      data.where((row) => row['profile'] == 'empty').toList(),
      calls,
    ),
  };
}

Map<String, Object> rawSafety(
  List<Map<String, dynamic>> data,
  List<Map<String, dynamic>> calls,
) {
  final byId = {for (final call in calls) call['case']: responseOf(call)};
  final scored = <Map<String, Object>>[];
  final literalBraceCases = <String>[];
  final literalBraceRows = <Map<String, dynamic>>[];
  var invalid = 0;
  for (final row in data) {
    final output = rawText(byId[row['id']]!);
    if (output == null) {
      invalid++;
      continue;
    }
    if (output == '{') {
      literalBraceCases.add(row['id'] as String);
      literalBraceRows.add(row);
    }
    scored.add(score(QualityCase(row), output, true));
  }
  return {
    'cases': data.length,
    'invalidTextJson': invalid,
    'literalOpeningBraceCases': literalBraceCases,
    'literalBraceErrors': literalBraceRows
        .where((row) => row['kind'] == 'error')
        .length,
    'literalBraceControls': literalBraceRows
        .where((row) => row['kind'] == 'control')
        .length,
    'literalBraceErrorsRecoveredByApp': literalBraceRows
        .where((row) => row['kind'] == 'error' && row['score']['clean'] == true)
        .length,
    'literalBraceWithoutWarning': literalBraceRows
        .where((row) => row['complete'] == true)
        .length,
    'changedControls': scored
        .where((row) => row['falseControl'] == true)
        .length,
    'protectedFailures': scored
        .where((row) => (row['protectedLost'] as List).isNotEmpty)
        .length,
    'whitespaceFailures': scored
        .where((row) => row['whitespacePreserved'] != true)
        .length,
    'markupFailures': scored
        .where((row) => row['markupPreserved'] != true)
        .length,
  };
}

String? rawText(Map<String, dynamic> response) {
  try {
    final content =
        response['response'] ?? (response['message'] as Map?)?['content'];
    return switch (jsonDecode(content as String)) {
      {'text': final String text} => text,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

void auditRow(
  Map<String, dynamic> item,
  Map<String, dynamic> row,
  List<Map<String, dynamic>> calls,
  String model,
) {
  for (final key in item.keys) {
    require(
      jsonEncode(row[key]) == jsonEncode(item[key]),
      'Изменена разметка ${row['id']}: $key',
    );
  }
  final rescored = score(
    QualityCase(item),
    row['output'] as String,
    row['complete'] as bool,
  );
  require(jsonEncode(rescored) == jsonEncode(row['score']), 'Другая оценка');
  final call = calls.where((call) => call['case'] == item['id']).single;
  final body = call['requestBody'] as String;
  final request = jsonDecode(body) as Map<String, dynamic>;
  require(
    sha256.convert(utf8.encode(body)).toString() == call['requestSha256'],
    'Другая контрольная сумма HTTP-запроса',
  );
  require(
    row['model'] == model && request['model'] == model,
    'Выбор модели не совпадает',
  );
  require(
    (call['api'] ?? '/api/generate') ==
        (request.containsKey('messages') ? '/api/chat' : '/api/generate'),
    'API не соответствует форме запроса',
  );
  require(
    (request['options'] as Map)['num_ctx'] == 8192 &&
        requestHasInput(request, item['text'] as String),
    'Другое содержимое или контекст запроса',
  );
  final response = responseOf(call);
  require(response['model'] == model, 'Ответ от другой модели: ${item['id']}');
}

bool requestHasInput(Map<String, dynamic> request, String text) {
  final encoded = jsonEncode({'text': text});
  return switch (request) {
    {'raw': true, 'prompt': final String prompt} => prompt.contains(encoded),
    {
      'messages': [
        {'role': 'system', 'content': String _},
        {'role': 'user', 'content': final String content},
      ],
    } =>
      content == encoded && request['raw'] == null,
    _ => false,
  };
}

Map<String, dynamic> responseOf(Map<String, dynamic> call) =>
    jsonDecode(call['responseBody'] as String) as Map<String, dynamic>;

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
