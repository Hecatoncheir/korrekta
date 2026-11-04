import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/runtime/safe_extract.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:zstd_neo/zstd_neo.dart';

void main() {
  late Directory root, stage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('korrekta-archive-');
    stage = await Directory(p.join(root.path, 'stage')).create();
  });
  tearDown(() async => root.delete(recursive: true));

  for (final zstd in [false, true]) {
    test(
      'Потоковая распаковка tar.${zstd ? 'zst' : 'gz'} с ограничением размера',
      () async {
        final entries = [
          TarEntry.data(TarHeader(name: 'nested/data.txt', mode: 420), [
            1,
            2,
            3,
            4,
          ]),
        ];
        final file = await tar(root, entries, zstd: zstd);
        await extractAsset(file, stage, file.uri.toString(), 1024);
        expect(
          await File(p.join(stage.path, 'nested', 'data.txt')).readAsBytes(),
          [1, 2, 3, 4],
        );
        final other = await Directory(p.join(root.path, 'other')).create();
        await expectLater(
          extractAsset(file, other, file.uri.toString(), 2),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'Ссылки внутри пакета разрешены, выходящие наружу отклоняются',
    () async {
      final valid = await tar(root, [
        TarEntry.data(TarHeader(name: 'bin/tool', mode: 493), [1, 2]),
        TarEntry.data(
          TarHeader(
            name: 'bin/alias',
            mode: 493,
            typeFlag: TypeFlag.symlink,
            linkName: 'tool',
          ),
          [],
        ),
      ]);
      await extractAsset(valid, stage, valid.uri.toString(), 1024);
      expect(await File(p.join(stage.path, 'bin', 'alias')).readAsBytes(), [
        1,
        2,
      ]);
      final outside = await tar(root, [
        TarEntry.data(
          TarHeader(
            name: 'escape',
            mode: 493,
            typeFlag: TypeFlag.symlink,
            linkName: '../outside',
          ),
          [],
        ),
      ]);
      await expectLater(
        extractAsset(outside, stage, outside.uri.toString(), 1024),
        throwsFormatException,
      );
    },
    skip: Platform.isWindows,
  );
}

Future<File> tar(
  Directory directory,
  List<TarEntry> entries, {
  bool zstd = false,
}) async {
  final stream = Stream.fromIterable(entries).transform(tarWriter);
  final compressed = zstd
      ? stream.transform(ZstdEncoder())
      : stream.transform(gzip.encoder);
  final file = File(p.join(directory.path, 'test.tar.${zstd ? 'zst' : 'gz'}'));
  final sink = file.openWrite();
  await sink.addStream(compressed);
  await sink.close();
  return file;
}
