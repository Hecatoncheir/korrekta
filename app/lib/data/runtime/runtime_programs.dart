import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/settings.dart';
import '../../domain/setup.dart';
import 'asset_install.dart';
import 'owned_processes.dart';
import 'runtime_data.dart';
import 'setup_asset.dart';

class RuntimePrograms {
  RuntimePrograms(this.install, this.catalog, {this.reusePrograms = true});
  final AssetInstall install;
  final SetupCatalog catalog;
  final bool reusePrograms;

  Future<Settings> dictionaries(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  ) async {
    report((label: 'Проверяем словари', completed: null, total: null));
    if (await validDictionaries(settings.store)) return settings;
    task.check();
    final data = await install.ensure(catalog.asset('data'), task, report);
    return settings.copyWith(store: p.join(data.path, 'dictionaries-v1'));
  }

  Future<String> hunspell(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  ) async {
    report((label: 'Проверяем Hunspell', completed: null, total: null));
    final candidates = [
      settings.hunspell,
      p.join(settings.store, 'native', 'ucrt64', 'bin', 'hunspell.exe'),
      'hunspell',
    ];
    final existing = reusePrograms
        ? await findProgram(candidates, '1.7.5', ['-v'])
        : null;
    task.check();
    if (existing != null) return existing;
    if (Platform.isWindows) {
      final data = await install.ensure(catalog.asset('data'), task, report);
      return p.join(
        data.path,
        'dictionaries-v1',
        'native',
        'ucrt64',
        'bin',
        'hunspell.exe',
      );
    }
    return _portable('hunspell', task, report);
  }

  Future<String> ollama(SetupTask task, SetupReporter report) async {
    final env = Platform.environment;
    final candidates = [
      'ollama',
      if (env['LOCALAPPDATA'] case final local?)
        p.join(local, 'Programs', 'Ollama', 'ollama.exe'),
      '/Applications/Ollama.app/Contents/Resources/ollama',
      '/usr/local/bin/ollama',
      '/usr/bin/ollama',
    ];
    final existing = reusePrograms
        ? await findProgram(candidates, '0.40.4', ['--version'])
        : null;
    task.check();
    return existing ?? await _portable('ollama', task, report);
  }

  Future<String> java(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  ) async {
    final binary = Platform.isWindows ? 'java.exe' : 'java';
    final candidates = [
      p.join(
        p.dirname(settings.store),
        'runtimes',
        'jdk-21.0.13+9-jre',
        'bin',
        binary,
      ),
      if (Platform.environment['JAVA_HOME'] case final home?)
        p.join(home, 'bin', binary),
      'java',
    ];
    final existing = reusePrograms
        ? await findProgram(candidates, 'version "21.', ['-version'])
        : null;
    task.check();
    return existing ?? await _portable('java', task, report);
  }

  Future<String> languageTool(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  ) async {
    final existing = p.join(p.dirname(settings.store), 'languagetool', '6.8');
    if (await validLanguageTool(existing)) return existing;
    task.check();
    final data = await install.ensure(catalog.asset('data'), task, report);
    return p.join(data.path, 'languagetool', '6.8');
  }

  Future<String> _portable(
    String name,
    SetupTask task,
    SetupReporter report,
  ) async {
    final asset = catalog.asset(name);
    final folder = await install.ensure(asset, task, report);
    return p.joinAll([folder.path, ...p.posix.split(asset.markers.first)]);
  }
}
