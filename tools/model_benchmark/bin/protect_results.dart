import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/cli.dart' show summarize;
import 'package:korrekta_model_benchmark/src/guard_response.dart';
import 'package:korrekta_model_benchmark/src/scoring.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('names');
  try {
    final options = parser.parse(arguments);
    final source = File(options.option('input')!);
    final output = File(options.option('output')!);
    if (output.existsSync()) {
      throw const FormatException('Файл результата уже существует');
    }
    final namesPath = options.option('names');
    final names = namesPath == null
        ? <String>[]
        : (jsonDecode(await File(namesPath).readAsString()) as List<dynamic>)
              .cast<String>();
    final rows = (await source.readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as JsonMap)
        .toList();
    if (rows.isEmpty || rows.first['type'] != 'metadata') {
      throw const FormatException('Нет метаданных исходного прогона');
    }
    final records = <JsonMap>[];
    await output.parent.create(recursive: true);
    final sink = output.openWrite();
    try {
      for (final row in rows) {
        final type = row['type'];
        if (type == 'summary') continue;
        if (type == 'metadata') {
          sink.writeln(
            jsonEncode({
              ...row,
              'guard_version': guardVersion,
              'personal_names': names,
              'replay_source': source.path,
            }),
          );
        } else if (type == 'case' || type == 'cold_start') {
          final guarded = protectResponse(row, names: names);
          if (type == 'case') records.add(guarded);
          sink.writeln(jsonEncode(guarded));
        } else {
          sink.writeln(jsonEncode(row));
        }
      }
      final summary = summarize(records);
      sink.writeln(jsonEncode({'type': 'summary', ...summary}));
      stdout.writeln(
        jsonEncode({'cases': records.length, 'guard_version': guardVersion}),
      );
    } finally {
      await sink.close();
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}
