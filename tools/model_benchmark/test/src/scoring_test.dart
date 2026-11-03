import 'package:korrekta_model_benchmark/src/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('Разная ширина контекста не меняет оценку исправления', () {
    final score = scoreCase(
      'Мне нравиться читать.',
      [
        {'original': 'нравиться', 'replacement': 'нравится'},
      ],
      [
        {'original': 'Мне нравиться', 'replacement': 'Мне нравится'},
      ],
    );
    expect(score['tp'], 1);
    expect(score['fp'], 0);
    expect(score['exact'], true);
  });
  test('Две отдельные запятые эквивалентны общей замене', () {
    const text = 'Книга которую я купил лежит здесь.';
    final score = scoreCase(
      text,
      [
        {
          'original': 'Книга которую я купил лежит',
          'replacement': 'Книга, которую я купил, лежит',
        },
      ],
      [
        {'original': 'Книга', 'replacement': 'Книга,'},
        {'original': 'купил', 'replacement': 'купил,'},
      ],
    );
    expect(score['tp'], 1);
    expect(score['correct_predictions'], 2);
    expect(score['fp'], 0);
    expect(score['exact'], true);
  });
  test('Часть составной правки не считается полным исправлением', () {
    final score = scoreCase(
      'Книга которую я купил лежит здесь.',
      [
        {
          'original': 'Книга которую я купил лежит',
          'replacement': 'Книга, которую я купил, лежит',
        },
      ],
      [
        {'original': 'Книга', 'replacement': 'Книга,'},
      ],
    );
    expect(score['tp'], 0);
    expect(score['correct_predictions'], 1);
    expect(score['fp'], 0);
    expect(score['fn'], 1);
  });
  test('Повторяющийся фрагмент нельзя применить к первому совпадению', () {
    final result = locateEdits('Я пишу. Ты пишу.', [
      {'original': 'пишу', 'replacement': 'пишешь'},
    ]);
    expect(result.edits, isEmpty);
    expect(result.rejected, hasLength(1));
  });
  test('Пересекающиеся и отсутствующие фрагменты отклоняются', () {
    final result = locateEdits('Мне нравиться писать.', [
      {'original': 'Мне нравиться', 'replacement': 'Мне нравится'},
      {'original': 'нравиться', 'replacement': 'нравится'},
      {'original': 'чужой текст', 'replacement': 'замена'},
    ]);
    expect(result.edits, hasLength(1));
    expect(result.rejected, hasLength(2));
  });
  test('Unicode до исправления не сдвигает диапазон', () {
    final edits = locateEdits('🙂 Мне нравиться писать.', [
      {'original': 'нравиться', 'replacement': 'нравится'},
    ]);
    expect(
      applyEdits('🙂 Мне нравиться писать.', edits.edits),
      '🙂 Мне нравится писать.',
    );
    expect(diffKeys('🙂 а', '🙂 б'), {'[3,4,"б"]'});
  });
  test('Переписывание правильной фразы — ложная подсказка', () {
    final score = scoreCase('Мне бы кофе.', [], [
      {'original': 'Мне бы кофе.', 'replacement': 'Я хотел бы кофе.'},
    ]);
    expect(score['fp'], 1);
    expect(score['false_notice'], true);
  });
  test('Отдельно распознаётся неправильная структура ответа', () {
    expect(validSchema({'edits': <dynamic>[]}), true);
    expect(
      validSchema({
        'edits': [
          {'original': 'а', 'replacement': 'б'},
        ],
      }),
      false,
    );
    expect(validSchema({'text': 'ответ'}), false);
  });
}
