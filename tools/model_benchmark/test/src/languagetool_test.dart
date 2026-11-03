import 'package:korrekta_model_benchmark/src/languagetool.dart';
import 'package:test/test.dart';

Map<String, dynamic> notice(int start, int length, List<String> values) => {
  'offset': start,
  'length': length,
  'replacements': [
    for (final value in values) {'value': value},
  ],
};

void main() {
  test('UTF-16 диапазон после эмодзи указывает на нужное повторение', () {
    final result = applyLanguageTool('🙂 кот кот', [
      notice(7, 3, ['кит']),
    ]);
    expect(result['output'], '🙂 кот кит');
  });
  test('Первый вариант выбирается без знания эталона', () {
    final result = applyLanguageTool('Ашыбка', [
      notice(0, 6, ['Ошибка', 'ошибка']),
    ]);
    expect(result['output'], 'Ошибка');
  });
  test('Вставки и удаления применяются справа налево', () {
    final result = applyLanguageTool('Да  я', [
      notice(2, 1, ['']),
      notice(5, 0, ['.']),
    ]);
    expect(result['output'], 'Да я.');
  });
  test(
    'Пересечение отклоняется, замечание без замены сохраняется в счётчике',
    () {
      final result = applyLanguageTool('кот', [
        notice(0, 3, ['кит']),
        notice(1, 1, ['а']),
        notice(0, 3, []),
      ]);
      expect(result['output'], 'кит');
      expect(result['notice_count'], 3);
      expect(result['without_replacement'], 1);
      expect(result['rejected'], hasLength(1));
    },
  );
  test('Диапазон вне исходной строки не применяется', () {
    expect(
      () => applyLanguageTool('кот', [
        notice(1, 5, ['кит']),
      ]),
      throwsFormatException,
    );
  });
}
