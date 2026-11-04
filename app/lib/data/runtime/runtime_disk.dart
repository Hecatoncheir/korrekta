import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/setup.dart';

class RuntimeDisk {
  const RuntimeDisk();

  Future<void> require(Directory directory, int bytes) async {
    await directory.create(recursive: true);
    final available = await freeBytes(directory);
    if (available != null && available < bytes) {
      final gb = (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      throw SetupFailure(
        'Не хватает места на диске. Освободите не менее $gb ГБ в расположении компонентов и повторите.',
      );
    }
  }

  Future<int?> freeBytes(Directory directory) async {
    try {
      final path = p.absolute(directory.path);
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            r'[System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($env:KORREKTA_SPACE_PATH)).AvailableFreeSpace',
          ],
          environment: {'KORREKTA_SPACE_PATH': path},
        ).timeout(const Duration(seconds: 10));
        return result.exitCode == 0
            ? int.tryParse((result.stdout as String).trim())
            : null;
      }
      final result = await Process.run('df', [
        '-Pk',
        path,
      ]).timeout(const Duration(seconds: 10));
      final fields = (result.stdout as String)
          .trim()
          .split('\n')
          .last
          .trim()
          .split(RegExp(r'\s+'));
      return result.exitCode == 0 ? int.parse(fields[3]) * 1024 : null;
    } on Exception {
      return null;
    }
  }
}
