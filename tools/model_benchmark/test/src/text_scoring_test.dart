import 'package:korrekta_model_benchmark/src/text_scoring.dart';
import 'package:test/test.dart';

void main() {
  test('Полный текст учитывает верную правку и лишнюю замену ё', () {
    final score = scoreText('Мне нравиться ее рассказ.', [
      {'original': 'нравиться', 'replacement': 'нравится'},
    ], 'Мне нравится её рассказ.');
    expect(score['atomic_tp'], 1);
    expect(score['atomic_fp'], 1);
    expect(score['matched_corrections'], 1);
    expect(score['exact'], false);
  });
  test('Часть составной правки не равна исправленной ошибке', () {
    final score = scoreText('Книга которую я купил лежит здесь.', [
      {
        'original': 'Книга которую я купил лежит',
        'replacement': 'Книга, которую я купил, лежит',
      },
    ], 'Книга, которую я купил лежит здесь.');
    expect(score['atomic_tp'], 1);
    expect(score['atomic_fn'], 1);
    expect(score['matched_corrections'], 0);
  });
  test('Вставка после эмодзи оценивается без привязки к подстроке', () {
    final score = scoreText('🙂 Да да.', [
      {'original': 'Да да', 'replacement': 'Да, да'},
    ], '🙂 Да, да.');
    expect(score['atomic_tp'], 1);
    expect(score['atomic_fp'], 0);
    expect(score['exact'], true);
  });
  test('Пробелы и оформление в правильном тексте не нормализуются', () {
    final score = scoreText('Мне бы кофе.\n', [], 'Мне бы кофе.');
    expect(score['changed_control'], true);
    expect(score['atomic_fp'], 1);
  });
}
