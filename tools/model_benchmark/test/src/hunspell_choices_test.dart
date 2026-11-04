import 'package:korrekta_model_benchmark/src/dictionary_checker.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';
import 'package:test/test.dart';

class FakeDictionary implements WordDictionary {
  @override
  Future<bool> knows(String word, String language) async =>
      language == 'ru' && word == 'привет';
  @override
  Future<List<String>> suggest(String word) async => switch (word) {
    'пишит' => ['шипит', 'пиши', 'пишет', 'пишет', 'пишет текст'],
    'начнёться' => ['начнется', 'начнётся'],
    'ливея' => ['ливия'],
    _ => [],
  };
}

void main() {
  test('Раскладка передаётся как один разрешённый вариант с отказом', () async {
    final slots = await collectHunspellChoices(
      'ghbdtn',
      FakeDictionary(),
      layout: true,
    );
    expect(slots.single.options, ['ghbdtn', 'привет']);
    expect(selectChoices('ghbdtn', slots, [0]).output, 'ghbdtn');
    expect(selectChoices('ghbdtn', slots, [1]).output, 'привет');
  });
  test(
    'Есть отказ и варианты после первого, без дублей и новых слов',
    () async {
      final slots = await collectHunspellChoices('он пишит.', FakeDictionary());
      expect(slots.single.options, ['пишит', 'шипит', 'пиши', 'пишет']);
      expect(selectChoices('он пишит.', slots, [3]).output, 'он пишет.');
      expect(selectChoices('он пишит.', slots, [0]).output, 'он пишит.');
    },
  );
  test('Имя и личный словарь не передаются на свободное изменение', () async {
    final slots = await collectHunspellChoices(
      'Ливея и ливея пишит.',
      FakeDictionary(),
      names: ['ливея'],
    );
    expect(slots, hasLength(1));
    expect(slots.single.original, 'пишит');
  });
  test('Нельзя удалить ё в составной замене', () async {
    final slots = await collectHunspellChoices('начнёться', FakeDictionary());
    expect(slots.single.options, ['начнёться', 'начнётся']);
  });
  test('Снимок, форматирование и UTF-16 после эмодзи сохраняются', () async {
    const source = '👩🏽‍🔬\r\n\t  он пишит.';
    final slots = await collectHunspellChoices(source, FakeDictionary());
    final selected = selectChoices(source, slots, [3]);
    expect(selected.output, '👩🏽‍🔬\r\n\t  он пишет.');
    expect(() => selected.applyTo('новый текст'), throwsStateError);
  });
  test('Свободный текст и дополнительные поля отклоняются', () {
    expect(
      () => parseChoices('{"text":"переписанный текст"}', 1),
      throwsFormatException,
    );
    expect(() => parseChoices('{"c0":0,"text":"x"}', 1), throwsFormatException);
    expect(() => parseChoices('{"c0":1.0}', 1), throwsFormatException);
    expect(() => parseChoices('{}', 1), throwsFormatException);
  });
  test('Неверный номер, диапазон или пересечение не применяются частично', () {
    final slot = WordChoices(3, 'пишит', ['пишит', 'пишет']);
    expect(
      () => selectChoices('он пишит.', [slot], [-1]),
      throwsFormatException,
    );
    expect(
      () => selectChoices('он пишит.', [slot], [2]),
      throwsFormatException,
    );
    expect(
      () => selectChoices('он пишет.', [slot], [1]),
      throwsFormatException,
    );
    expect(
      () => selectChoices('он пишит.', [slot, slot], [1, 0]),
      throwsFormatException,
    );
  });
  test('Список вариантов заморожен до ответа модели', () {
    final source = ['слово', 'слова'];
    final slot = WordChoices(0, 'слово', source);
    source[1] = 'другой текст';
    expect(slot.options[1], 'слова');
    expect(parseChoices('{"c0":1}', 1), [1]);
  });
}
