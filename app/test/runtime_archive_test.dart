import 'dart:io';
import 'dart:convert';

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

  test(
    'Расширенные PAX-метаданные macOS читаются с ограничением 1 МиБ',
    () async {
      final file = await tar(root, [
        TarEntry.data(
          TarHeader(
            name: 'PaxHeader/metadata',
            mode: 420,
            typeFlag: TypeFlag.xHeader,
          ),
          utf8.encode(pax('SCHILY.xattr.com.apple.metadata', 'x' * 23000)),
        ),
        TarEntry.data(TarHeader(name: 'data.txt', mode: 420), [1, 2]),
      ]);
      await extractAsset(file, stage, file.uri.toString(), 1024);
      expect(await File(p.join(stage.path, 'data.txt')).readAsBytes(), [1, 2]);
      final oversized = await tar(root, [
        TarEntry.data(
          TarHeader(
            name: 'PaxHeader/oversized',
            mode: 420,
            typeFlag: TypeFlag.xHeader,
          ),
          utf8.encode(pax('SCHILY.xattr.large', 'x' * (1024 * 1024 + 1))),
        ),
        TarEntry.data(TarHeader(name: 'other.txt', mode: 420), [3]),
      ]);
      await expectLater(
        extractAsset(oversized, stage, oversized.uri.toString(), 1024),
        throwsFormatException,
      );
    },
  );

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

String pax(String key, String value) {
  final body = ' $key=$value\n';
  var size = body.length;
  while (size != body.length + size.toString().length) {
    size = body.length + size.toString().length;
  }
  return '$size$body';
}
