import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/draft_store.dart';
import 'package:korrekta/data/local_components.dart';
import 'package:korrekta/domain/settings.dart';

void main() {
  test(
    'Восстановление черновика и модели, резервная копия при повреждении',
    () async {
      final directory = await Directory.systemTemp.createTemp('korrekta-test-');
      try {
        final store = FileDraftStore(File('${directory.path}/draft.json'));
        const settings = Settings(
          model: LocalModel.balanced,
          names: ['Норвета'],
        );
        await store.save((text: 'Первый\r\n  🙂', settings: settings));
        await store.save((text: 'Второй', settings: settings));
        expect(
          (await store.load(const Settings())).settings.model,
          LocalModel.balanced,
        );
        await store.file.writeAsString('{broken');
        final restored = await store.load(const Settings());
        expect(restored.text, 'Первый\r\n  🙂');
        expect(restored.settings.names, ['Норвета']);
        await store.save((text: 'Третий', settings: settings));
        expect(
          await File('${store.file.path}.backup').readAsString(),
          contains('Первый'),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('Запрещены внешние адреса и неожиданные пути', () {
    for (final address in [
      'https://example.org',
      'http://example.org',
      'http://localhost/proxy',
      'http://user@localhost:80',
    ]) {
      expect(() => localEndpoint(address), throwsFormatException);
    }
    expect(localEndpoint('http://127.0.0.1:11435').port, 11435);
  });

  test('Разбор модели и прогресса через patterns', () {
    final model = LocalModel.balanced.id;
    expect(
      LocalComponents.hasModel({
        'models': [
          {'name': model},
        ],
      }, model),
      isTrue,
    );
    expect(
      LocalComponents.hasModel({
        'models': [
          {'name': LocalModel.quality.id},
        ],
      }, model),
      isFalse,
    );
    expect(
      LocalComponents.parseProgress(
        '{"status":"pulling","completed":25,"total":100}',
      ).fraction,
      .25,
    );
    expect(
      () => LocalComponents.parseProgress('{"error":"failure"}'),
      throwsStateError,
    );
  });
}
