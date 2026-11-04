import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/update_api.dart';
import 'package:korrekta/data/update_download.dart';
import 'package:korrekta/domain/app_release.dart';

const assetName = 'Korrekta-0.2.0-windows-x64-setup.exe';
final assetUrl = Uri.parse(
  'https://github.com/Hecatoncheir/korrekta/releases/download/v0.2.0/$assetName',
);

void main() {
  test('Версии и контракт релиза, внешний адрес отклоняется', () {
    expect(newerVersion(releaseVersion('v0.2.0')!, '0.1.0'), isTrue);
    expect(newerVersion(releaseVersion('v0.1.0')!, '0.2.0'), isFalse);
    expect(releaseVersion('something'), isNull);
    expect(
      () => trustedReleaseUrl('https://example.org/setup.exe'),
      throwsFormatException,
    );
    expect(
      parseAsset({
        'name': '../setup.exe',
        'browser_download_url': assetUrl.toString(),
        'size': 1,
      }),
      isNull,
    );
  });

  test(
    'GitHub без релизов не считается сетевой ошибкой; 403 считается',
    () async {
      final missing = MockClient((_) async => http.Response('Not found', 404));
      expect(await UpdateApi(missing).latest('windows-x64-setup.exe'), isNull);
      missing.close();
      final denied = MockClient((_) async => http.Response('rate limit', 403));
      await expectLater(
        UpdateApi(denied).latest('windows-x64-setup.exe'),
        throwsA(isA<HttpException>()),
      );
      denied.close();
    },
  );

  test('Продолжает часть загрузки, проверяет SHA-256 и повторно использует целый файл', () async {
    final directory = await Directory.systemTemp.createTemp(
      'korrekta-download-',
    );
    final bytes = utf8.encode('проверенное обновление');
    final digest = sha256.convert(bytes).toString();
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      calls++;
      expect(request.headers['Range'], 'bytes=5-');
      return http.StreamedResponse(
        Stream.value(bytes.sublist(5)),
        206,
        headers: {
          'content-range': 'bytes 5-${bytes.length - 1}/${bytes.length}',
        },
      );
    });
    try {
      final asset = (
        name: assetName,
        url: assetUrl,
        size: bytes.length,
        digest: digest,
      );
      await File('${directory.path}/$assetName.part')
          .writeAsBytes(bytes.sublist(0, 5));
      final downloader = UpdateDownload(client, directory);
      final file = await downloader.download(asset, digest, (_) {});
      expect(await file.readAsBytes(), bytes);
      expect(await downloader.cached(asset, digest), isNotNull);
      await downloader.download(asset, digest, (_) {});
      expect(calls, 1);
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'Неверная сумма, недокачанный ответ и неверный Range не принимаются',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'korrekta-bad-download-',
      );
      final client = MockClient((_) async => http.Response('bad', 200));
      try {
        final asset = (
          name: assetName,
          url: assetUrl,
          size: 3,
          digest: '0' * 64,
        );
        final downloader = UpdateDownload(client, directory);
        await expectLater(
          downloader.download(asset, '0' * 64, (_) {}),
          throwsFormatException,
        );
        expect(await downloader.cached(asset, '0' * 64), isNull);
        expect(
          () => UpdateDownload.validResponse(
            http.StreamedResponse(
              const Stream.empty(),
              206,
              headers: {'content-range': 'bytes 0-2/3'},
            ),
            1,
            3,
          ),
          throwsA(isA<HttpException>()),
        );
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
