import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/cli.dart'
    show request, generationOptions;
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';
import 'package:korrekta_model_benchmark/src/scoring.dart';

const model = 'hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M';

Future<JsonMap> decide(HttpClient client, Uri endpoint, JsonMap row) async {
  final slots = (row['slots'] as List<dynamic>)
      .cast<JsonMap>()
      .map(WordChoices.fromJson)
      .toList();
  final text = row['text'] as String;
  if (slots.isEmpty) {
    return {
      'output': text,
      'choices': <int>[],
      'status': 'no_candidates',
      'model_seconds': 0.0,
      'validation_seconds': 0.0,
    };
  }
  final timer = Stopwatch()..start();
  JsonMap? response;
  try {
    response = await request(client, endpoint, 'generate', {
      'model': model,
      'prompt': row['rendered_prompt'],
      'raw': true,
      'stream': false,
      'think': false,
      'format': choicesSchema(slots),
      'options': {...generationOptions(false), 'num_predict': 256},
      'keep_alive': '10m',
    }).timeout(const Duration(seconds: 120));
    timer.stop();
    if (response['done_reason'] != 'stop') {
      throw const FormatException('Незавершённый ответ');
    }
    final validation = Stopwatch()..start();
    final choices = parseChoices(response['response'] as String, slots.length);
    final selected = selectChoices(text, slots, choices);
    validation.stop();
    return {
      'output': selected.output,
      'choices': choices,
      'status': selected.edits.isEmpty ? 'kept_all' : 'selected',
      'model_seconds': timer.elapsedMicroseconds / 1e6,
      'validation_seconds': validation.elapsedMicroseconds / 1e6,
      'response': response,
    };
  } catch (error) {
    timer.stop();
    return {
      'output': text,
      'status': 'invalid_response',
      'error': error.toString(),
      'model_seconds': timer.elapsedMicroseconds / 1e6,
      'validation_seconds': 0.0,
      'response': ?response,
    };
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:11435')
    ..addFlag('probe', negatable: false);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final endpoint = Uri.parse(options.option('endpoint')!);
    if (endpoint.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost', '::1'].contains(endpoint.host)) {
      throw const FormatException('Нужен локальный Ollama');
    }
    final output = File(options.option('output')!);
    if (output.existsSync()) throw const FormatException('Файл уже существует');
    final rows = (await File(
      options.option('input')!,
    ).readAsLines()).map((line) => jsonDecode(line) as JsonMap).toList();
    await output.parent.create(recursive: true);
    sink = output.openWrite();
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'model': model,
        'ollama': await request(client, endpoint, 'version'),
        'model_details': await request(client, endpoint, 'show', {
          'model': model,
        }),
        'options': {...generationOptions(false), 'num_predict': 256},
        'input': options.option('input'),
        'endpoint': endpoint.toString(),
      }),
    );
    final cold = rows.firstWhere(
      (row) => (row['slots'] as List<dynamic>).isNotEmpty,
    );
    final firstDecision = await decide(client, endpoint, cold);
    sink.writeln(
      jsonEncode({
        'type': 'cold_start',
        'id': cold['id'],
        'rendered_prompt_sha256': cold['rendered_prompt_sha256'],
        ...firstDecision,
      }),
    );
    await sink.flush();
    if (firstDecision.containsKey('error')) {
      throw const FormatException(
        'Проба формата не прошла; основной отбор остановлен',
      );
    }
    if (options.flag('probe')) {
      sink.writeln(
        jsonEncode({'type': 'summary', 'completed': true, 'count': 0}),
      );
      stdout.writeln('Проба формата прошла');
      return;
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final decision = await decide(client, endpoint, row);
      sink.writeln(
        jsonEncode({
          'type': 'case',
          ...row,
          'rendered_prompt': null,
          ...decision,
          'seconds':
              (row['hunspell_seconds'] as num) +
              (decision['model_seconds'] as num) +
              (decision['validation_seconds'] as num),
        }),
      );
      await sink.flush();
      if ((i + 1) % 100 == 0) stdout.writeln('Отбор: ${i + 1}/${rows.length}');
    }
    sink.writeln(
      jsonEncode({'type': 'summary', 'completed': true, 'count': rows.length}),
    );
    stdout.writeln('Отбор завершён: ${rows.length}');
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 64;
  } finally {
    await sink?.close();
    client.close(force: true);
  }
}
