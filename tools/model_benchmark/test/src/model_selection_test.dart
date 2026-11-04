import 'dart:convert';
import 'dart:io';

import 'package:korrekta_model_benchmark/src/desktop_request.dart';
import 'package:korrekta_model_benchmark/desktop.dart';
import 'package:test/test.dart';

void main() {
  test(
    '20B и 10B передаются в настоящий HTTP-запрос без замены модели',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final models = <String>[];
      server.listen((connection) async {
        final body = jsonDecode(
          await utf8.decoder.bind(connection).join(),
        ) as Map<String, dynamic>;
        models.add(body['model'] as String);
        expect(body['options'], containsPair('num_ctx', 8192));
        expect(body['raw'], isTrue);
        connection.response.write(
          '{"done_reason":"stop","response":"{\\"text\\":\\"Текст\\"}"}',
        );
        await connection.response.close();
      });
      final client = HttpClient();
      try {
        for (final model in [
          ensembleModel,
          'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
        ]) {
          await desktopRequest(
            client,
            Uri.parse('http://127.0.0.1:${server.port}'),
            'generate',
            DesktopRuntime.generationBody(model, 'prompt', {
              'type': 'object',
            }, 1024),
          );
        }
        expect(models, [
          ensembleModel,
          'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
        ]);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
