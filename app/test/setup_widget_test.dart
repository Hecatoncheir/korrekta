import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/settings.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'runtime_setup_test.dart' show ControlledSetup;
import 'support/test_app.dart';

void main() {
  testWidgets(
    'Подготовка начинается сама; редактор доступен, проверка и перевод ждут готовности',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = makeCubit(FakeChecker(), MemoryStore());
      editor.edit('Мой текст');
      final setup = ControlledSetup();
      await tester.pumpWidget(testApp(editor, setup: setup));
      await tester.pump();
      expect(setup.calls, [LocalModel.balanced]);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('check'))).onPressed,
        isNull,
      );
      editor.edit('Можно писать во время подготовки');
      await tester.pump();
      await tester.tap(find.byTooltip('Переводчик'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('translate')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pump();
      await tester.tap(find.text(LocalModel.quality.label));
      await tester.pump();
      expect(editor.state.settings.model, LocalModel.quality);
      expect(setup.calls, [LocalModel.balanced, LocalModel.quality]);
      setup.finish.complete();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Редактор'));
      await tester.pump();
      expect(editor.state.text, 'Можно писать во время подготовки');
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('check'))).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await editor.close();
    },
  );
}
