import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/local_components.dart';
import 'package:korrekta/data/runtime/asset_download.dart';
import 'package:korrekta/data/runtime/asset_install.dart';
import 'package:korrekta/data/runtime/owned_processes.dart';
import 'package:korrekta/data/runtime/runtime_manager.dart';
import 'package:korrekta/data/runtime/setup_asset.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/setup.dart';
import 'package:korrekta/ui/components_cubit.dart';
import 'package:path/path.dart' as p;

import 'runtime_download_test.dart' show asset;

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('korrekta-setup-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('Распаковка, повторный запуск без загрузки и восстановление неполной установки', () async {
    final bytes = zip('data.txt', 'проверено');
    var requests = 0;
    final installer = AssetInstall(
      root,
      downloads: AssetDownload(
        root,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      ),
    );
    final folder = await installer.ensure(asset(bytes), SetupTask(), (_) {});
    expect(
      await File(p.join(folder.path, 'data.txt')).readAsString(),
      'проверено',
    );
    await installer.ensure(asset(bytes), SetupTask(), (_) {});
    expect(requests, 1);
    await File(p.join(folder.path, 'data.txt')).delete();
    await installer.ensure(asset(bytes), SetupTask(), (_) {});
    expect(requests, 2);
    expect(
      await File(p.join(folder.path, 'data.txt')).readAsString(),
      'проверено',
    );
  });

  for (final name in [
    '../outside.txt',
    '/outside.txt',
    'C:/outside.txt',
    r'dir\..\outside.txt',
  ]) {
    test('Архив не может записать файл за пределами папки: $name', () async {
      final bytes = zip(name, 'плохой путь');
      final download = AssetDownload(
        root,
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      final installer = AssetInstall(root, downloads: download);
      await expectLater(
        installer.ensure(asset(bytes), SetupTask(), (_) {}),
        throwsFormatException,
      );
      expect(
        await Directory('${installer.location(asset(bytes)).path}.staging')
            .exists(),
        isFalse,
      );
      expect(await File(p.join(root.path, 'outside.txt')).exists(), isFalse);
    });
  }

  test(
    'Ошибка распаковки не заменяет прежний компонент и пользовательский файл',
    () async {
      final bytes = zip('unrelated.txt', 'неполный пакет');
      final installer = AssetInstall(
        root,
        downloads: AssetDownload(
          root,
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes(bytes, 200)),
        ),
      );
      final folder = installer.location(asset(bytes));
      await folder.create(recursive: true);
      final old = File(p.join(folder.path, 'old.txt'));
      await old.writeAsString('старое');
      final draft = File(p.join(root.path, 'draft.json'));
      await draft.writeAsString('личный текст');
      await expectLater(
        installer.ensure(asset(bytes), SetupTask(), (_) {}),
        throwsA(isA<SetupFailure>()),
      );
      expect(await old.readAsString(), 'старое');
      expect(await draft.readAsString(), 'личный текст');
    },
  );

  test(
    'Каталог содержит проверяемые пакеты для всех заявленных архитектур',
    () async {
      final json = jsonDecode(
        await File('assets/components.json').readAsString(),
      ) as Map<String, dynamic>;
      for (final platform in [
        'windows-x64',
        'linux-x64',
        'macos-x64',
        'macos-arm64',
      ]) {
        final catalog = SetupCatalog(json, platform);
        for (final name in [
          'data',
          'java',
          'ollama',
          if (platform != 'windows-x64') 'hunspell',
        ]) {
          final package = catalog.asset(name);
          expect(package.url.scheme, 'https');
          expect(package.sha256.length, 64);
          expect(package.markers, isNotEmpty);
        }
      }
    },
  );

  test('Занятый порт не освобождается принудительно', () async {
    final foreign = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = foreign.port;
    final endpoint = await availableEndpoint('http://127.0.0.1:$port');
    expect(Uri.parse(endpoint).port, isNot(port));
    final processes = OwnedProcesses(Directory(p.join(root.path, 'logs')));
    await processes.close();
    expect(foreign.port, port);
    await foreign.close();
  });

  test(
    'Остановка завершает собственный процесс и сохраняет посторонний',
    () async {
      final executable = Platform.isWindows ? 'powershell.exe' : '/bin/sleep';
      final args = Platform.isWindows
          ? [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-Command',
              'Start-Sleep -Seconds 30',
            ]
          : ['30'];
      final foreign = await Process.start(executable, args);
      var foreignExited = false;
      final foreignExit = foreign.exitCode.then((_) => foreignExited = true);
      final processes = OwnedProcesses(Directory(p.join(root.path, 'logs')));
      try {
        await processes.start('owned', executable, args);
        expect(processes.alive('owned'), isTrue);
        await processes.close();
        expect(processes.alive('owned'), isFalse);
        expect(foreignExited, isFalse);
      } finally {
        foreign.kill();
        await foreignExit;
        await foreign.stdout.drain<void>();
        await foreign.stderr.drain<void>();
      }
    },
  );

  test('Смена модели отменяет старую подготовку и применяет только последний результат', () async {
    final setup = ControlledSetup();
    final ready = <LocalModel>[];
    final cubit = ComponentsCubit(
      LocalComponents(),
      setup: setup,
      onReady: (settings) => ready.add(settings.model),
    );
    final first = cubit.prepare(const Settings());
    await Future<void>.delayed(Duration.zero);
    expect(setup.calls, [LocalModel.balanced]);
    final second = cubit.prepare(const Settings(model: LocalModel.quality));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(setup.calls, [LocalModel.balanced, LocalModel.quality]);
    setup.finish.complete();
    await second;
    expect(ready, [LocalModel.quality]);
    expect(cubit.state.ready, isTrue);
    await cubit.close();
    expect(setup.closed, isTrue);
  });

  test('Отмена сразу после запуска и повторная попытка не зависают', () async {
    final setup = ControlledSetup();
    final cubit = ComponentsCubit(LocalComponents(), setup: setup);
    final pending = cubit.prepare(const Settings());
    cubit.cancel();
    await pending;
    expect(cubit.state.stopped, isTrue);
    expect(setup.calls, isEmpty);
    setup.finish.complete();
    await cubit.prepare(const Settings());
    expect(cubit.state.ready, isTrue);
    await cubit.close();
  });
}

List<int> zip(String name, String text) =>
    ZipEncoder().encode(Archive()..addFile(ArchiveFile.string(name, text)));

class ControlledSetup implements ComponentSetup {
  final calls = <LocalModel>[];
  final finish = Completer<void>();
  bool closed = false;
  @override
  Future<Settings> prepare(
    Settings settings,
    SetupTask task,
    SetupReporter report,
  ) async {
    calls.add(settings.model);
    final cancelled = Completer<void>();
    final remove = task.onCancel(cancelled.complete);
    await Future.any([finish.future, cancelled.future]);
    remove();
    task.check();
    return settings;
  }

  @override
  Future<void> close() async => closed = true;
}
