import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/settings.dart';

typedef ComponentStatus = ({bool ollama, bool model, bool languageTool});
typedef DownloadProgress = ({
  String status,
  double? fraction,
  int? completed,
  int? total,
});

class LocalComponents {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  Future<ComponentStatus> status(Settings settings) async {
    final tags = await _read(settings.ollama, '/api/tags');
    return (
      ollama: tags is Map<String, dynamic> && tags['models'] is List<dynamic>,
      model: hasModel(tags, settings.model.id),
      languageTool: await languageToolReady(settings.languageTool),
    );
  }

  Future<bool> ollamaReady(String endpoint) async =>
      switch (await _read(endpoint, '/api/tags')) {
        {'models': List<dynamic> _} => true,
        _ => false,
      };

  Future<bool> languageToolReady(String endpoint) async {
    try {
      final request = await _client.postUrl(
        localEndpoint(endpoint).resolve('/v2/check'),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        'language=ru-RU&text=${Uri.encodeQueryComponent('Проверка.')}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 &&
          switch (jsonDecode(body)) {
            {'software': {'version': '6.8'}} => true,
            _ => false,
          };
    } on Exception {
      return false;
    }
  }

  Future<void> warmup(Settings settings) async {
    final request = await _client.postUrl(
      localEndpoint(settings.ollama).resolve('/api/generate'),
    );
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': settings.model.id,
        'prompt': 'Ответь: да',
        'stream': false,
        'options': {'num_ctx': 8192, 'num_predict': 4, 'temperature': 0},
      }),
    );
    final response = await request.close().timeout(const Duration(minutes: 5));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200 ||
        switch (jsonDecode(body)) {
          {'done': true, 'model': String _} => false,
          _ => true,
        }) {
      throw const HttpException(
        'Не удалось загрузить выбранную модель в память',
      );
    }
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
      (
        status: status,
        fraction: (done / total).clamp(0, 1).toDouble(),
        completed: done.toInt(),
        total: total.toInt(),
      ),
    {'status': String status} => (
      status: status,
      fraction: null,
      completed: null,
      total: null,
    ),
    _ => throw const FormatException('Не удалось прочитать прогресс Ollama'),
  };

  void close() => _client.close(force: true);
}
