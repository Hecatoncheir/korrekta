import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/ensemble_roles.dart';
import 'package:korrekta_model_benchmark/src/ensemble_runtime.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';

Future<Map<String, dynamic>> removeChannel(
  EnsembleRuntime runtime,
  Map<String, dynamic> row,
  String source,
  String profile,
) async {
  List<WordChoices> slots(String key) => (row[key] as List<dynamic>)
      .map((s) => WordChoices.fromJson(s as Map<String, dynamic>))
      .toList();
  final text = row['text'] as String;
  final matches = source == 'languagetool'
      ? <dynamic>[]
      : (row['lt_response'] as Map<String, dynamic>)['matches']
            as List<dynamic>;
  final pool = buildEnsemble(
    text,
    hunspell: source == 'hunspell' ? [] : slots('hunspell_slots'),
    symspell: source == 'symspell' ? [] : slots('symspell_slots'),
    matches: matches,
    gigaOutput: source == 'gigachat' ? text : row['giga_output'] as String,
  );
  final changed = {
    ...pool.payload(),
    'lt_response': {'matches': matches},
  };
  final features = await roleFeatures(
    changed,
    SharedLexicon(runtime.hunspell, runtime.symspell),
  );
  return {
    ...changed,
    'role_features': features,
    'result': chooseRoles({...changed, 'role_features': features}, profile),
  };
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('profile', mandatory: true);
  EnsembleRuntime? runtime;
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final file = File(options.option('output')!);
    if (file.existsSync()) throw const FormatException('Файл уже существует');
    final rows = (await File(options.option('input')!).readAsLines())
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .where((r) => r['type'] == 'case')
        .toList();
    runtime = await EnsembleRuntime.open();
    sink = file.openWrite();
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'profile': options.option('profile'),
        'note': 'Отключаются только каналы предложений, общий словарь распознавания не меняется',
      }),
    );
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final channels = <String, dynamic>{};
      for (final source in [
        'gigachat',
        'languagetool',
        'hunspell',
        'symspell',
      ]) {
        channels[source] = await removeChannel(
          runtime,
          row,
          source,
          options.option('profile')!,
        );
      }
      sink.writeln(jsonEncode({...row, 'ablations': channels}));
      await sink.flush();
      if ((i + 1) % 100 == 0) {
        stdout.writeln('Вклад каналов ${i + 1}/${rows.length}');
      }
    }
    sink.writeln(
      jsonEncode({'type': 'summary', 'completed': true, 'count': rows.length}),
    );
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 64;
  } finally {
    await sink?.close();
    await runtime?.close();
  }
}
