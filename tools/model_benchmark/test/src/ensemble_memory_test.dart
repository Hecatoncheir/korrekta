import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../bin/ensemble_memory.dart' as probe;

void main() {
  test('Модель и контекст меняются явно; эталоны не передаются, ошибки сохраняются', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    var answer = '{"text":"Она хочет петь."}';
    var done = 'stop';
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      expect(body['raw'], true);
      expect(body['prompt'], 'официальный подготовленный шаблон');
      expect((body['options'] as Map<String, dynamic>)['num_ctx'], 4096);
      expect(body.containsKey('edits'), isFalse);
      request.response.write(
        jsonEncode({'done_reason': done, 'response': answer}),
      );
      await request.response.close();
    });
    final row = {
      'text': 'Она хочеть петь.',
      'rendered_prompt': 'официальный подготовленный шаблон',
      'prompt_tokens': 150,
      'edits': [
        {'original': 'хочеть', 'replacement': 'хочет'},
      ],
    };
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    try {
      expect(
        (await probe.proposal(
          client,
          endpoint,
          'test-model',
          4096,
          row,
        ))['output'],
        'Она хочет петь.',
      );
      answer = '{"text":"Она хочет петь.","extra":1}';
      final invalid = await probe.proposal(
        client,
        endpoint,
        'test-model',
        4096,
        row,
      );
      expect(invalid['output'], row['text']);
      expect(invalid.containsKey('error'), isTrue);
      expect((invalid['response'] as Map<String, dynamic>)['response'], answer);
      done = 'length';
      expect(
        (await probe.proposal(
          client,
          endpoint,
          'test-model',
          4096,
          row,
        )).containsKey('error'),
        isTrue,
      );
      expect(
        () => probe.proposal(client, endpoint, 'test-model', 1024, row),
        throwsFormatException,
      );
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}
