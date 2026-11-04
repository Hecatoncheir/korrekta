import 'dart:convert';
import 'dart:io';

import 'package:korrekta/data/local_components.dart';
import 'package:korrekta/data/runtime/owned_processes.dart';
import 'package:korrekta/data/runtime/runtime_data.dart';
import 'package:korrekta/data/runtime/runtime_manager.dart';
import 'package:korrekta/data/runtime/setup_asset.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/setup.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final rootIndex = args.indexOf('--root');
  final root = rootIndex < 0
      ? await Directory.systemTemp.createTemp('korrekta-runtime-')
      : Directory(args[rootIndex + 1]);
  await root.create(recursive: true);
  final catalog = SetupCatalog(
    jsonDecode(await File('assets/components.json').readAsString())
        as Map<String, dynamic>,
    SetupCatalog.currentPlatform(),
  );
  final manager = RuntimeManager(
    root,
    catalog,
    reusePrograms: !args.contains('--portable'),
  );
  final existing = args.contains('--reuse');
  var settings = existing
      ? Settings.defaults(root.path)
      : Settings(
          store: p.join(root.path, 'missing-dictionaries'),
          hunspell: p.join(root.path, 'missing-hunspell'),
          ollama: await availableEndpoint('http://127.0.0.1:0'),
          languageTool: await availableEndpoint('http://127.0.0.1:0'),
        );
  final probe = LocalComponents();
  if (args.contains('--local-ollama')) {
    settings = settings.copyWith(ollama: 'http://127.0.0.1:11434');
  }
  final before = await probe.status(settings);
  try {
    var lastLabel = '';
    settings = await manager.prepare(settings, SetupTask(), (progress) {
      if (progress.label == lastLabel) return;
      lastLabel = progress.label;
      stdout.writeln(progress.label);
    }, loadModel: !args.contains('--services-only'));
    final status = await probe.status(settings);
    if (!status.ollama ||
        !status.languageTool ||
        !await validDictionaries(settings.store)) {
      throw StateError('Компоненты не готовы');
    }
    final hunspell = await findProgram([settings.hunspell], '1.7.5', ['-v']);
    if (hunspell == null) throw StateError('Не запустился Hunspell');
    await dictionaryCheck(settings);
    stdout.writeln(
      jsonEncode({
        'platform': catalog.platform,
        'ollama': status.ollama,
        'languageTool68': status.languageTool,
        'hunspell175': true,
        'dictionaries': true,
        'model': status.model,
      }),
    );
  } finally {
    await manager.close();
    final after = await probe.status(settings);
    probe.close();
    if (after.ollama != before.ollama ||
        after.languageTool != before.languageTool) {
      throw StateError(
        'Нарушено владение процессами: состояние чужих служб изменилось или собственная служба осталась запущенной',
      );
    }
  }
}

Future<void> dictionaryCheck(Settings settings) async {
  final process = await Process.start(settings.hunspell, [
    '-a',
    '-i',
    'UTF-8',
    '-d',
    'ru_RU',
  ], workingDirectory: p.join(settings.store, 'hunspell'));
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();
  process.stdin.writeln('привет');
  await process.stdin.close();
  final code = await process.exitCode.timeout(const Duration(seconds: 15));
  if (code != 0 ||
      !(await output).split('\n').any((line) => line.trim() == '*')) {
    throw StateError('Hunspell не прочитал русский словарь: ${await errors}');
  }
  await errors;
}
