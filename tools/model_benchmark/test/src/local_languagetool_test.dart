import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/local_languagetool.dart';
import 'package:test/test.dart';

void main() {
  test('Запрещает внешний адрес', () {
    expect(
      () => LocalLanguageTool(Uri.parse('https://example.test')),
      throwsFormatException,
    );
  });
  test('Передаёт Unicode и спецсимволы, отклоняет неполный ответ', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = LocalLanguageTool(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    var incomplete = false;
    server.listen((request) async {
      final fields = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      expect(fields['text'], '🙂 текст & +\r\n');
      expect(fields['language'], 'ru');
      request.response.write(
        jsonEncode({
          'software': {'version': '6.8'},
          'warnings': {'incompleteResults': incomplete},
          'matches': <dynamic>[],
        }),
      );
      await request.response.close();
    });
    try {
      expect((await client.check('🙂 текст & +\r\n'))['matches'], isEmpty);
      incomplete = true;
      await expectLater(
        client.check('🙂 текст & +\r\n'),
        throwsFormatException,
      );
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
