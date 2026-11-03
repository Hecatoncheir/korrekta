import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'languagetool.dart';
import 'scoring.dart';

Future<int> runLanguageTool(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('data', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('split', defaultsTo: 'dev', allowed: ['dev', 'test'])
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:8081');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final options = parser.parse(arguments);
    final endpoint = Uri.parse(options.option('endpoint')!);
    if (endpoint.scheme != 'http' ||
        !const ['localhost', '127.0.0.1', '::1'].contains(endpoint.host)) {
      throw const FormatException('Допустим только локальный HTTP API');
    }
    final cases = (await File(options.option('data')!).readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as JsonMap)
        .where((row) => row['split'] == options.option('split'))
        .toList();
    if (cases.isEmpty) throw const FormatException('Нет примеров');
    final output = File(options.option('output')!);
    await output.parent.create(recursive: true);
    if (output.existsSync()) {
      throw const FormatException('Файл результата уже существует');
    }
    final sink = output.openWrite();
    try {
      Future<void> write(JsonMap record) async {
        sink.writeln(jsonEncode(record));
        await sink.flush();
      }

      await write({
        'type': 'metadata',
        'time': DateTime.now().toUtc().toIso8601String(),
        'model': 'LanguageTool 6.8',
        'endpoint': endpoint.toString(),
        'split': options.option('split'),
        'parameters': {'language': 'ru', 'level': 'default'},
        'selection': 'Первый вариант; при пересечении первое замечание API',
        'count': cases.length,
      });
      Future<JsonMap> check(JsonMap item, String type) async {
        final timer = Stopwatch()..start();
        final request = await client.postUrl(endpoint.resolve('/v2/check'));
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          Uri(
            queryParameters: {
              'language': 'ru',
              'level': 'default',
              'text': item['text'] as String,
            },
          ).query,
        );
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        timer.stop();
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}: $body');
        }
        final value = jsonDecode(body) as JsonMap;
        return {
          'type': type,
          'id': item['id'],
          'category': item['category'],
          'text': item['text'],
          'expected': item['edits'],
          'seconds': timer.elapsedMicroseconds / 1e6,
          'response': value,
          ...applyLanguageTool(
            item['text'] as String,
            value['matches'] as List<dynamic>,
          ),
        };
      }

      await write(
        await check(
          cases.first,
          'cold_start',
        ).timeout(const Duration(seconds: 60)),
      );
      for (var i = 0; i < cases.length; i++) {
        final record = await check(
          cases[i],
          'case',
        ).timeout(const Duration(seconds: 60));
        await write(record);
        stderr.writeln('${i + 1}/${cases.length} ${record['id']}');
      }
      await write({
        'type': 'summary',
        'completed': true,
        'count': cases.length,
      });
    } finally {
      await sink.close();
    }
    return 0;
  } on FormatException catch (error) {
    stderr.writeln('$error\n${parser.usage}');
    return 64;
  } catch (error) {
    stderr.writeln(error);
    return 70;
  } finally {
    client.close(force: true);
  }
}
