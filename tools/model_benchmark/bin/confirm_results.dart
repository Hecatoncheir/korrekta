import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/confirmation_response.dart';
import 'package:korrekta_model_benchmark/src/languagetool_gate.dart';
import 'package:korrekta_model_benchmark/src/local_languagetool.dart';
import 'package:korrekta_model_benchmark/src/scoring.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output-prefix', mandatory: true)
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:8081');
  LocalLanguageTool? client;
  final sinks = <String, IOSink>{};
  try {
    final options = parser.parse(arguments);
    final rows = (await File(options.option('input')!).readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as JsonMap)
        .toList();
    if (rows.isEmpty ||
        rows.first['type'] != 'metadata' ||
        rows.last['type'] != 'summary') {
      throw const FormatException('Нужен завершённый исходный прогон');
    }
    final cases = rows.where((row) => row['type'] == 'case').toList();
    if (cases.isEmpty ||
        cases.map((row) => row['id']).toSet().length != cases.length) {
      throw const FormatException('Пустой набор или повтор идентификаторов');
    }
    const profiles = ['giga-dart', 'lt-first', 'lt-dart', 'joint'];
    final files = {
      for (final profile in profiles)
        profile: File('${options.option('output-prefix')}-$profile.jsonl'),
    };
    if (files.values.any((file) => file.existsSync())) {
      throw const FormatException('Выходной файл уже существует');
    }
    client = LocalLanguageTool(Uri.parse(options.option('endpoint')!));
    for (final entry in files.entries) {
      await entry.value.parent.create(recursive: true);
      final sink = entry.value.openWrite();
      sinks[entry.key] = sink;
      sink.writeln(
        jsonEncode({
          ...rows.first,
          'source_model': rows.first['model'],
          'model': entry.key.startsWith('lt-')
              ? 'LanguageTool 6.8'
              : rows.first['model'],
          'profile': entry.key,
          'personal_names': <String>[],
          'languagetool_parameters': {'language': 'ru', 'level': 'default'},
          'confirmation_version': languageToolGateVersion,
          'source': options.option('input'),
          'languagetool_endpoint': options.option('endpoint'),
          'timing': 'Сохранённое время модели плюс новые измерения LT и Dart; не новый полный запрос',
        }),
      );
    }
    // Прогрев LT отделён от измеряемых примеров.
    final coldTimer = Stopwatch()..start();
    final cold = await client.check(cases.first['text'] as String);
    coldTimer.stop();
    for (final sink in sinks.values) {
      sink.writeln(
        jsonEncode({
          'type': 'lt_cold_start',
          'seconds': coldTimer.elapsedMicroseconds / 1e6,
          'response': cold,
        }),
      );
    }
    for (final row in cases) {
      final timer = Stopwatch()..start();
      final response = await client.check(row['text'] as String);
      timer.stop();
      final outputs = confirmationProfiles(
        row,
        response,
        timer.elapsedMicroseconds / 1e6,
      );
      for (final entry in outputs.entries) {
        sinks[entry.key]!.writeln(jsonEncode(entry.value));
        await sinks[entry.key]!.flush();
      }
    }
    for (final sink in sinks.values) {
      sink.writeln(
        jsonEncode({
          'type': 'summary',
          'completed': true,
          'count': cases.length,
        }),
      );
    }
    stdout.writeln(
      jsonEncode({'count': cases.length, 'version': languageToolGateVersion}),
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } finally {
    for (final sink in sinks.values) {
      await sink.close();
    }
    client?.close();
  }
}
