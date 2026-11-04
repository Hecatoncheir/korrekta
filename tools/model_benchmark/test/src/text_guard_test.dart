import 'package:korrekta_model_benchmark/text_guard.dart';
import 'package:korrekta_model_benchmark/src/guard_response.dart';
import 'package:korrekta_model_benchmark/src/text_diff.dart' show applyEdits;
import 'package:test/test.dart';

void main() {
  test('Unicode diff восстанавливает весь ответ, включая повторения', () {
    for (final pair in [
      ('', '🙂 новый текст'),
      ('🙂 слово слово.', '🙂 слово, слово.'),
      ('а\u0301 б 👨‍👧', 'о\u0301 б 👨‍👧!'),
      ('две строки\n\n', 'одна строка'),
    ]) {
      expect(applyEdits(pair.$1, diffEdits(pair.$1, pair.$2)), pair.$2);
    }
  });
  test('Разметка эталонов не влияет на решение фильтра', () {
    final base = <String, dynamic>{
      'type': 'case',
      'text': 'Аурика проверяит текст.',
      'output': 'Аурица проверяет текст.',
      'seconds': 1.0,
      'done_reason': 'stop',
      'schema_valid': true,
    };
    final first = protectResponse({
      ...base,
      'expected': <dynamic>[],
      'protected': ['проверяит'],
    });
    final second = protectResponse({
      ...base,
      'expected': [
        {'original': 'проверяит', 'replacement': 'проверяет'},
      ],
      'protected': ['Аурика'],
    });
    expect(first['output'], 'Аурика проверяет текст.');
    expect(second['output'], first['output']);
    expect(second['guard'], first['guard']);
  });
  test('Незавершённый ответ не превращается в исправление', () {
    final row = protectResponse({
      'type': 'case',
      'text': 'текст готов.',
      'output': 'текст готов,',
      'seconds': 0.1,
      'done_reason': 'length',
      'schema_valid': true,
      'expected': <dynamic>[],
    });
    expect(row['output'], 'текст готов.');
    expect(
      (row['guard'] as Map<String, dynamic>)['status'],
      'invalid_model_response',
    );
    expect(row['exact'], false);
  });
  group('Независимые правки и защита имён', () {
    test('Сохраняет имя и оставляет полезное исправление рядом', () {
      final result = guardText(
        'Аурика проверяит письмо.',
        'Аурица проверяет письмо.',
      );
      expect(result.output, 'Аурика проверяет письмо.');
      expect(result.accepted, hasLength(1));
      expect(result.rejected, isNotEmpty);
    });
    test('Учитывает личный словарь без изменения регистра исходника', () {
      final result = guardText(
        'автор ливея проверяит текст.',
        'автор ливею проверяет текст.',
        names: ['Ливея'],
      );
      expect(result.output, 'автор ливея проверяет текст.');
    });
    test('Личный словарь защищает все повторения и только целые имена', () {
      final spans = protectedSpans(
        'ливея, ливея и сливея.',
        names: ['Ливея'],
      ).where((span) => span.reason == 'personal_name').toList();
      expect(spans.map((span) => span.start), [0, 7]);
    });
    test('Не разрешает дописать имя на границе защищённого слова', () {
      expect(
        guardText('Аурика пришла.', 'Аурикаа пришла.').output,
        'Аурика пришла.',
      );
    });
    test('Разрешает запятую рядом с именем', () {
      expect(
        guardText('Аурика приди сюда.', 'Аурика, приди сюда.').output,
        'Аурика, приди сюда.',
      );
    });
    test('Первое слово тоже защищено, даже если это не имя', () {
      expect(
        guardText('Каждый придёт.', 'Каждые придёт.').output,
        'Каждый придёт.',
      );
      // Ограничение эвристики: это не распознавание сущностей или грамматики.
    });
  });

  group('Оформление и технические строки', () {
    test('Сохраняет переносы, табуляцию и намеренные пробелы', () {
      const source = 'Заметка:\r\n\t  автор проверяит письмо.\r\n';
      final result = guardText(source, 'Заметка: автор проверяет письмо.');
      expect(result.output, 'Заметка:\r\n\t  автор проверяет письмо.\r\n');
    });
    test('Не меняет цитату, исправляя слово вне неё', () {
      final result = guardText(
        '«Тёплый свет» помогаит автору.',
        '"Теплый свет" помогает автору.',
      );
      expect(result.output, '«Тёплый свет» помогает автору.');
    });
    test('Сохраняет оттенок кожи, ZWJ, флаг и keycap', () {
      const source = '👍🏿 👨‍👧 🇫🇷 1️⃣ текст помогаит.';
      expect(
        guardText(source, '👍🏻 👨 🇨🇦 2️⃣ текст помогает.').output,
        '👍🏿 👨‍👧 🇫🇷 1️⃣ текст помогает.',
      );
    });
    test('Сохраняет Markdown, имена файлов, код и URL', () {
      const source =
          '- **Файл:** notes_42.md `keep=true` https://example.test/a?q=7 помогаит.';
      final result = guardText(
        source,
        '* **Файл**: notes_43.md `keep=false` https://example.test/a?q=8 помогает.',
      );
      expect(
        result.output,
        '- **Файл:** notes_42.md `keep=true` https://example.test/a?q=7 помогает.',
      );
    });
    test('Не меняет содержимое JSON и огороженного кода', () {
      const source =
          '{"ready":true}\n```dart\nfinal v = 1;\n```\nтекст помогаит.';
      expect(
        guardText(
          source,
          '{"ready": false}\n```dart\nfinal v = 2;\n```\nтекст помогает.',
        ).output,
        '{"ready":true}\n```dart\nfinal v = 1;\n```\nтекст помогает.',
      );
    });
    test('Отбрасывает пояснение без потери локальной правки', () {
      expect(
        guardText(
          'автор проверяит текст.',
          'Исправленный текст: автор проверяет текст.',
        ).output,
        'автор проверяет текст.',
      );
    });
    test('Не переписывает порядок слов и не вставляет новые слова', () {
      const source = 'автор хочет читать книгу.';
      expect(guardText(source, 'автор хочет книгу читать.').output, source);
    });
    test('Не меняет е/ё и конечную пунктуацию', () {
      const source = 'мне нравится ее книга 🙂';
      expect(guardText(source, 'мне нравится её книга 🙂.').output, source);
    });
  });

  group('Unicode и привязка к исходнику', () {
    test('Позиции после составных эмодзи остаются UTF-16', () {
      const source = '👩‍🔬 автор проверяит письмо.';
      final result = guardText(source, '👩‍🔬 автор проверяет письмо.');
      expect(result.output, '👩‍🔬 автор проверяет письмо.');
      expect(result.accepted.single.start, source.indexOf('проверяит'));
    });
    test('Защищает букву вместе с комбинируемым ударением', () {
      const source = 'а\u0301втор помогаит.';
      expect(
        guardText(source, 'о\u0301втор помогает.').output,
        'а\u0301втор помогает.',
      );
    });
    test('Не применяет результат к новой версии документа', () {
      final result = guardText('автор проверяит.', 'автор проверяет.');
      expect(() => result.applyTo('🙂 автор проверяит.'), throwsStateError);
    });
    test('Неверный Unicode и слишком большой ответ не обрабатываются', () {
      expect(guardText('текст', 'текст\uD800').failure, 'invalid_unicode');
      final result = guardText('текст', List.filled(5000, 'а').join());
      expect(result.failure, 'diff_limit');
      expect(result.output, 'текст');
    });
  });
}
