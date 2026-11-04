import 'package:korrekta_model_benchmark/src/confirmation_response.dart';
import 'package:test/test.dart';

void main() {
  final response = <String, dynamic>{
    'matches': [
      {
        'offset': 3,
        'length': 5,
        'rule': {'id': 'SPELLING'},
        'replacements': [
          {'value': 'пишет'},
        ],
      },
    ],
  };
  final row = <String, dynamic>{
    'text': 'он пишит.',
    'output': 'он пишет.',
    'schema_valid': true,
    'done_reason': 'stop',
    'seconds': 1.0,
    'content': '{"text":"он пишет."}',
  };
  test(
    'Разметка эталонов и защищённых фрагментов недоступна подтверждению',
    () {
      final first = confirmationProfiles(
        {
          ...row,
          'expected': <dynamic>[],
          'protected': ['пишит'],
        },
        response,
        0.1,
      );
      final second = confirmationProfiles(
        {
          ...row,
          'expected': [
            {'original': 'пишит', 'replacement': 'пишет'},
          ],
          'protected': ['он'],
        },
        response,
        0.1,
      );
      expect(first['joint']!['output'], 'он пишет.');
      expect(second['joint']!['output'], first['joint']!['output']);
      expect(second['joint']!['confirmation'], first['joint']!['confirmation']);
    },
  );
  test('Ошибка модели не разрешает её правки, LT измеряется независимо', () {
    final results = confirmationProfiles(
      {...row, 'expected': <dynamic>[], 'error': 'model unavailable'},
      response,
      0.1,
    );
    expect(results['joint']!['output'], 'он пишит.');
    expect(results['joint']!['exact'], false);
    expect(results['lt-first']!['output'], 'он пишет.');
    expect(results['lt-first']!.containsKey('error'), false);
  });
}
