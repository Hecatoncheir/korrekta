import 'dart:convert';

import 'scoring.dart';

const textResponseSchema = <String, Object>{
  'type': 'object',
  'properties': {
    'text': {'type': 'string'},
  },
  'required': ['text'],
  'additionalProperties': false,
};

JsonMap evaluateResponse(
  String text,
  List<dynamic> expected,
  String content,
  String mode,
) {
  Object? parsed;
  if (mode == 'text') {
    parsed = content;
  } else {
    try {
      parsed = jsonDecode(content);
    } on FormatException {
      parsed = null;
    }
  }
  if (mode == 'edits') {
    final valid = validSchema(parsed);
    final predicted = valid
        ? (parsed as JsonMap)['edits'] as List<dynamic>
        : <dynamic>[];
    return {
      'predicted': parsed,
      'schema_valid': valid,
      ...scoreCase(text, expected, predicted),
      if (!valid) 'invalid_response': content,
    };
  }
  final valid = mode == 'text'
      ? content.isNotEmpty
      : parsed is JsonMap && parsed.length == 1 && parsed['text'] is String;
  final corrected = valid
      ? (mode == 'text' ? content : (parsed as JsonMap)['text'] as String)
      : text;
  // Для общих метрик оценивается весь результат, без обрезки и нормализации.
  final predicted = corrected == text
      ? <dynamic>[]
      : <dynamic>[
          {'original': text, 'replacement': corrected},
        ];
  return {
    'predicted': parsed,
    'schema_valid': valid,
    ...scoreCase(text, expected, predicted),
    if (!valid) 'exact': false,
    if (!valid) 'invalid_response': content,
  };
}
