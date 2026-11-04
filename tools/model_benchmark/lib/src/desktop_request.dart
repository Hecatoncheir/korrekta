import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> desktopRequest(
  HttpClient client,
  Uri endpoint,
  String api,
  Map<String, dynamic> body,
) async {
  final connection = await client.postUrl(endpoint.replace(path: '/api/$api'));
  connection.followRedirects = false;
  connection.headers.contentType = ContentType.json;
  connection.write(jsonEncode(body));
  final response = await connection.close().timeout(
    const Duration(seconds: 120),
  );
  final raw = await utf8.decoder
      .bind(response)
      .join()
      .timeout(const Duration(seconds: 120));
  if (response.statusCode != 200) {
    throw HttpException('Ollama: HTTP ${response.statusCode}');
  }
  final data = jsonDecode(raw) as Map<String, dynamic>;
  if (data.containsKey('error')) throw StateError('Ollama не завершил запрос');
  return data;
}
