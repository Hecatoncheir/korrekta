import 'dart:convert';

import 'package:korrekta_model_benchmark/src/correction_response.dart';
import 'package:korrekta_model_benchmark/src/desktop_generation.dart';
import 'package:test/test.dart';

void main() {
  test('Скобка, пустота и потерянная большая часть исходника отклоняются', () {
    const original = 'Первая строка.\r\n  Вторая строка с именем Норвета.';
    for (final value in ['{', '', '   ', 'Первая строка.']) {
      expect(
        () => readCorrectionText(original, jsonEncode({'text': value})),
        throwsFormatException,
      );
    }
  });
  test('Полный текст, исправление, CRLF, код и эмодзи не нормализуются', () {
    const original = 'Норвета  проверела код `x=1`.\r\n  Всё 🙂';
    const expected = 'Норвета  проверила код `x=1`.\r\n  Всё 🙂';
    expect(
      readCorrectionText(original, jsonEncode({'text': expected})),
      expected,
    );
    expect(
      readCorrectionText(original, jsonEncode({'text': original})),
      original,
    );
    expect(readCorrectionText('{', '{"text":"{"}'), '{');
  });
  test('Ответ без буквы или цифры не подменяет осмысленный короткий текст', () {
    expect(
      () => readCorrectionText('Я', '{"text":"{"}'),
      throwsFormatException,
    );
    expect(readCorrectionText('2', '{"text":"3"}'), '3');
  });
  test(
    'Лишнее поле, неверный JSON, отсутствие текста не исправляются молча',
    () {
      for (final value in [
        '{',
        '{"text":12}',
        '{"other":"Текст"}',
        '{"text":"Текст","extra":true}',
      ]) {
        expect(() => readCorrectionText('Текст', value), throwsFormatException);
      }
    },
  );
  test('Содержимое chat и generate извлекается строго по выбранному API', () {
    expect(generationContent({'response': 'один'}, 'generate'), 'один');
    expect(
      generationContent({
        'message': {'role': 'assistant', 'content': 'два'},
      }, 'chat'),
      'два',
    );
    expect(
      () => generationContent({'response': 'один'}, 'chat'),
      throwsFormatException,
    );
    expect(
      () => generationContent({
        'message': {'role': 'user', 'content': 'два'},
      }, 'chat'),
      throwsFormatException,
    );
  });
}
