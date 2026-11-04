import 'package:korrekta_model_benchmark/src/dictionary_checker.dart';
import 'package:korrekta_model_benchmark/src/ensemble_roles.dart';
import 'package:test/test.dart';

Map<String, dynamic> row(
  String text,
  String original,
  List<String> options,
  List<List<String>> sources, {
  bool known = true,
  List<List<String>>? categories,
  List<bool>? style,
}) => {
  'text': text,
  'slots': [
    {
      'start': text.indexOf(original),
      'original': original,
      'options': options,
      'sources': sources,
    },
  ],
  'role_features': [
    {
      'grammar_alert': false,
      'options': [
        for (var i = 0; i < options.length; i++)
          {
            'known': i == 0 ? known : true,
            'lt_categories': categories?[i] ?? [],
            'lt_preferred': i > 0,
            'style_risk': style?[i] ?? false,
          },
      ],
    },
  ],
};

class Lexicon implements WordDictionary {
  @override
  Future<bool> knows(String word, String language) async => word == 'хочет';
  @override
  Future<List<String>> suggest(String word) async => [];
}

void main() {
  test('Более близкая согласованная замена сохраняет форму автора', () {
    final data = row(
      'Редактор исправляит текст.',
      'исправляит',
      ['исправляит', 'исправляет', 'исправит'],
      [
        [],
        ['hunspell', 'symspell', 'languagetool'],
        ['gigachat', 'hunspell'],
      ],
      known: false,
    );
    expect(
      chooseRoles(data, 'inflections')['output'],
      'Редактор исправляет текст.',
    );
  });
  test(
    'Ё сохраняется в готовом эквивалентном варианте при другой опечатке',
    () {
      final data = row(
        'Встреча начнёться позже.',
        'начнёться',
        ['начнёться', 'начнётся', 'начнется'],
        [
          [],
          ['hunspell', 'languagetool'],
          ['gigachat', 'languagetool'],
        ],
        known: false,
      );
      expect(
        chooseRoles(data, 'inflections')['output'],
        'Встреча начнётся позже.',
      );
    },
  );
  test(
    'Контекст выбирает правильную форму дальше первого словарного варианта',
    () {
      final data = row(
        'Она хочеть петь.',
        'хочеть',
        ['хочеть', 'хотеть', 'хочет'],
        [
          [],
          ['hunspell', 'symspell', 'languagetool'],
          ['hunspell', 'symspell', 'languagetool', 'gigachat'],
        ],
        known: false,
      );
      expect(chooseRoles(data, 'agreement')['output'], 'Она хочет петь.');
    },
  );
  test('Строгое согласие источников не считается разрешением менять имя после явной подсказки', () {
    final data = row(
      'автор орив пишет.',
      'орив',
      ['орив', 'обрыв'],
      [
        [],
        ['hunspell', 'symspell', 'languagetool', 'gigachat'],
      ],
      known: false,
    );
    expect(chooseRoles(data, 'inflections')['output'], data['text']);
  });
  test('Неоднозначная орфография без контекста остаётся на просмотр', () {
    final data = row(
      'Она хочеть петь.',
      'хочеть',
      ['хочеть', 'хотеть', 'хочет'],
      [
        [],
        ['hunspell', 'symspell', 'languagetool'],
        ['hunspell', 'symspell', 'languagetool'],
      ],
      known: false,
    );
    expect(chooseRoles(data, 'clauses')['choices'], [0]);
  });
  test(
    'Единственное согласованное написание можно исправить без голоса модели',
    () {
      final data = row(
        'Нужен коментарий.',
        'коментарий',
        ['коментарий', 'комментарий'],
        [
          [],
          ['hunspell', 'symspell', 'languagetool'],
        ],
        known: false,
      );
      expect(chooseRoles(data, 'agreement')['output'], 'Нужен комментарий.');
    },
  );
  test(
    'Нельзя принять стилистическую замену только из-за согласия LT и модели',
    () {
      final data = row(
        'С днём рожденья!',
        'рожденья',
        ['рожденья', 'рождения'],
        [
          [],
          ['gigachat', 'languagetool'],
        ],
        style: [false, true],
      );
      expect(chooseRoles(data, 'inflections')['choices'], [0]);
    },
  );
  test(
    'Вариативное согласование сохраняется и при грамматическом сигнале LT',
    () {
      final data = row(
        'Большинство гостей ушло.',
        'ушло',
        ['ушло', 'ушли'],
        [
          [],
          ['gigachat', 'languagetool'],
        ],
        categories: [
          [],
          ['GRAMMAR'],
        ],
      );
      expect(chooseRoles(data, 'inflections')['choices'], [0]);
    },
  );
  test('Необязательная запятая после обстоятельства отклоняется', () {
    final data = row(
      'Согласно плану всё готово.',
      '',
      ['', ','],
      [
        [],
        ['gigachat'],
      ],
    );
    (data['slots'] as List<dynamic>).first['start'] = 14;
    expect(chooseRoles(data, 'inflections')['output'], data['text']);
  });
  test('Запятая перед придаточным доступна роли clauses, но не agreement', () {
    final data = row(
      'Я знаю что он придёт.',
      '',
      ['', ','],
      [
        [],
        ['gigachat'],
      ],
    );
    (data['slots'] as List<dynamic>).first['start'] = 6;
    expect(chooseRoles(data, 'clauses')['output'], 'Я знаю, что он придёт.');
    expect(chooseRoles(data, 'agreement')['choices'], [0]);
  });
  test('Составной союз не делится запятой без независимого правила', () {
    final data = row(
      'Мы ушли потому что поздно.',
      '',
      ['', ','],
      [
        [],
        ['gigachat'],
      ],
    );
    (data['slots'] as List<dynamic>).first['start'] = 14;
    expect(chooseRoles(data, 'clauses')['choices'], [0]);
  });
  test(
    'Грамматика без переписывания исходника используется как отдельный сигнал',
    () async {
      final data = row(
        'Она хочеть петь.',
        'хочеть',
        ['хочеть', 'хочет'],
        [
          [],
          ['gigachat'],
        ],
        known: false,
      );
      data['lt_response'] = {
        'matches': [
          {
            'offset': 4,
            'length': 6,
            'replacements': <dynamic>[],
            'rule': {
              'id': 'agreement',
              'description': 'Согласование',
              'category': {'id': 'GRAMMAR'},
            },
          },
        ],
      };
      final features = await roleFeatures(data, Lexicon());
      expect(features.single['grammar_alert'], isTrue);
      expect(
        ((features.single['options'] as List<dynamic>)[1]
            as Map<String, dynamic>)['lt_categories'],
        isEmpty,
      );
      data['role_features'] = features;
      expect(chooseRoles(data, 'agreement')['output'], 'Она хочет петь.');
    },
  );
}
