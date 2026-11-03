import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Родной шаблон отправляется в generate без повторного шаблонирования',
    () async {
      final directory = await Directory.systemTemp.createTemp('korrekta-raw-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final Object response;
        switch (request.uri.path) {
          case '/api/version':
            response = {'version': 'test'};
          case '/api/show':
            response = {'template': '{{ .Prompt }}'};
          case '/api/ps':
            response = {'models': <Object>[]};
          case '/api/generate':
            requests.add(jsonDecode(body) as Map<String, dynamic>);
            response = {
              'response': jsonEncode({
                'edits': [
                  {
                    'original': 'нравиться',
                    'replacement': 'нравится',
                    'category': 'grammar',
                    'explanation': 'Форма глагола.',
                  },
                ],
              }),
              'done_reason': 'stop',
            };
          default:
            request.response.statusCode = 404;
            response = {'error': 'Неожиданный путь'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      try {
        final data = File('${directory.path}/cases.jsonl');
        final prompt = File('${directory.path}/prompt.txt');
        final output = File('${directory.path}/results.jsonl');
        await data.writeAsString(
          jsonEncode({
            'id': 'probe',
            'split': 'dev',
            'category': 'verb',
            'text': 'Мне нравиться читать.',
            'edits': [
              {'original': 'нравиться', 'replacement': 'нравится'},
            ],
            'rendered_prompt': '<s>официальный шаблон и текст',
            'rendered_prompt_sha256': 'test-hash',
          }),
        );
        await prompt.writeAsString('Инструкция');
        final arguments = [
          '--model',
          'test',
          '--data',
          data.path,
          '--prompt',
          prompt.path,
          '--split',
          'dev',
          '--output',
          output.path,
          '--endpoint',
          'http://127.0.0.1:${server.port}',
          '--raw',
        ];
        expect(await runCli(arguments), 0);
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request['raw'], true);
          expect(request['prompt'], '<s>официальный шаблон и текст');
          expect(request.containsKey('messages'), false);
          expect(request['format'], isA<Map<String, dynamic>>());
        }
        final records = (await output.readAsLines()).map(
          (line) => jsonDecode(line) as Map<String, dynamic>,
        );
        final result = records.singleWhere((row) => row['type'] == 'case');
        expect(result['output'], 'Мне нравится читать.');
        expect(result['schema_valid'], true);
        expect(result['rendered_prompt_sha256'], 'test-hash');
      } finally {
        await server.close(force: true);
        final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await directory.resolveSymbolicLinks();
        if (!resolved.startsWith(
          '$temporaryRoot${Platform.pathSeparator}korrekta-raw-',
        )) {
          throw StateError('Временный каталог находится вне ожидаемого пути');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
