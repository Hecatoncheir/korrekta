import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/ensemble_runtime.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';

Map<String, dynamic> compactRow(Map<String, dynamic> row) {
  final slots = (row['slots'] as List<dynamic>).cast<Map<String, dynamic>>();
  final mappings = <List<int>>[];
  final compact = <Map<String, dynamic>>[];
  for (final slot in slots) {
    final sources = (slot['sources'] as List<dynamic>)
        .map((s) => (s as List<dynamic>).cast<String>())
        .toList();
    final indexes = <int>{0};
    for (final source in ['gigachat', 'languagetool', 'hunspell', 'symspell']) {
      final found = sources.indexWhere((s) => s.contains(source));
      if (found >= 0) indexes.add(found);
    }
    final ids = indexes.toList();
    mappings.add(ids);
    compact.add({
      ...slot,
      'options': [for (final i in ids) (slot['options'] as List<dynamic>)[i]],
      'sources': [for (final i in ids) sources[i]],
    });
  }
  return {...row, 'compact_slots': compact, 'compact_mappings': mappings};
}

Map<String, dynamic> compactPayload(Map<String, dynamic> row) => {
  'text': row['text'],
  'fragments': [
    for (final slot
        in (row['compact_slots'] as List<dynamic>).cast<Map<String, dynamic>>())
      {
        'id': slot['id'],
        'start': slot['start'],
        'before': slot['original'],
        'variants': [
          for (var i = 0; i < (slot['options'] as List<dynamic>).length; i++)
            {
              'id': i,
              'text': (slot['options'] as List<dynamic>)[i],
              'from': (slot['sources'] as List<dynamic>)[i],
            },
        ],
      },
  ],
};

Future<Map<String, dynamic>> decide(
  EnsembleRuntime runtime,
  Map<String, dynamic> row,
  String system,
) async {
  final text = row['text'] as String;
  final slots = (row['compact_slots'] as List<dynamic>)
      .map((s) => WordChoices.fromJson(s as Map<String, dynamic>))
      .toList();
  Map<String, dynamic>? response;
  try {
    final choices = <int>[];
    if (slots.isNotEmpty) {
      response = await runtime.generate(
        gigaPrompt(system, compactPayload(row)),
        choicesSchema(slots),
        512,
      );
      choices.addAll(
        parseChoices(response['response'] as String, slots.length),
      );
    }
    final mappings = (row['compact_mappings'] as List<dynamic>)
        .cast<List<dynamic>>();
    final full = [
      for (var i = 0; i < choices.length; i++) mappings[i][choices[i]] as int,
    ];
    return {
      'output': selectEnsembleChoices(text, slots, choices).output,
      'choices': full,
      'compact_choices': choices,
      'response': ?response,
    };
  } catch (error) {
    return {'output': text, 'error': error.toString(), 'response': ?response};
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('prompt')
    ..addFlag('prepare', negatable: false);
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
    final preparing = options.flag('prepare');
    final system = preparing
        ? ''
        : await File(options.option('prompt')!).readAsString();
    if (!preparing) runtime = await EnsembleRuntime.open();
    await file.parent.create(recursive: true);
    sink = file.openWrite();
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'mode': preparing ? 'prepare' : 'compact',
      }),
    );
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final result = preparing
          ? compactRow(row)
          : {...row, 'compact_result': await decide(runtime!, row, system)};
      sink.writeln(jsonEncode(result));
      await sink.flush();
      if ((i + 1) % 50 == 0)
        stdout.writeln('Компактный выбор ${i + 1}/${rows.length}');
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
