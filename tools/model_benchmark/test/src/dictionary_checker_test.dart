import 'package:korrekta_model_benchmark/src/dictionary_checker.dart';
import 'package:korrekta_model_benchmark/src/dictionary_engines.dart';
import 'package:korrekta_model_benchmark/src/symspell.dart';
import 'package:test/test.dart';

class TestDictionary implements WordDictionary {
  TestDictionary(this.ru, {this.en = const {}, this.replacements = const {}});
  final Set<String> ru;
  final Set<String> en;
  final Map<String, List<String>> replacements;
  @override
  Future<bool> knows(String word, String language) async =>
      (language == 'ru' ? ru : en).contains(dictionaryKey(word));
  @override
  Future<List<String>> suggest(String word) async => replacements[word] ?? [];
}

void main() {
  test('OSA считает перестановку одной операцией', () {
    expect(spellingDistance('кот', 'кто'), 1);
    expect(spellingDistance('письмо', 'писмо'), 1);
    expect(spellingDistance('текст', 'тексты'), 1);
  });
  test('Симметричные удаления находят вставку, удаление и перестановку', () {
    final index = SymSpellIndex({'письмо': 100, 'привет': 80});
    expect(index.lookup('писмо').first, 'письмо');
    expect(index.lookup('писььмо').first, 'письмо');
    expect(index.lookup('привте').first, 'привет');
  });
  test('Частота ранжирует варианты при равном расстоянии', () {
    final index = SymSpellIndex({'пишет': 100, 'пищит': 10});
    expect(index.lookup('пишит').first, 'пишет');
    expect(index.lookup('абракадабра'), isEmpty);
  });
  test('Поиск учитывает изменения за пределами префикса', () {
    expect(
      SymSpellIndex({'автоматически': 3}).lookup('автоматическки').first,
      'автоматически',
    );
  });
  test('е/ё нормализуются только для словарного поиска', () async {
    final dictionary = TestDictionary({'ее'});
    expect((await checkDictionaryText('её', dictionary)).output, 'её');
  });
  test(
    'Слово из словаря не переписывается ради частоты или грамматики',
    () async {
      final dictionary = TestDictionary(
        {'я', 'хочет', 'попроще'},
        replacements: {
          'хочет': ['хочу'],
          'попроще': ['проще'],
        },
      );
      expect(
        (await checkDictionaryText('я хочет попроще', dictionary)).output,
        'я хочет попроще',
      );
    },
  );
  test('Имя и CRLF сохраняются, правка рядом остаётся', () async {
    final dictionary = TestDictionary(
      {},
      replacements: {
        'аурика': ['аурица'],
        'пишит': ['пишет'],
      },
    );
    expect(
      (await checkDictionaryText(
        'Аурика\r\n\t  пишит. 👩🏽‍🔬',
        dictionary,
      )).output,
      'Аурика\r\n\t  пишет. 👩🏽‍🔬',
    );
  });
  test(
    'Личный словарь защищает строчное имя, включая режим раскладки',
    () async {
      final dictionary = TestDictionary(
        {'пишет'},
        replacements: {
          'ливея': ['ливия'],
          'пишит': ['пишет'],
        },
      );
      expect(
        (await checkDictionaryText(
          'ливея пишит.',
          dictionary,
          layout: true,
          names: ['Ливея'],
        )).output,
        'ливея пишет.',
      );
    },
  );
  test('Не меняет составную правку с потерей ё', () async {
    final dictionary = TestDictionary(
      {},
      replacements: {
        'начнёться': ['начнется', 'начнётся'],
      },
    );
    expect(
      (await checkDictionaryText('начнёться', dictionary)).output,
      'начнётся',
    );
  });
  test('Сохраняет код, цитату, URL, идентификатор и дефисное слово', () async {
    final dictionary = TestDictionary(
      {},
      replacements: {
        'пишит': ['пишет'],
        'нибудь': ['нибуд'],
      },
    );
    const source =
        '`пишит` «пишит» https://example.test/пишит id_пишит кто-нибудь пишит';
    expect(
      (await checkDictionaryText(source, dictionary)).output,
      '`пишит` «пишит» https://example.test/пишит id_пишит кто-нибудь пишет',
    );
  });
  test('Раскладка исправляет заглавную букву и внутреннюю клавишу ;', () async {
    final dictionary = TestDictionary({'привет', 'нужно'}, en: {'hello'});
    expect(
      (await checkDictionaryText(
        'Ghbdtn ye;yj',
        dictionary,
        layout: true,
      )).output,
      'Привет нужно',
    );
    expect((await checkDictionaryText('Ghbdtn', dictionary)).output, 'Ghbdtn');
  });
  test('Обратная раскладка включает короткое is', () async {
    final dictionary = TestDictionary({}, en: {'the', 'model', 'is', 'ready'});
    expect(
      (await checkDictionaryText(
        'Еру ьщвуд шы куфвн',
        dictionary,
        layout: true,
      )).output,
      'The model is ready',
    );
  });
  test(
    'Раскладка не трогает известное английское слово, код и цитату',
    () async {
      final dictionary = TestDictionary({'привет'}, en: {'flutter'});
      expect(
        (await checkDictionaryText(
          'Flutter API `ghbdtn` «ghbdtn» ghbdtn_2',
          dictionary,
          layout: true,
        )).output,
        'Flutter API `ghbdtn` «ghbdtn» ghbdtn_2',
      );
    },
  );
  test('Снимок и позиция после составного эмодзи проверяются', () async {
    final dictionary = TestDictionary(
      {},
      replacements: {
        'пишит': ['пишет'],
      },
    );
    const source = '👩🏽‍🔬 пишит';
    final result = await checkDictionaryText(source, dictionary);
    expect(result.edits.single.start, source.indexOf('пишит'));
    expect(() => result.applyTo('другой текст'), throwsStateError);
  });
  test('Парсер настоящего протокола Hunspell сохраняет порядок', () {
    expect(parseHunspellReply(['*']).correct, true);
    expect(parseHunspellReply(['+ корень']).correct, true);
    expect(parseHunspellReply(['# слово 0']).suggestions, isEmpty);
    expect(parseHunspellReply(['& пишит 2 0: пишет, пищит']).suggestions, [
      'пишет',
      'пищит',
    ]);
    expect(() => parseHunspellReply([]), throwsFormatException);
    expect(() => parseHunspellReply(['неизвестно']), throwsFormatException);
  });
}
