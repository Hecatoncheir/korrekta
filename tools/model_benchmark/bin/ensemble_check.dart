import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/ensemble_runtime.dart';
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';
import 'package:korrekta_model_benchmark/src/languagetool.dart';
import 'package:korrekta_model_benchmark/src/text_guard.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('proposal-prompt', mandatory: true)
    ..addOption('selection-prompt', mandatory: true)
    ..addOption('store', defaultsTo: 'E:/korrekta/dictionaries-v1')
    ..addOption('ollama', defaultsTo: 'http://127.0.0.1:11435')
    ..addOption('lt', defaultsTo: 'http://127.0.0.1:8081')
    ..addOption('names')
    ..addFlag('collect-only', negatable: false)
    ..addFlag('prepared', negatable: false);
  EnsembleRuntime? runtime;
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final output = File(options.option('output')!);
    if (output.existsSync()) throw const FormatException('Файл уже существует');
    final proposal = await File(options.option('proposal-prompt')!)
        .readAsString();
    final selection = await File(options.option('selection-prompt')!)
        .readAsString();
    final names = options.option('names') == null
        ? <String>[]
        : (jsonDecode(
            await File(options.option('names')!).readAsString(),
          ) as List<dynamic>).cast<String>();
    final rows = (await File(options.option('input')!).readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    runtime = await EnsembleRuntime.open(
      store: options.option('store')!,
      ollama: options.option('ollama')!,
      languageTool: options.option('lt')!,
    );
    await output.parent.create(recursive: true);
    sink = output.openWrite();
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'version': 'ensemble-v1',
        'model': ensembleModel,
        'ollama': options.option('ollama'),
        'lt': options.option('lt'),
        'personal_names': names,
        'options': {'temperature': 0, 'seed': 42, 'num_ctx': 8192},
        'timing': 'Текущая обработка; сохранённая генерация модели не входит, инициализация словарей отдельно',
      }),
    );
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final text = row['text'] as String;
      final prepared = options.flag('prepared')
          ? row
          : await runtime.collect(
              text,
              proposal,
              names: names,
              cachedGiga: row['cached_giga_row'] as Map<String, dynamic>?,
            );
      final selected = options.flag('collect-only')
          ? <String, dynamic>{'selection_seconds': 0.0}
          : await runtime.select(prepared, selection);
      final slots = (prepared['slots'] as List<dynamic>)
          .map((s) => WordChoices.fromJson(s as Map<String, dynamic>))
          .toList();
      final matches =
          (prepared['lt_response'] as Map<String, dynamic>)['matches']
              as List<dynamic>;
      final ltOutput = guardText(
        text,
        applyLanguageTool(text, matches)['output'] as String,
        names: names,
      ).output;
      sink.writeln(
        jsonEncode({
          'type': 'case',
          'id': row['id'],
          'category': row['category'],
          ...prepared,
          ...selected,
          'expected': row['edits'] ?? row['expected'],
          'run': row['run'],
          'lt_output': ltOutput,
          'priority_output': selectEnsembleChoices(
            text,
            slots,
            List.filled(slots.length, 1),
          ).output,
          'seconds':
              (prepared['collection_seconds'] as num) +
              (selected['selection_seconds'] as num),
          'complete':
              !prepared.containsKey('collection_error') &&
              !selected.containsKey('selection_error'),
        }),
      );
      await sink.flush();
      if ((i + 1) % 25 == 0) {
        stdout.writeln('Общий режим: ${i + 1}/${rows.length}');
      }
    }
    sink.writeln(
      jsonEncode({'type': 'summary', 'count': rows.length, 'completed': true}),
    );
    stdout.writeln('Проверено: ${rows.length}');
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
