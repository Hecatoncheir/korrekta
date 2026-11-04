import 'package:korrekta_model_benchmark/src/dictionary_checker.dart';
import 'package:korrekta_model_benchmark/src/ensemble.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';
import 'package:test/test.dart';

Map<String, dynamic> lt(int start, int length, String replacement) => {
  'offset': start,
  'length': length,
  'replacements': [
    {'value': replacement},
  ],
};

EnsemblePool pool(
  String text, {
  List<WordChoices> hs = const [],
  List<WordChoices> ss = const [],
  List<dynamic> matches = const [],
  String? giga,
  List<String> names = const [],
}) => buildEnsemble(
  text,
  hunspell: hs,
  symspell: ss,
  matches: matches,
  gigaOutput: giga ?? text,
  names: names,
);

class Dictionary implements WordDictionary {
  Dictionary(this.known);
  final Set<String> known;
  @override
  Future<bool> knows(String word, String language) async =>
      known.contains(word);
  @override
  Future<List<String>> suggest(String word) async => ['вариант'];
}

void main() {
  test('Общий словарь узнаёт слово из любого источника', () async {
    final common = SharedLexicon(Dictionary({'абв'}), Dictionary({'где'}));
    expect(await common.knows('где', 'ru'), isTrue);
    expect(await common.knows('абв', 'ru'), isTrue);
    expect(await common.knows('неизвестное', 'ru'), isFalse);
    expect(await common.suggest('что'), ['вариант']);
  });
  test(
    'Одинаковые предложения объединяют свидетельства без трёх голосов словаря',
    () {
      const text = 'Она хочеть читать.';
      final choices = [
        WordChoices(4, 'хочеть', ['хочеть', 'хочет']),
      ];
      final result = pool(
        text,
        hs: choices,
        ss: choices,
        matches: [lt(4, 6, 'хочет')],
        giga: 'Она хочет читать.',
      );
      expect(result.slots.single.options, ['хочеть', 'хочет']);
      expect(result.evidence.single[1], {
        'hunspell',
        'symspell',
        'languagetool',
        'gigachat',
      });
      expect(result.apply([1], text), 'Она хочет читать.');
    },
  );
  test('Непересекающиеся грамматика и орфография применяются вместе', () {
    const text = 'Он пришол, хотя мы была рядом.';
    final result = pool(
      text,
      hs: [
        WordChoices(3, 'пришол', ['пришол', 'пришёл']),
      ],
      matches: [lt(text.indexOf('была'), 4, 'были')],
    );
    expect(result.apply([1, 1], text), 'Он пришёл, хотя мы были рядом.');
  });
  test('Конфликтующие слова остаются альтернативами, а не последовательными правками', () {
    final result = pool(
      'Она хочеть.',
      hs: [
        WordChoices(4, 'хочеть', ['хочеть', 'хочет', 'хочешь']),
      ],
      giga: 'Она хочет.',
    );
    expect(result.slots.single.options, ['хочеть', 'хочет', 'хочешь']);
    expect(result.apply([2], 'Она хочеть.'), 'Она хочешь.');
    expect(() => result.apply([3], 'Она хочеть.'), throwsFormatException);
  });
  test('Вставка запятой не ломает emoji, пробелы и CRLF', () {
    const text = '🙂 Я знаю что  он здесь.\r\n';
    final result = pool(text, matches: [lt(9, 0, ',')]);
    expect(result.apply([1], text), '🙂 Я знаю, что  он здесь.\r\n');
    expect(() => result.apply([1], '$text!'), throwsStateError);
  });
  test('Защита имён, цитат и личного словаря общая для всех источников', () {
    const text = 'Мирэль пишет «карова» и зовёт норвета.';
    final result = pool(
      text,
      giga: 'Мирель пишет «корова» и зовёт норвежца.',
      names: ['норвета'],
    );
    expect(result.slots, isEmpty);
    expect(result.rejected, isNotEmpty);
  });
  test('Составная правка LT отклоняется целиком при нарушении защиты', () {
    const text = 'Она хочеть видеть Мирэль.';
    final result = pool(text, matches: [lt(4, 19, 'хочет видеть Мирель')]);
    expect(result.slots, isEmpty);
  });
  test(
    'JSON модели нельзя расширить новыми полями или строковыми номерами',
    () {
      expect(
        () => parseChoices('{"c0":1,"text":"другое"}', 1),
        throwsFormatException,
      );
      expect(() => parseChoices('{"c0":"1"}', 1), throwsFormatException);
      expect(() => parseChoices('{"c1":1}', 1), throwsFormatException);
    },
  );
  test('Неправильный диапазон LT не превращается в отсутствие ошибок', () {
    expect(
      () => pool('Текст.', matches: [lt(90, 2, 'да')]),
      throwsFormatException,
    );
  });
}
