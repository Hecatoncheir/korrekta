import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../bin/rank_hunspell_choices.dart' as ranker;

void main() {
  test(
    'HTTP отправляет только подготовленный вход; неверный выбор не применяется',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      var answer = 2;
      var done = 'stop';
      server.listen((request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        expect(body['raw'], true);
        expect(body['prompt'], 'подготовленный вход без эталона');
        expect(body.containsKey('expected'), false);
        expect(body.containsKey('text'), false);
        request.response.write(
          jsonEncode({
            'response': jsonEncode({
              'choices': [answer],
            }),
            'done_reason': done,
          }),
        );
        await request.response.close();
      });
      final row = <String, dynamic>{
        'text': 'он пишит.',
        'rendered_prompt': 'подготовленный вход без эталона',
        'expected': [
          {'original': 'пишит', 'replacement': 'пишет'},
        ],
        'slots': [
          {
            'start': 3,
            'original': 'пишит',
            'options': ['пишит', 'пишет'],
          },
        ],
      };
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      try {
        final invalid = await ranker.decide(client, endpoint, row);
        expect(invalid['status'], 'invalid_response');
        expect(invalid['output'], 'он пишит.');
        answer = 1;
        expect(
          (await ranker.decide(client, endpoint, row))['output'],
          'он пишет.',
        );
        done = 'length';
        expect(
          (await ranker.decide(client, endpoint, row))['output'],
          'он пишит.',
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
