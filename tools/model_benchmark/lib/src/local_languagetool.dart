import 'dart:convert';
import 'dart:io';

import 'scoring.dart';

class LocalLanguageTool {
  LocalLanguageTool(this.endpoint) {
    if (endpoint.scheme != 'http' ||
        !const ['localhost', '127.0.0.1', '::1'].contains(endpoint.host)) {
      throw const FormatException('Разрешён только локальный LanguageTool');
    }
  }
  final Uri endpoint;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  Future<JsonMap> check(String text) =>
      _check(text).timeout(const Duration(seconds: 60));

  Future<JsonMap> _check(String text) async {
    final request = await _client.postUrl(endpoint.resolve('/v2/check'));
    request.followRedirects = false;
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(
      Uri(queryParameters: {'language': 'ru', 'level': 'default', 'text': text})
          .query,
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('LanguageTool: HTTP ${response.statusCode}');
    }
    final value = jsonDecode(body) as JsonMap;
    final software = value['software'] as JsonMap;
    final warnings = value['warnings'] as JsonMap;
    if (software['version'] != '6.8' ||
        warnings['incompleteResults'] != false ||
        value['matches'] is! List<dynamic>) {
      throw const FormatException('Неполный ответ или другая версия LT');
    }
    return value;
  }

  void close() => _client.close(force: true);
}
