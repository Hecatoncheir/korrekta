import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/settings.dart';
import '../../domain/setup.dart';
import '../local_components.dart';
import 'asset_install.dart';
import 'owned_processes.dart';
import 'runtime_disk.dart';
import 'runtime_programs.dart';
import 'setup_asset.dart';

abstract interface class ComponentSetup {
  Future<Settings> prepare(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  );
  Future<void> close();
}

class RuntimeManager implements ComponentSetup {
  RuntimeManager(this.root, SetupCatalog catalog, {bool reusePrograms = true})
    : programs = RuntimePrograms(
        AssetInstall(root),
        catalog,
        reusePrograms: reusePrograms,
      ),
      processes = OwnedProcesses(Directory(p.join(root.path, 'logs')));
  final Directory root;
  final RuntimePrograms programs;
  final OwnedProcesses processes;
  SetupTask? _activeTask;
  Future<Settings>? _pending;
  bool _stopping = false;

  @override
  Future<Settings> prepare(
    Settings settings,
    SetupTask task,
    SetupReporter report, {
    bool loadModel = true,
  }) {
    if (_stopping) throw const SetupCancelled();
    _activeTask = task;
    return _pending = _prepare(settings, task, report, loadModel);
  }

  Future<Settings> _prepare(
    Settings settings,
    SetupTask task,
    SetupReporter report,
    bool loadModel,
  ) async {
    await root.create(recursive: true);
    final lock = await File(p.join(root.path, '.prepare.lock'))
        .open(mode: FileMode.append);
    final probe = LocalComponents();
    final remove = task.onCancel(probe.close);
    try {
      await _lock(lock);
      var resolved = await programs.dictionaries(settings, task, report);
      resolved = resolved.copyWith(
        hunspell: await programs.hunspell(resolved, task, report),
      );
      resolved = resolved.copyWith(
        ollama: await _ollama(resolved, probe, task, report),
      );
      resolved = resolved.copyWith(
        languageTool: await _languageTool(resolved, probe, task, report),
      );
      if (loadModel) await _model(resolved, probe, task, report);
      task.check();
      return resolved;
    } finally {
      remove();
      probe.close();
      await lock.close();
    }
  }

  Future<void> _lock(RandomAccessFile lock) async {
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      throw const SetupFailure(
        'Компоненты уже готовятся в другом окне Корректы. Дождитесь завершения и повторите.',
      );
    }
  }

  Future<String> _ollama(
    Settings settings,
    LocalComponents probe,
    SetupTask task,
    SetupReporter report,
  ) async {
    report((label: 'Проверяем Ollama', completed: null, total: null));
    if (await probe.ollamaReady(settings.ollama)) return settings.ollama;
    final executable = await programs.ollama(task, report);
    task.check();
    final endpoint = await availableEndpoint(settings.ollama);
    final models = modelDirectory();
    await models.create(recursive: true);
    report((label: 'Запускаем Ollama', completed: null, total: null));
    await processes.start(
      'Ollama',
      executable,
      ['serve'],
      environment: {
        'OLLAMA_HOST': endpoint,
        'OLLAMA_MODELS': models.path,
        'OLLAMA_MAX_LOADED_MODELS': '1',
        'OLLAMA_NUM_PARALLEL': '1',
        'OLLAMA_NO_CLOUD': '1',
      },
    );
    await waitForService(
      name: 'Ollama',
      ready: () => probe.ollamaReady(endpoint),
      processes: processes,
      task: task,
    );
    return endpoint;
  }

  Future<String> _languageTool(
    Settings settings,
    LocalComponents probe,
    SetupTask task,
    SetupReporter report,
  ) async {
    report((label: 'Проверяем LanguageTool 6.8', completed: null, total: null));
    if (await probe.languageToolReady(settings.languageTool)) {
      return settings.languageTool;
    }
    final libraries = await programs.languageTool(settings, task, report);
    final java = await programs.java(settings, task, report);
    task.check();
    final endpoint = await availableEndpoint(settings.languageTool);
    report((label: 'Запускаем LanguageTool 6.8', completed: null, total: null));
    await processes.start('LanguageTool', java, [
      '-Xms64m',
      '-Xmx768m',
      '-Dfile.encoding=UTF-8',
      '-cp',
      p.join(libraries, 'lib', '*'),
      'org.languagetool.server.HTTPServer',
      '--config',
      p.join(libraries, 'server.properties'),
      '--port',
      '${Uri.parse(endpoint).port}',
    ]);
    await waitForService(
      name: 'LanguageTool',
      ready: () => probe.languageToolReady(endpoint),
      processes: processes,
      task: task,
    );
    return endpoint;
  }

  Future<void> _model(
    Settings settings,
    LocalComponents probe,
    SetupTask task,
    SetupReporter report,
  ) async {
    final status = await probe.status(settings);
    task.check();
    if (!status.model) await _pull(settings, probe, task, report);
    report((
      label: 'Загружаем ${settings.model.shortName} в память',
      completed: null,
      total: null,
    ));
    await probe.warmup(settings);
    task.check();
  }

  Future<void> _pull(
    Settings settings,
    LocalComponents probe,
    SetupTask task,
    SetupReporter report,
  ) async {
    await const RuntimeDisk().require(modelDirectory(), 512 * 1024 * 1024);
    var complete = false;
    int? checkedTotal;
    await for (final progress in probe.pull(settings)) {
      task.check();
      complete = progress.status == 'success';
      if (progress.total case final total? when total != checkedTotal) {
        await const RuntimeDisk().require(
          modelDirectory(),
          total - (progress.completed ?? 0) + 512 * 1024 * 1024,
        );
        checkedTotal = total;
      }
      report((
        label: 'Скачиваем ${settings.model.shortName}',
        completed: progress.completed,
        total: progress.total,
      ));
    }
    if (!complete) {
      throw const SetupFailure(
        'Загрузка модели прервалась. Повторная попытка продолжит загрузку.',
      );
    }
  }

  Directory modelDirectory() {
    final env = Platform.environment;
    if (env['OLLAMA_MODELS'] case final path? when path.isNotEmpty) {
      return Directory(path);
    }
    final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    return Directory(p.join(home ?? root.path, '.ollama', 'models'));
  }

  @override
  Future<void> close() async {
    _stopping = true;
    _activeTask?.cancel();
    try {
      await _pending;
    } catch (_) {
      // Незавершённая подготовка уже передала ошибку в интерфейс.
    }
    await processes.close();
    _stopping = false;
  }
}
