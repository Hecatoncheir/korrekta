import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/quality_data.dart';

void main() {
  final item = QualityCase({
    'id': 'fixture',
    'profile': 'empty',
    'group': 'names',
    'kind': 'control',
    'text': 'Лиорель  ждёт.\r\n  `id_07` 👩🏽‍💻',
    'expected': ['Лиорель  ждёт.\r\n  `id_07` 👩🏽‍💻'],
    'names': <String>[],
    'protected': ['Лиорель', '`id_07`', '👩🏽‍💻'],
  });
  test('Сбой не считается чистой проверкой даже при сохранённом исходнике', () {
    final row = score(item, item.text, false);
    expect(row['clean'], isFalse);
    expect(row['falseControl'], isFalse);
  });
  test('Смена имени, эмодзи и CRLF учитывается отдельно от обычной правки', () {
    final row = score(item, 'Лиорел  ждёт.\n  `id_07` 👩‍💻', true);
    expect(row['clean'], isFalse);
    expect(row['falseControl'], isTrue);
    expect(row['protectedLost'], ['Лиорель', '👩🏽‍💻']);
    expect(row['whitespacePreserved'], isFalse);
  });
  test('Лишняя запятая сохраняет имя, но портит правильный контроль', () {
    final row = score(item, 'Лиорель,  ждёт.\r\n  `id_07` 👩🏽‍💻', true);
    expect(row['falseControl'], isTrue);
    expect(row['protectedLost'], isEmpty);
    expect(row['whitespacePreserved'], isTrue);
  });
}
