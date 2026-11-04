import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/settings.dart';

typedef ComponentStatus = ({bool ollama, bool model, bool languageTool});
typedef DownloadProgress = ({String status, double? fraction});

class LocalComponents {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  Future<ComponentStatus> status(Settings settings) async {
    final tags = await _read(settings.ollama, '/api/tags');
    final languages = await _read(settings.languageTool, '/v2/languages');
    return (
      ollama: tags != null,
      model: hasModel(tags, settings.model.id),
      languageTool: languages is List<dynamic>,
    );
  }

  static bool hasModel(Object? tags, String id) => switch (tags) {
    {'models': List<dynamic> models} => models.any(
      (entry) => switch (entry) {
        {'name': String name} => name == id,
        _ => false,
      },
    ),
    _ => false,
  };

  Future<Object?> _read(String endpoint, String path) async {
    try {
      final request = await _client.getUrl(
        localEndpoint(endpoint).resolve(path),
      );
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200 ? jsonDecode(body) : null;
    } on Exception {
      return null;
    }
  }

  Stream<DownloadProgress> pull(Settings settings) async* {
    final request = await _client.postUrl(
      localEndpoint(settings.ollama).resolve('/api/pull'),
    );
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'model': settings.model.id, 'stream': true}));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw const HttpException('Ollama не смог начать загрузку модели');
    }
    yield* response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(minutes: 3))
        .map(parseProgress);
  }

  static DownloadProgress parseProgress(String line) => switch (jsonDecode(
    line,
  )) {
    {'error': String error} => throw StateError(error),
    {'status': String status, 'completed': num done, 'total': num total}
        when total > 0 =>
      (status: status, fraction: (done / total).clamp(0, 1).toDouble()),
    {'status': String status} => (status: status, fraction: null),
    _ => throw const FormatException('Не удалось прочитать прогресс Ollama'),
  };

  void close() => _client.close(force: true);
}
