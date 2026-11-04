import 'package:korrekta_model_benchmark/src/languagetool_gate.dart';
import 'package:test/test.dart';

Map<String, dynamic> match(int offset, int length, List<String> variants) => {
  'offset': offset,
  'length': length,
  'rule': {'id': 'TEST_RULE'},
  'replacements': [
    for (final value in variants) {'value': value},
  ],
};

void main() {
  test('Одинаковая замена подтверждается и сохраняет правило', () {
    final result = confirmText('он пишит.', 'он пишет.', [
      match(3, 5, ['пишет']),
    ]);
    expect(result.output, 'он пишет.');
    expect(result.confirmed.single.ruleId, 'TEST_RULE');
  });
  test('Рассматривается не только первый вариант LT', () {
    expect(
      confirmText('он пишит.', 'он пишет.', [
        match(3, 5, ['пищит', 'пишет']),
      ]).output,
      'он пишет.',
    );
  });
  test('Замечание с широким контекстом подтверждает ту же запятую', () {
    expect(
      confirmText('Я знаю что он придёт.', 'Я знаю, что он придёт.', [
        match(2, 8, ['знаю, что']),
      ]).output,
      'Я знаю, что он придёт.',
    );
  });
  test('Отсутствие замечаний не разрешает стилистическую замену', () {
    final result = confirmText('Можно попроще?', 'Можно проще?', []);
    expect(result.output, 'Можно попроще?');
    expect(result.unconfirmed, hasLength(1));
  });
  test('Одного пересечения диапазона недостаточно', () {
    expect(
      confirmText('он пишит.', 'он пишет.', [
        match(3, 5, ['пищит']),
      ]).output,
      'он пишит.',
    );
  });
  test('Повторяющиеся слова различаются по позиции UTF-16 после эмодзи', () {
    const text = '🙂 он пишит и пишит.';
    expect(
      confirmText(text, '🙂 он пишет и пишет.', [
        match(text.lastIndexOf('пишит'), 5, ['пишет']),
      ]).output,
      '🙂 он пишит и пишет.',
    );
  });
  test('Согласие LT не отменяет защиту имени и оформления', () {
    const source = 'Аурика пишит.\n\n';
    expect(
      confirmText(source, 'Аурица пишет.\n', [
        match(0, 6, ['Аурица']),
        match(7, 5, ['пишет']),
        match(13, 2, ['\n']),
      ]).output,
      'Аурика пишет.\n\n',
    );
  });
  test('Без явного варианта замены замечание не подтверждает правку', () {
    expect(
      confirmText('он пишит.', 'он пишет.', [match(3, 5, [])]).output,
      'он пишит.',
    );
  });
  test('Не применяет подтверждение к изменённому снимку', () {
    final result = confirmText('он пишит.', 'он пишет.', [
      match(3, 5, ['пишет']),
    ]);
    expect(() => result.applyTo('он уже пишит.'), throwsStateError);
  });
  test('Неверные диапазоны и разрыв суррогатной пары отклоняются', () {
    expect(
      () => confirmText('🙂 текст.', '🙂 текст.', [
        match(1, 1, ['а']),
      ]),
      throwsFormatException,
    );
    expect(
      () => confirmText('текст.', 'текст.', [
        match(40, 1, ['а']),
      ]),
      throwsFormatException,
    );
  });
  test('Составное замечание не разрешает только половину своей замены', () {
    const text = 'он пишит и читаит.';
    final result = confirmText(text, 'он пишет и читает.', [
      match(3, 14, ['пишет и читает']),
    ]);
    expect(result.output, text);
  });
}
