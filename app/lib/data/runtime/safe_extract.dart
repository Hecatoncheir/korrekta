import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart'
    show InputFileStream, OutputFileStream, ZipDecoder;
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:zstd_neo/zstd_neo.dart';

import '../../domain/setup.dart';

Future<void> extractAsset(
  File file,
  Directory destination,
  String url,
  int limit,
) {
  final source = file.path;
  final target = destination.path;
  return Isolate.run(() async {
    final extractor = _Extractor(
      Directory(await Directory(target).resolveSymbolicLinks()),
      limit,
    );
    if (Uri.parse(url).path.endsWith('.zip')) {
      await extractor.zip(File(source));
    } else {
      await extractor.tar(
        File(source),
        zstd: Uri.parse(url).path.endsWith('.zst'),
      );
    }
    await extractor.finish();
  });
}

String archivePath(String root, String name) {
  if (name.contains('\\') ||
      name.contains(':') ||
      name.contains('\u0000') ||
      p.posix.isAbsolute(name)) {
    throw const FormatException('Недопустимый путь в архиве');
  }
  final parts = p.posix.split(name);
  if (parts.contains('..')) {
    throw const FormatException('Путь выходит за пределы архива');
  }
  final result = p.normalize(p.joinAll([root, ...parts]));
  if (result != root && !p.isWithin(root, result)) {
    throw const FormatException('Путь выходит за пределы архива');
  }
  return result;
}

typedef _Link = ({String path, String target, bool hard});

class _Extractor {
  _Extractor(this.root, this.limit);
  final Directory root;
  final int limit;
  int _expanded = 0;
  final _files = <String>{};
  final _links = <_Link>[];
  final _executables = <String>[];

  Future<void> zip(File source) async {
    final input = InputFileStream(source.path);
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      for (final entry in archive) {
        final path = archivePath(root.path, entry.name);
        if (entry.isSymbolicLink) {
          _queueLink(path, entry.symbolicLink!, entry.isHardLink);
        } else if (entry.isDirectory) {
          await Directory(path).create(recursive: true);
        } else {
          await _prepare(path, entry.size, entry.mode);
          final output = OutputFileStream(path);
          try {
            entry.writeContent(output);
          } finally {
            await output.close();
          }
        }
      }
    } finally {
      await input.close();
    }
  }

  Future<void> tar(File source, {required bool zstd}) async {
    final stream = zstd
        ? source.openRead().transform(
            ZstdDecoder(
              maxWindowSize: 256 * 1024 * 1024,
              maxOutputSize: limit + 64 * 1024 * 1024,
            ),
          )
        : source.openRead().transform(gzip.decoder);
    // Официальный архив Ollama для macOS содержит расширенные PAX-метаданные.
    final reader = TarReader(stream, maxSpecialFileSize: 1024 * 1024);
    try {
      while (await reader.moveNext()) {
        await _tarEntry(reader.current);
      }
    } finally {
      await reader.cancel();
    }
  }

  Future<void> _tarEntry(TarEntry entry) async {
    final path = archivePath(root.path, entry.name);
    switch (entry.type) {
      case TypeFlag.reg || TypeFlag.regA:
        await _prepare(path, entry.size, entry.header.mode);
        final sink = File(path).openWrite();
        try {
          await sink.addStream(entry.contents);
        } finally {
          await sink.close();
        }
      case TypeFlag.dir:
        await Directory(path).create(recursive: true);
      case TypeFlag.symlink || TypeFlag.link:
        _queueLink(path, entry.header.linkName!, entry.type == TypeFlag.link);
      default:
        throw const FormatException('Неподдерживаемый тип записи в архиве');
    }
  }

  Future<void> _prepare(String path, int size, int mode) async {
    _expanded += size;
    if (_expanded > limit || size < 0 || !_files.add(path)) {
      throw const FormatException(
        'Неверный размер или повторяющийся файл архива',
      );
    }
    await Directory(p.dirname(path)).create(recursive: true);
    if (mode & 0x49 != 0) _executables.add(path);
  }

  void _queueLink(String path, String target, bool hard) {
    if (Platform.isWindows) {
      throw const FormatException('Ссылки в пакете Windows не поддерживаются');
    }
    if (p.posix.isAbsolute(target) ||
        target.contains('\\') ||
        target.contains(':')) {
      throw const FormatException('Небезопасная ссылка в архиве');
    }
    final base = hard ? root.path : p.dirname(path);
    final resolved = p.normalize(p.joinAll([base, ...p.posix.split(target)]));
    if (!p.isWithin(root.path, resolved) || !_files.add(path)) {
      throw const FormatException('Ссылка выходит за пределы архива');
    }
    _links.add((path: path, target: resolved, hard: hard));
  }

  Future<void> finish() async {
    for (final link in _links.where((link) => link.hard)) {
      await Directory(p.dirname(link.path)).create(recursive: true);
      await File(link.target).copy(link.path);
    }
    for (final link in _links.where((link) => !link.hard)) {
      await Directory(p.dirname(link.path)).create(recursive: true);
      final parent = await Directory(p.dirname(link.path))
          .resolveSymbolicLinks();
      if (parent != root.path && !p.isWithin(root.path, parent)) {
        throw const FormatException('Небезопасная родительская папка ссылки');
      }
      await Link(link.path)
          .create(p.relative(link.target, from: p.dirname(link.path)));
    }
    for (final link in _links) {
      final resolved = await File(link.path).resolveSymbolicLinks();
      if (!p.isWithin(root.path, resolved)) {
        throw const FormatException('Ссылка выходит за пределы архива');
      }
    }
    await makeExecutable(_executables);
  }
}

Future<void> makeExecutable(List<String> files) async {
  if (Platform.isWindows) return;
  for (var start = 0; start < files.length; start += 50) {
    final batch = files.skip(start).take(50).toList();
    final result = await Process.run('chmod', ['755', ...batch]);
    if (result.exitCode != 0) {
      throw const SetupFailure(
        'Не удалось разрешить запуск компонентов. Проверьте права папки приложения.',
      );
    }
  }
}
