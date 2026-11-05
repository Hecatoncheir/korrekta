import 'dart:convert';

final _meaningful = RegExp(r'[\p{L}\p{N}]', unicode: true);

String readCorrectionText(String original, String content) {
  final parsed = jsonDecode(content);
  return switch (parsed) {
    {'text': final String text} when parsed.length == 1 =>
      validateCorrectionText(original, text),
    _ => throw const FormatException('Неправильная структура текста GigaChat'),
  };
}

String validateCorrectionText(String original, String output) {
  if (output == original) return output;
  if (output.trim().isEmpty ||
      output.runes.length * 2 < original.runes.length ||
      _meaningful.hasMatch(original) && !_meaningful.hasMatch(output)) {
    throw const FormatException(
      'GigaChat вернул неполный или непригодный текст',
    );
  }
  return output;
}
