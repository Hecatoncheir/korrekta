import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/ensemble_roles.dart';
import 'package:korrekta_model_benchmark/src/ensemble_runtime.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('profile', allowed: roleProfiles)
    ..addFlag('features', negatable: false);
  EnsembleRuntime? runtime;
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final file = File(options.option('output')!);
    if (file.existsSync()) throw const FormatException('Файл уже существует');
    final rows = (await File(options.option('input')!).readAsLines())
        .where((s) => s.trim().isNotEmpty)
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .where((r) => r['type'] == 'case')
        .toList();
    if (options.flag('features')) runtime = await EnsembleRuntime.open();
    await file.parent.create(recursive: true);
    sink = file.openWrite();
    final profiles = options.option('profile') == null
        ? roleProfiles
        : [options.option('profile')!];
    sink.writeln(jsonEncode({'type': 'metadata', 'profiles': profiles}));
    for (final row in rows) {
      if (runtime != null) {
        final features = await roleFeatures(
          row,
          SharedLexicon(runtime.hunspell, runtime.symspell),
        );
        sink.writeln(jsonEncode({...row, 'role_features': features}));
      } else {
        sink.writeln(
          jsonEncode({
            ...row,
            'role_results': {
              for (final profile in profiles)
                profile: chooseRoles(row, profile),
            },
          }),
        );
      }
      await sink.flush();
    }
    sink.writeln(
      jsonEncode({'type': 'summary', 'completed': true, 'count': rows.length}),
    );
    stdout.writeln('Обработано ${rows.length}');
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
