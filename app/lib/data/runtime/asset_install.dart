import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/setup.dart';
import 'asset_download.dart';
import 'runtime_disk.dart';
import 'safe_extract.dart';
import 'setup_asset.dart';

class AssetInstall {
  AssetInstall(this.root, {AssetDownload? downloads, RuntimeDisk? disk})
    : downloads =
          downloads ?? AssetDownload(Directory(p.join(root.path, 'downloads'))),
      disk = disk ?? const RuntimeDisk();
  final Directory root;
  final AssetDownload downloads;
  final RuntimeDisk disk;

  Directory location(SetupAsset asset) => Directory(
    p.join(
      root.path,
      'packages',
      '${asset.id}-${asset.sha256.substring(0, 12)}',
    ),
  );

  Future<Directory> ensure(
    SetupAsset asset,
    SetupTask task,
    SetupReporter report,
  ) async {
    final target = location(asset);
    task.check();
    if (await installed(target, asset)) return target;
    await disk.require(
      root,
      asset.bytes + asset.expandedBytes + 512 * 1024 * 1024,
    );
    final archive = await downloads.fetch(asset, task, report);
    task.check();
    report((
      label: 'Распаковываем ${asset.label}',
      completed: null,
      total: null,
    ));
    final stage = Directory('${target.path}.staging');
    await _remove(stage);
    await stage.create(recursive: true);
    try {
      await extractAsset(
        archive,
        stage,
        asset.url.toString(),
        asset.expandedBytes,
      );
      task.check();
      await checkMarkers(stage, asset);
      await File(p.join(stage.path, '.ready.json'))
          .writeAsString(jsonEncode({'sha256': asset.sha256}), flush: true);
      await _remove(target);
      await stage.rename(target.path);
      await archive.delete();
      return target;
    } finally {
      await _remove(stage);
    }
  }

  Future<bool> installed(Directory folder, SetupAsset asset) async {
    try {
      final marker = jsonDecode(
        await File(p.join(folder.path, '.ready.json')).readAsString(),
      );
      if (marker is! Map<String, dynamic> || marker['sha256'] != asset.sha256) {
        return false;
      }
      await checkMarkers(folder, asset);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> checkMarkers(Directory folder, SetupAsset asset) async {
    for (final marker in asset.markers) {
      final file = File(archivePath(folder.path, marker));
      if (!await file.exists() || await file.length() == 0) {
        throw SetupFailure(
          'В пакете ${asset.label} отсутствует обязательный файл. Повторите подготовку.',
        );
      }
    }
  }

  Future<void> _remove(Directory directory) async {
    final absoluteRoot = p.normalize(p.absolute(root.path));
    final target = p.normalize(p.absolute(directory.path));
    if (!p.isWithin(p.join(absoluteRoot, 'packages'), target)) {
      throw StateError('Удаление разрешено только внутри папки пакетов');
    }
    final parent = Directory(p.dirname(target));
    await parent.create(recursive: true);
    final expectedParent = p.join(
      await root.resolveSymbolicLinks(),
      'packages',
    );
    if (p.normalize(await parent.resolveSymbolicLinks()) !=
        p.normalize(expectedParent)) {
      throw const SetupFailure(
        'Папка компонентов не должна быть символической ссылкой.',
      );
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
