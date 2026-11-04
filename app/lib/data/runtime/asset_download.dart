import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../domain/setup.dart';
import 'setup_asset.dart';

class AssetDownload {
  AssetDownload(this.directory, {http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final Directory directory;
  final http.Client Function() _clientFactory;

  Future<File> fetch(
    SetupAsset asset,
    SetupTask task,
    SetupReporter report,
  ) async {
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, '${asset.id}.archive'));
    if (await valid(file, asset)) return file;
    final part = File('${file.path}.part');
    if (await part.exists() && await part.length() > asset.bytes) {
      await part.delete();
    }
    task.check();
    final client = _clientFactory();
    final remove = task.onCancel(client.close);
    try {
      await _transfer(client, asset, part, task, report);
      task.check();
      report((label: 'Проверяем ${asset.label}', completed: null, total: null));
      if (!await valid(part, asset)) {
        await part.delete();
        throw const SetupFailure(
          'Загруженный файл повреждён. Повторите подготовку — файл будет скачан заново.',
        );
      }
      task.check();
      if (await file.exists()) await file.delete();
      return await part.rename(file.path);
    } catch (_) {
      task.check();
      rethrow;
    } finally {
      remove();
      client.close();
    }
  }

  Future<void> _transfer(
    http.Client client,
    SetupAsset asset,
    File part,
    SetupTask task,
    SetupReporter report,
  ) async {
    var offset = await part.exists() ? await part.length() : 0;
    if (offset == asset.bytes) return;
    final response = await _request(client, asset.url, offset);
    if (response.statusCode == 200) offset = 0;
    _validateResponse(response, offset, asset.bytes);
    final sink = part.openWrite(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var done = offset;
    final clock = Stopwatch()..start();
    try {
      await sink.addStream(
        response.stream.timeout(const Duration(seconds: 60)).map((chunk) {
          task.check();
          done += chunk.length;
          if (done > asset.bytes) {
            throw const SetupFailure(
              'Сервер прислал файл неожиданного размера. Повторите позже.',
            );
          }
          if (clock.elapsedMilliseconds >= 100 || done == asset.bytes) {
            report((
              label: 'Скачиваем ${asset.label}',
              completed: done,
              total: asset.bytes,
            ));
            clock.reset();
          }
          return chunk;
        }),
      );
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<http.StreamedResponse> _request(
    http.Client client,
    Uri url,
    int offset,
  ) async {
    var current = url;
    for (var redirect = 0; redirect < 6; redirect++) {
      if (current.scheme != 'https' || current.userInfo.isNotEmpty) {
        throw const SetupFailure(
          'Источник компонента должен использовать HTTPS.',
        );
      }
      final request = http.Request('GET', current)..followRedirects = false;
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null) break;
      current = current.resolve(location);
    }
    throw const SetupFailure(
      'Не удалось перейти к загрузке компонента. Повторите позже.',
    );
  }

  void _validateResponse(http.StreamedResponse response, int offset, int size) {
    if (response.statusCode == 200 && offset == 0) return;
    final range = response.headers['content-range'];
    if (response.statusCode == 206 &&
        range == 'bytes $offset-${size - 1}/$size') {
      return;
    }
    throw SetupFailure(
      'Не удалось скачать компонент (ответ ${response.statusCode}). Проверьте интернет и повторите.',
    );
  }

  static Future<bool> valid(File file, SetupAsset asset) async {
    if (!await file.exists() || await file.length() != asset.bytes) {
      return false;
    }
    final path = file.path;
    final digest = await Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
    return digest == asset.sha256;
  }
}
