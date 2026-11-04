import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/runtime/asset_download.dart';
import 'package:korrekta/data/runtime/setup_asset.dart';
import 'package:korrekta/domain/setup.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  const bytes = [1, 2, 3, 4, 5, 6];
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('korrekta-download-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'Продолжение загрузки с сохранённого места и проверка SHA-256',
    () async {
      await File(p.join(root.path, 'fixture.archive.part'))
          .writeAsBytes(bytes.take(2).toList());
      var requests = 0;
      final download = AssetDownload(
        root,
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(request.headers['Range'], 'bytes=2-');
          return http.Response.bytes(
            bytes.skip(2).toList(),
            206,
            headers: {'content-range': 'bytes 2-5/6'},
          );
        }),
      );
      final file = await download.fetch(asset(bytes), SetupTask(), (_) {});
      expect(await file.readAsBytes(), bytes);
      await download.fetch(asset(bytes), SetupTask(), (_) {});
      expect(requests, 1);
    },
  );

  test('Сервер без Range начинает файл заново', () async {
    await File(p.join(root.path, 'fixture.archive.part')).writeAsBytes([9, 9]);
    final download = AssetDownload(
      root,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    final file = await download.fetch(asset(bytes), SetupTask(), (_) {});
    expect(await file.readAsBytes(), bytes);
  });

  test('Повреждённый файл и неверный Content-Range не принимаются', () async {
    final download = AssetDownload(
      root,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes([1, 2, 3, 4, 5, 7], 200)),
    );
    await expectLater(
      download.fetch(asset(bytes), SetupTask(), (_) {}),
      throwsA(isA<SetupFailure>()),
    );
    expect(
      await File(p.join(root.path, 'fixture.archive.part')).exists(),
      isFalse,
    );
    await File(p.join(root.path, 'fixture.archive.part')).writeAsBytes([1, 2]);
    final badRange = AssetDownload(
      root,
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          bytes,
          206,
          headers: {'content-range': 'bytes 0-5/6'},
        ),
      ),
    );
    await expectLater(
      badRange.fetch(asset(bytes), SetupTask(), (_) {}),
      throwsA(isA<SetupFailure>()),
    );
    expect(
      await File(p.join(root.path, 'fixture.archive.part')).readAsBytes(),
      [1, 2],
    );
  });

  test(
    'Отмена сохраняет только записанную часть для следующей попытки',
    () async {
      final task = SetupTask();
      final chunkWritten = Completer<void>();
      final stream = StreamController<List<int>>();
      final download = AssetDownload(
        root,
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(stream.stream, 200),
        ),
      );
      final future = download.fetch(asset(bytes), task, (_) {});
      final expectation = expectLater(future, throwsA(isA<SetupCancelled>()));
      stream.add([1, 2]);
      final part = File(p.join(root.path, 'fixture.archive.part'));
      for (var i = 0; i < 100; i++) {
        if (await part.exists() && await part.length() == 2) {
          chunkWritten.complete();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(chunkWritten.isCompleted, isTrue);
      task.cancel();
      stream.add([3, 4]);
      await stream.close();
      await expectation;
      expect(await part.readAsBytes(), [1, 2]);
    },
  );

  test('Перенаправление с HTTPS на HTTP запрещено', () async {
    final download = AssetDownload(
      root,
      clientFactory: () => MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'http://example.test/file.zip'},
        ),
      ),
    );
    await expectLater(
      download.fetch(asset(bytes), SetupTask(), (_) {}),
      throwsA(isA<SetupFailure>()),
    );
  });
}

SetupAsset asset(
  List<int> bytes, {
  String url = 'https://example.test/file.zip',
  List<String> markers = const ['data.txt'],
}) => SetupAsset(
  id: 'fixture',
  label: 'тестовый компонент',
  url: Uri.parse(url),
  bytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  expandedBytes: 1024,
  markers: markers,
);
