import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/app_release.dart';

class UpdateDownload {
  UpdateDownload(this.client, this.directory);
  final http.Client client;
  final Directory directory;

  Future<bool> verified(File file, ReleaseAsset asset, String digest) async {
    if (!await file.exists() || await file.length() != asset.size) return false;
    return (await sha256.bind(file.openRead()).first).toString() == digest;
  }

  Future<File?> cached(ReleaseAsset asset, String digest) async {
    final file = File(p.join(directory.path, asset.name));
    return await verified(file, asset, digest) ? file : null;
  }

  Future<File> download(
    ReleaseAsset asset,
    String digest,
    void Function(double) progress,
  ) async {
    final existing = await cached(asset, digest);
    if (existing != null) return existing;
    await directory.create(recursive: true);
    final part = File(p.join(directory.path, '${asset.name}.part'));
    var offset = await part.exists() ? await part.length() : 0;
    if (offset >= asset.size) offset = 0;
    final request = http.Request('GET', asset.url);
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final append = validResponse(response, offset, asset.size);
    final sink = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    var received = append ? offset : 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > asset.size) {
          throw const FormatException('Размер обновления превышает ожидаемый');
        }
        sink.add(chunk);
        progress(received / asset.size);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (!await verified(part, asset, digest)) {
      throw const FormatException('Контрольная сумма обновления не совпала');
    }
    return part.rename(p.join(directory.path, asset.name));
  }

  static bool validResponse(
    http.StreamedResponse response,
    int offset,
    int size,
  ) {
    if (response.statusCode == 200) return false;
    if (response.statusCode == 206 &&
        offset > 0 &&
        response.headers['content-range'] ==
            'bytes $offset-${size - 1}/$size') {
      return true;
    }
    throw const HttpException('Не удалось продолжить загрузку обновления');
  }
}
