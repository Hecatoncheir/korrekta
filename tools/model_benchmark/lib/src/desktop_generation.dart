import 'dart:convert';

import 'cli.dart' show generationOptions;
import 'ensemble.dart' show gigaPrompt;

const compactModel = 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M';

typedef GenerationRequest = ({String api, Map<String, dynamic> body});

GenerationRequest generationRequest(
  String model,
  String instruction,
  Map<String, dynamic> payload,
  Map<String, dynamic> schema,
  int tokens,
) {
  final common = <String, dynamic>{
    'model': model,
    'format': schema,
    'stream': false,
    'think': false,
    'keep_alive': '10m',
    'truncate': false,
    'shift': false,
    'options': {
      ...generationOptions(false),
      'num_ctx': 8192,
      'num_predict': tokens,
    },
  };
  if (model == compactModel) {
    // Ollama применяет собственный шаблон 3.1 из выбранной GGUF-модели.
    return (
      api: 'chat',
      body: {
        ...common,
        'messages': [
          {'role': 'system', 'content': instruction},
          {'role': 'user', 'content': jsonEncode(payload)},
        ],
      },
    );
  }
  return (
    api: 'generate',
    body: {...common, 'raw': true, 'prompt': gigaPrompt(instruction, payload)},
  );
}

String generationContent(Map<String, dynamic> response, String api) =>
    switch ((api, response)) {
      ('generate', {'response': final String content}) => content,
      (
        'chat',
        {'message': {'role': 'assistant', 'content': final String content}},
      ) =>
        content,
      _ => throw const FormatException('GigaChat не вернул текст ответа'),
    };
