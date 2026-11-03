import 'package:korrekta_model_benchmark/src/response_contract.dart';
import 'package:test/test.dart';

void main() {
  test('Обычный ответ сохраняет пробелы, переносы и эмодзи дословно', () {
    const text = 'Заголовок\n\n  Текст 🙂\n';
    final result = evaluateResponse(text, [], text, 'text');
    expect(result['output'], text);
    expect(result['exact'], true);
  });
  test('Вступление не удаляется ради улучшения оценки', () {
    final result = evaluateResponse(
      'Всё готово.',
      [],
      'Ответ: Всё готово.',
      'text',
    );
    expect(result['exact'], false);
    expect(result['false_notice'], true);
  });
  test('Простой JSON оценивает исправленный текст', () {
    final result = evaluateResponse(
      'Она согласен.',
      [
        {'original': 'согласен', 'replacement': 'согласна'},
      ],
      '{"text":"Она согласна."}',
      'text-json',
    );
    expect(result['schema_valid'], true);
    expect(result['tp'], 1);
    expect(result['exact'], true);
  });
  test('Неправильная схема не считается правильным результатом', () {
    final result = evaluateResponse(
      'Всё готово.',
      [],
      '{"answer":"Всё готово."}',
      'text-json',
    );
    expect(result['schema_valid'], false);
    expect(result['exact'], false);
    expect(result['output'], 'Всё готово.');
  });
}
