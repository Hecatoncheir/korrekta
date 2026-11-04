import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/cli.dart'
    show request, generationOptions;
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/ensemble_roles.dart';
import 'package:korrekta_model_benchmark/src/ensemble_runtime.dart';
import 'package:korrekta_model_benchmark/src/response_contract.dart';

Future<Map<String, dynamic>> proposal(
  HttpClient client,
  Uri endpoint,
  String model,
  int context,
  Map<String, dynamic> row,
) async {
  if ((row['prompt_tokens'] as int) + 1024 >= context) {
    throw const FormatException('Недостаточный контекст');
  }
  final timer = Stopwatch()..start();
  Map<String, dynamic>? response;
  try {
    response = await request(client, endpoint, 'generate', {
      'model': model,
      'raw': true,
      'prompt': row['rendered_prompt'],
      'format': textResponseSchema,
      'stream': false,
      'think': false,
      'keep_alive': '10m',
      'options': {
        ...generationOptions(false),
        'num_ctx': context,
        'num_predict': 1024,
      },
    }).timeout(const Duration(seconds: 120));
    timer.stop();
    if (response['done_reason'] != 'stop') {
      throw const FormatException('Незавершённый ответ');
    }
    final parsed = jsonDecode(response['response'] as String);
    if (parsed is! Map<String, dynamic> ||
        parsed.length != 1 ||
        parsed['text'] is! String) {
      throw const FormatException('Неправильная структура ответа');
    }
    return {
      'text': row['text'],
      'output': parsed['text'],
      'schema_valid': true,
      'done_reason': 'stop',
      'response': response,
      'model_seconds': timer.elapsedMicroseconds / 1e6,
    };
  } catch (error) {
    timer.stop();
    return {
      'text': row['text'],
      'output': row['text'],
      'schema_valid': false,
      'error': error.toString(),
      'response': ?response,
      'model_seconds': timer.elapsedMicroseconds / 1e6,
    };
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('model', mandatory: true)
    ..addOption('context', mandatory: true)
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:11435')
    ..addOption('prompt', mandatory: true);
  EnsembleRuntime? runtime;
  final client = HttpClient();
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final endpoint = Uri.parse(options.option('endpoint')!);
    if (endpoint.scheme != 'http' ||
        !['127.0.0.1', 'localhost', '::1'].contains(endpoint.host)) {
      throw const FormatException('Нужен локальный адрес');
    }
    final model = options.option('model')!;
    final context = int.parse(options.option('context')!);
    final file = File(options.option('output')!);
    if (file.existsSync()) throw const FormatException('Файл уже существует');
    final rows = (await File(
      options.option('input')!,
    ).readAsLines()).map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    final prompt = await File(options.option('prompt')!).readAsString();
    final initialization = Stopwatch()..start();
    runtime = await EnsembleRuntime.open(ollama: endpoint.toString());
    initialization.stop();
    sink = file.openWrite();
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'model': model,
        'context': context,
        'runtime': await request(client, endpoint, 'version'),
        'model_details': await request(client, endpoint, 'show', {
          'model': model,
        }),
        'initialization_seconds': initialization.elapsedMicroseconds / 1e6,
        'dart_rss': ProcessInfo.currentRss,
        'timing': 'Инициализация отдельно; полный тёплый запрос включает генерацию, LT, словари, признаки и выбор. Транспорт готовой генерации через cachedGiga не означает повторное использование старого ответа.',
      }),
    );
    final cold = await proposal(client, endpoint, model, context, rows.first);
    sink.writeln(
      jsonEncode({
        'type': 'cold_start',
        ...cold,
        'resident': await request(client, endpoint, 'ps'),
      }),
    );
    await sink.flush();
    if (cold.containsKey('error')) {
      throw const FormatException(
        'Холодная проба не прошла, прогон остановлен',
      );
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final timer = Stopwatch()..start();
      Map<String, dynamic>? generated;
      try {
        generated = await proposal(client, endpoint, model, context, row);
        if (generated.containsKey('error')) {
          throw FormatException(generated['error'] as String);
        }
        final collected = await runtime.collect(
          row['text'] as String,
          prompt,
          cachedGiga: generated,
        );
        final features = await roleFeatures(
          collected,
          SharedLexicon(runtime.hunspell, runtime.symspell),
        );
        final selected = chooseRoles({
          ...collected,
          'role_features': features,
        }, 'inflections');
        timer.stop();
        sink.writeln(
          jsonEncode({
            'type': 'case',
            ...row,
            ...collected,
            'giga_output': generated['output'],
            'role_features': features,
            'selection': selected,
            'output': selected['output'],
            'expected': row['edits'],
            'model_seconds': generated['model_seconds'],
            'seconds': timer.elapsedMicroseconds / 1e6,
            'dart_rss': ProcessInfo.currentRss,
          }),
        );
      } catch (error) {
        timer.stop();
        sink.writeln(
          jsonEncode({
            'type': 'case',
            ...row,
            'expected': row['edits'],
            'output': row['text'],
            'error': error.toString(),
            'generation': ?generated,
            'seconds': timer.elapsedMicroseconds / 1e6,
          }),
        );
      }
      await sink.flush();
      if ((i + 1) % 25 == 0) {
        stdout.writeln('$model / $context: ${i + 1}/${rows.length}');
      }
    }
    sink.writeln(
      jsonEncode({
        'type': 'summary',
        'completed': true,
        'count': rows.length,
        'resident': await request(client, endpoint, 'ps'),
        'dart_rss': ProcessInfo.currentRss,
      }),
    );
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 64;
  } finally {
    await sink?.close();
    client.close(force: true);
    await runtime?.close();
  }
}
