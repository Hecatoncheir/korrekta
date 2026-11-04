import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:korrekta/data/update_api.dart';
import 'package:korrekta/data/update_download.dart';

Future<void> main() async {
  final suffix = switch (Platform.operatingSystem) {
    'windows' => 'windows-x64-setup.exe',
    'linux' => 'linux-x64.run',
    'macos' => 'macos-universal.dmg',
    _ => throw UnsupportedError(Platform.operatingSystem),
  };
  final client = http.Client();
  try {
    final api = UpdateApi(client);
    final release = await api.latest(suffix);
    final asset = release?.installer;
    if (release == null || asset == null) {
      throw StateError('Нет опубликованного установщика');
    }
    final digest = await api.checksum(release);
    final downloads = UpdateDownload(
      client,
      Directory('../work/release-verification'),
    );
    final file = await downloads.download(asset, digest, (_) {});
    stdout.writeln(
      jsonEncode({
        'version': release.version.toString(),
        'file': file.path,
        'bytes': await file.length(),
        'sha256_verified': await downloads.verified(file, asset, digest),
        'installer_launched': false,
      }),
    );
  } finally {
    client.close();
  }
}
