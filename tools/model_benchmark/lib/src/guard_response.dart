import 'scoring.dart';
import 'text_guard.dart';
import 'text_scoring.dart';

const guardVersion = 'text-guard-v1';

JsonMap editJson(Edit edit) => {
  'start': edit.start,
  'end': edit.end,
  'original': edit.original,
  'replacement': edit.replacement,
};

/// Фильтрация видит только исходник, выход модели и личный словарь.
/// Эталоны используются после неё исключительно при расчёте оценок.
JsonMap protectResponse(JsonMap row, {List<String> names = const []}) {
  final text = row['text'] as String;
  final proposed = row['output'] as String;
  final timer = Stopwatch()..start();
  final valid =
      row['schema_valid'] == true &&
      row['done_reason'] == 'stop' &&
      !row.containsKey('error');
  final result = valid
      ? guardText(text, proposed, names: names)
      : GuardResult(
          text,
          const [],
          const [],
          const [],
          failure: 'invalid_model_response',
        );
  final output = result.output;
  timer.stop();
  final expected = row['expected'] as List<dynamic>;
  final predicted = output == text
      ? <dynamic>[]
      : <dynamic>[
          {'original': text, 'replacement': output},
        ];
  return {
    ...row,
    'unfiltered_output': proposed,
    'model_seconds': row['seconds'],
    'guard_seconds': timer.elapsedMicroseconds / 1e6,
    'seconds': (row['seconds'] as num) + timer.elapsedMicroseconds / 1e6,
    'guard': {
      'version': guardVersion,
      'status':
          result.failure ??
          (result.accepted.isEmpty && result.rejected.isNotEmpty
              ? 'all_changes_blocked'
              : 'ok'),
      'accepted': result.accepted.map(editJson).toList(),
      'rejected': [
        for (final rejected in result.rejected)
          {...editJson(rejected.edit), 'reason': rejected.reason},
      ],
      'protected_spans': [
        for (final span in result.spans)
          {'start': span.start, 'end': span.end, 'reason': span.reason},
      ],
    },
    ...scoreCase(text, expected, predicted),
    ...scoreText(text, expected, output),
    if (!valid || result.failure != null) 'exact': false,
  };
}
