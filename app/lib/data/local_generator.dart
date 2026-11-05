import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/generation.dart';
import '../domain/settings.dart';

abstract interface class TextGenerator {
  Future<GenerationOutput> generate(String prompt, Settings settings);
  void cancel();
}

class LocalGenerator implements TextGenerator {
  LocalGenerator({http.Client Function()? createClient})
    : _createClient = createClient ?? http.Client.new;
  final http.Client Function() _createClient;
  http.Client? _active;

  @override
  Future<GenerationOutput> generate(String prompt, Settings settings) async {
    final api = settings.model == LocalModel.quality ? 'generate' : 'chat';
    final endpoint = localEndpoint(settings.ollama).resolve('/api/$api');
    cancel();
    final client = _createClient();
    _active = client;
    try {
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..body = jsonEncode(generationBody(prompt, settings));
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(minutes: 5));
      if (response.statusCode == 404) {
        throw const FormatException(
          'Выбранная модель не найдена. Загрузите её в настройках.',
        );
      }
      if (response.statusCode != 200) {
        throw const FormatException(
          'Ollama не смог создать текст. Повторите попытку.',
        );
      }
      return readGeneration(jsonDecode(utf8.decode(response.bodyBytes)));
    } finally {
      if (identical(_active, client)) _active = null;
      client.close();
    }
  }

  @override
  void cancel() {
    _active?.close();
    _active = null;
  }
}

const generationInstruction =
    'Ты помощник по созданию текстов. Выполни запрос пользователя. '
    'Соблюдай указанные язык, стиль, объём и оформление. '
    'Если язык не указан, отвечай на языке запроса. '
    'Верни готовый текст без вступления и пояснений, если их не просили.';

Map<String, Object> generationBody(String prompt, Settings settings) => {
  'model': settings.model.id,
  'stream': false,
  'think': false,
  'truncate': false,
  'shift': false,
  'keep_alive': '10m',
  'options': {'temperature': 0.7, 'num_ctx': 8192, 'num_predict': 4096},
  if (settings.model == LocalModel.balanced)
    'messages': [
      {'role': 'system', 'content': generationInstruction},
      {'role': 'user', 'content': prompt},
    ]
  else ...{
    'raw': true,
    'prompt':
        '<s>$generationInstruction<|message_sep|>user<|role_sep|>$prompt'
        '<|message_sep|>available functions<|role_sep|>[]<|message_sep|>'
        'assistant<|role_sep|>',
  },
};

GenerationOutput readGeneration(Object? response) {
  final text = switch (response) {
    {'done': true, 'message': {'role': 'assistant', 'content': String text}} =>
      text,
    {'done': true, 'response': String text} => text,
    _ => '',
  };
  if (text.trim().isEmpty) {
    throw const FormatException('Модель не вернула текст. Повторите попытку.');
  }
  return (
    text: text,
    limited: switch (response) {
      {'done_reason': 'length'} => true,
      _ => false,
    },
  );
}

String generationError(Object error) => switch (error) {
  SocketException() || TimeoutException() || http.ClientException() => 'Ollama не отвечает. Проверьте подключение в настройках и повторите генерацию.',
  FormatException(:final message)
      when message.startsWith('Модель') ||
          message.startsWith('Выбранная') ||
          message.startsWith('Ollama') =>
    message,
  _ => 'Не удалось создать текст. Повторите попытку.',
};
