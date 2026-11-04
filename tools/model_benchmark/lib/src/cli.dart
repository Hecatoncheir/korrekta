import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

import 'scoring.dart';
import 'response_contract.dart';
import 'guard_response.dart';

final schema = <String, Object>{
  'type': 'object',
  'properties': {
    'edits': {
      'type': 'array',
      'maxItems': 8,
      'items': {
        'type': 'object',
        'properties': {
          'original': {'type': 'string'},
          'replacement': {'type': 'string'},
          'category': {
            'type': 'string',
            'enum': ['grammar', 'spelling', 'punctuation', 'typography'],
          },
          'explanation': {'type': 'string'},
        },
        'required': ['original', 'replacement', 'category', 'explanation'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['edits'],
  'additionalProperties': false,
};

Future<int> runCli(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('model')
    ..addOption('data')
    ..addOption('prompt')
    ..addOption('output')
    ..addOption('split', defaultsTo: 'test', allowed: ['dev', 'test'])
    ..addOption('limit', defaultsTo: '0')
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:11434')
    ..addFlag('cpu', negatable: false)
    ..addFlag('raw', negatable: false)
    ..addFlag('protect', negatable: false)
    ..addOption('names')
    ..addOption(
      'response-mode',
      defaultsTo: 'edits',
      allowed: ['edits', 'text', 'text-json'],
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln(parser.usage);
      return 0;
    }
    for (final name in ['model', 'data', 'prompt', 'output']) {
      if (options.option(name) == null) {
        throw FormatException('Не задан --$name');
      }
    }
    final endpoint = Uri.parse(options.option('endpoint')!);
    if (!const ['127.0.0.1', 'localhost', '::1'].contains(endpoint.host) ||
        endpoint.scheme != 'http') {
      throw const FormatException('Допустим только локальный HTTP API');
    }
    final limit = int.tryParse(options.option('limit')!);
    if (limit == null || limit < 0) {
      throw const FormatException('Неправильный --limit');
    }
    return await runBenchmark(options, endpoint, limit);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    return 64;
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    return 70;
  }
}

Future<int> runBenchmark(ArgResults options, Uri endpoint, int limit) async {
  final model = options.option('model')!;
  final responseMode = options.option('response-mode')!;
  final prompt = await File(options.option('prompt')!).readAsString();
  final namesPath = options.option('names');
  if (namesPath != null && !options.flag('protect')) {
    throw const FormatException('--names требует --protect');
  }
  final names = namesPath == null
      ? <String>[]
      : (jsonDecode(await File(namesPath).readAsString()) as List<dynamic>)
            .cast<String>();
  final lines = await File(options.option('data')!).readAsLines();
  var cases = lines
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as JsonMap)
      .where((item) => item['split'] == options.option('split'))
      .toList();
  if (limit > 0) cases = cases.take(limit).toList();
  if (cases.isEmpty) {
    throw const FormatException('Нет примеров для выбранной части набора');
  }
  if (options.flag('raw') &&
      cases.any((row) => row['rendered_prompt'] is! String)) {
    throw const FormatException(
      'Для --raw нужен rendered_prompt у каждого примера',
    );
  }
  final output = File(options.option('output')!);
  await output.parent.create(recursive: true);
  if (output.existsSync()) {
    throw const FormatException('Файл результата уже существует');
  }
  final sink = output.openWrite();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final records = <JsonMap>[];
  try {
    final version = await request(client, endpoint, 'version');
    final show = await request(client, endpoint, 'show', {'model': model});
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        'model': model,
        'ollama': version,
        'details': show['details'],
        'capabilities': show['capabilities'],
        'model_info': show['model_info'],
        'template': show['template'],
        'prompt': prompt,
        'schema': responseMode == 'edits'
            ? schema
            : responseMode == 'text-json'
            ? textResponseSchema
            : null,
        'response_mode': responseMode,
        'split': options.option('split'),
        'cpu': options.flag('cpu'),
        'raw': options.flag('raw'),
        if (options.flag('protect')) ...{
          'guard_version': guardVersion,
          'personal_names': names,
        },
        if (options.flag('raw')) 'prompt_source': cases.first['prompt_source'],
        'time': DateTime.now().toUtc().toIso8601String(),
        'options': generationOptions(options.flag('cpu')),
      }),
    );
    for (final loaded
        in (await request(client, endpoint, 'ps'))['models'] as List<dynamic>) {
      await request(client, endpoint, 'generate', {
        'model': (loaded as JsonMap)['name'],
        'keep_alive': 0,
      });
    }
    final cold = await checkCase(
      client,
      endpoint,
      model,
      prompt,
      cases.first,
      options.flag('cpu'),
      options.flag('raw'),
      responseMode,
      protect: options.flag('protect'),
      names: names,
    );
    sink.writeln(jsonEncode({...cold, 'type': 'cold_start'}));
    sink.writeln(
      jsonEncode({
        'type': 'resident_memory',
        'data': await request(client, endpoint, 'ps'),
      }),
    );
    for (final item in cases) {
      final record = await checkCase(
        client,
        endpoint,
        model,
        prompt,
        item,
        options.flag('cpu'),
        options.flag('raw'),
        responseMode,
        protect: options.flag('protect'),
        names: names,
      );
      records.add(record);
      sink.writeln(jsonEncode(record));
      await sink.flush();
      if (records.length % 10 == 0 || records.length == cases.length) {
        stderr.writeln('$model: ${records.length}/${cases.length}');
      }
    }
    final result = summarize(records);
    sink.writeln(jsonEncode({'type': 'summary', ...result}));
    stdout.writeln(jsonEncode(result));
  } finally {
    client.close(force: true);
    await sink.close();
  }
  return 0;
}

JsonMap generationOptions(bool cpu) => {
  'temperature': 0,
  'seed': 42,
  'num_ctx': 4096,
  'num_predict': 768,
  'repeat_penalty': 1.0,
  if (cpu) 'num_gpu': 0,
};

Future<JsonMap> request(
  HttpClient client,
  Uri endpoint,
  String api, [
  JsonMap? body,
]) async {
  final url = endpoint.replace(path: '/api/$api');
  final connection = await client.openUrl(body == null ? 'GET' : 'POST', url);
  connection.followRedirects = false;
  if (body != null) {
    connection.headers.contentType = ContentType.json;
    connection.write(jsonEncode(body));
  }
  final response = await connection.close().timeout(
    const Duration(seconds: 180),
  );
  final raw = await utf8.decoder
      .bind(response)
      .join()
      .timeout(const Duration(seconds: 180));
  if (response.statusCode != 200) {
    throw HttpException('${response.statusCode}: $raw');
  }
  final data = jsonDecode(raw) as JsonMap;
  if (data.containsKey('error')) throw StateError(data['error'] as String);
  return data;
}

Future<JsonMap> checkCase(
  HttpClient client,
  Uri endpoint,
  String model,
  String prompt,
  JsonMap item,
  bool cpu,
  bool raw,
  String responseMode, {
  bool protect = false,
  List<String> names = const [],
}) async {
  final stopwatch = Stopwatch()..start();
  final text = item['text'] as String;
  final expected = item['edits'] as List<dynamic>;
  try {
    final response = await request(
      client,
      endpoint,
      raw ? 'generate' : 'chat',
      {
        'model': model,
        if (raw) ...{
          'prompt': item['rendered_prompt'],
          'raw': true,
        } else
          'messages': [
            {'role': 'system', 'content': prompt},
            {
              'role': 'user',
              'content': jsonEncode({'text': text}),
            },
          ],
        'stream': false,
        'think': false,
        if (responseMode != 'text')
          'format': responseMode == 'edits' ? schema : textResponseSchema,
        'options': generationOptions(cpu),
        'keep_alive': '10m',
      },
    );
    stopwatch.stop();
    final content = raw
        ? response['response'] as String
        : (response['message'] as JsonMap)['content'] as String;
    final record = <String, dynamic>{
      'type': 'case',
      'id': item['id'],
      'category': item['category'],
      'text': text,
      'expected': expected,
      'content': content,
      if (raw) 'rendered_prompt_sha256': item['rendered_prompt_sha256'],
      'seconds': stopwatch.elapsedMicroseconds / 1e6,
      'done_reason': response['done_reason'],
      'load_duration': response['load_duration'],
      'eval_count': response['eval_count'],
      'eval_duration': response['eval_duration'],
      'prompt_eval_count': response['prompt_eval_count'],
      'prompt_eval_duration': response['prompt_eval_duration'],
      ...evaluateResponse(text, expected, content, responseMode),
    };
    return protect ? protectResponse(record, names: names) : record;
  } catch (error) {
    stopwatch.stop();
    final record = <String, dynamic>{
      'type': 'case',
      'id': item['id'],
      'category': item['category'],
      'text': text,
      'expected': expected,
      'schema_valid': false,
      'seconds': stopwatch.elapsedMicroseconds / 1e6,
      'error': error.toString(),
      ...scoreCase(text, expected, <dynamic>[]),
    };
    return protect ? protectResponse(record, names: names) : record;
  }
}

JsonMap summarize(List<JsonMap> records) {
  int total(String name) =>
      records.fold(0, (sum, item) => sum + (item[name] as int));
  int count(String name) => records.where((item) => item[name] == true).length;
  final tp = total('tp'), fp = total('fp'), fn = total('fn');
  final correct = total('correct_predictions');
  final rejected = records.fold(
    0,
    (sum, item) => sum + (item['rejected'] as List<dynamic>).length,
  );
  final seconds = records.map((item) => item['seconds'] as double).toList()
    ..sort();
  double percentile(double p) =>
      seconds[min(seconds.length - 1, (p * seconds.length).ceil() - 1)];
  final controls = count('control');
  return {
    'cases': records.length,
    'tp': tp,
    'fp': fp,
    'fn': fn,
    'rejected': rejected,
    'correct_predictions': correct,
    'precision': correct + fp == 0 ? null : correct / (correct + fp),
    'raw_precision': correct + fp + rejected == 0
        ? null
        : correct / (correct + fp + rejected),
    'recall': tp + fn == 0 ? null : tp / (tp + fn),
    'controls': controls,
    'false_notices': count('false_notice'),
    'false_notice_rate': controls == 0
        ? null
        : count('false_notice') / controls,
    'schema_valid_rate': count('schema_valid') / records.length,
    'exact_rate':
        records
            .where(
              (item) => item['exact'] == true && item['schema_valid'] == true,
            )
            .length /
        records.length,
    'median_seconds': percentile(.5),
    'p95_seconds': percentile(.95),
    'max_seconds': seconds.last,
    'total_seconds': seconds.reduce((a, b) => a + b),
    'errors': records.where((item) => item.containsKey('error')).length,
  };
}
