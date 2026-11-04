import 'dart:convert';

import 'guard_response.dart';
import 'languagetool.dart';
import 'languagetool_gate.dart';
import 'scoring.dart';
import 'text_scoring.dart';

/// Эталоны используются только после решений обоих механизмов.
Map<String, JsonMap> confirmationProfiles(
  JsonMap row,
  JsonMap response,
  double languageToolSeconds,
) {
  final text = row['text'] as String;
  final matches = response['matches'] as List<dynamic>;
  final giga = protectResponse(row);
  final valid =
      row['schema_valid'] == true &&
      row['done_reason'] == 'stop' &&
      !row.containsKey('error');
  final timer = Stopwatch()..start();
  final confirmation = confirmText(
    text,
    valid ? row['output'] as String : text,
    matches,
  );
  timer.stop();
  final output = confirmation.output;
  final joint = <String, dynamic>{
    ...giga,
    ..._score(row, output),
    'seconds':
        (row['seconds'] as num) +
        languageToolSeconds +
        timer.elapsedMicroseconds / 1e6,
    'languagetool_seconds': languageToolSeconds,
    'confirmation_seconds': timer.elapsedMicroseconds / 1e6,
    'confirmation': {
      'version': languageToolGateVersion,
      'status':
          confirmation.guard.failure ??
          (confirmation.unconfirmed.isEmpty ? 'ok' : 'unconfirmed_changes'),
      'confirmed': [
        for (final item in confirmation.confirmed)
          {...editJson(item.edit), 'rule_id': item.ruleId},
      ],
      'unconfirmed': confirmation.unconfirmed.map(editJson).toList(),
    },
    if (!valid || confirmation.guard.failure != null) 'exact': false,
  };
  final ltOutput = applyLanguageTool(text, matches)['output'] as String;
  final lt = <String, dynamic>{
    for (final key in ['type', 'id', 'category', 'text', 'expected'])
      key: row[key],
    ..._score(row, ltOutput),
    'schema_valid': true,
    'done_reason': 'stop',
    'content': jsonEncode(response),
    'seconds': languageToolSeconds,
    'response': response,
  };
  return {
    'giga-dart': giga,
    'lt-first': lt,
    'lt-dart': protectResponse(lt),
    'joint': joint,
  };
}

JsonMap _score(JsonMap row, String output) {
  final text = row['text'] as String;
  final expected = row['expected'] as List<dynamic>;
  final predicted = output == text
      ? <dynamic>[]
      : <dynamic>[
          {'original': text, 'replacement': output},
        ];
  return {
    'predicted': predicted,
    ...scoreCase(text, expected, predicted),
    ...scoreText(text, expected, output),
  };
}
