import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';
import 'support/vim_keys.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;

void main() {
  testWidgets('Русские р/о/л/д двигают курсор как h/j/k/l', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = makeCubit(FakeChecker(), MemoryStore())
      ..edit('абв\nгде\nёжз');
    await tester.pumpWidget(testApp(cubit));
    await tester.tap(find.byKey(const Key('vim-toggle')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byKey(const Key('editor')))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    for (final (physical, character, offset) in [
      (PhysicalKeyboardKey.keyH, 'р', 0),
      (PhysicalKeyboardKey.keyL, 'д', 1),
      (PhysicalKeyboardKey.keyJ, 'о', 5),
      (PhysicalKeyboardKey.keyK, 'л', 1),
    ]) {
      await russianKey(tester, physical, character);
      await tester.pumpAndSettle();
      expect(controller.selection.extentOffset, offset);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await russianKey(tester, PhysicalKeyboardKey.digit4, ';');
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 2);
    await russianKey(tester, PhysicalKeyboardKey.digit6, ':');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 0);
    expect(controller.text, 'абв\nгде\nёжз');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });

  testWidgets(
    'Русские команды удаления, отмены, выделения и s не мешают Insert',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cubit = makeCubit(FakeChecker(), MemoryStore())..edit('раз два');
      await tester.pumpWidget(testApp(cubit));
      await tester.tap(find.byKey(const Key('vim-toggle')));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(const Key('editor')))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await russianKey(tester, PhysicalKeyboardKey.keyD, 'в');
      await russianKey(tester, PhysicalKeyboardKey.keyW, 'ц');
      await tester.pumpAndSettle();
      expect(controller.text, 'два');
      await russianKey(tester, PhysicalKeyboardKey.keyU, 'г');
      await tester.pumpAndSettle();
      expect(controller.text, 'раз два');
      await russianKey(tester, PhysicalKeyboardKey.keyV, 'м');
      await russianKey(tester, PhysicalKeyboardKey.keyS, 'ы');
      await tester.pumpAndSettle();
      expect(controller.text, 'аз два');
      expect(find.textContaining('INSERT'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('editor')),
        'Русский ввод: р о л д ы',
      );
      await tester.pumpAndSettle();
      expect(cubit.state.text, 'Русский ввод: р о л д ы');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await cubit.close();
    },
  );

  testWidgets('s в русской раскладке заменяет символ и включает Insert', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = makeCubit(FakeChecker(), MemoryStore());
    await tester.pumpWidget(testApp(cubit));
    await tester.tap(find.byKey(const Key('vim-toggle')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byKey(const Key('editor')))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyS,
      physicalKey: PhysicalKeyboardKey.keyS,
      character: 'ы',
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'не нравиться читать.');
    expect(find.textContaining('INSERT'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('editor'))).readOnly,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('editor')),
      'Я не нравиться читать.',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyU,
      physicalKey: PhysicalKeyboardKey.keyU,
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Мне нравиться читать.');
    expect(find.textContaining('NORMAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });

  testWidgets('Vim mode переключается и обрабатывает события клавиш', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = makeCubit(FakeChecker(), MemoryStore());
    await tester.pumpWidget(testApp(cubit));
    await tester.tap(find.byKey(const Key('vim-toggle')));
    await tester.pumpAndSettle();
    expect(cubit.state.settings.vimMode, isTrue);
    expect(find.textContaining('NORMAL'), findsOneWidget);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyX,
      physicalKey: PhysicalKeyboardKey.keyX,
    );
    await tester.pumpAndSettle();
    expect(cubit.state.text, 'не нравиться читать.');
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyU,
      physicalKey: PhysicalKeyboardKey.keyU,
    );
    await tester.pumpAndSettle();
    expect(cubit.state.text, 'Мне нравиться читать.');
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyI,
      physicalKey: PhysicalKeyboardKey.keyI,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('INSERT'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('editor')), 'Новый текст 🙂');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('NORMAL'), findsOneWidget);
    expect(cubit.state.text, 'Новый текст 🙂');
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });
  testWidgets('Редактор проверяет, применяет и отменяет правку', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = makeCubit(FakeChecker(), MemoryStore());
    await tester.pumpWidget(testApp(cubit));
    expect(
      tester.getSize(find.byKey(const Key('editor-header'))).height,
      tester.getSize(find.byKey(const Key('suggestions-header'))).height,
    );
    await tester.tap(find.byKey(const Key('check')));
    await tester.pumpAndSettle();
    expect(find.text('Рекомендуем исправить'), findsOneWidget);
    await tester.tap(find.text('Принять рекомендованные'));
    await tester.pumpAndSettle();
    expect(cubit.state.text, 'Мне нравится читать.');
    await tester.tap(find.byTooltip('Отменить замену'));
    await tester.pumpAndSettle();
    expect(cubit.state.text, 'Мне нравиться читать.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });

  testWidgets('Узкое окно и переход в настройки сохраняют черновик', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = makeCubit(FakeChecker(), MemoryStore());
    await tester.pumpWidget(testApp(cubit));
    await tester.enterText(find.byKey(const Key('editor')), 'Текст 🙂');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(
      find.text('10В — Лучшее соотношение скорость - качество'),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('Редактор'));
    await tester.pumpAndSettle();
    expect(cubit.state.text, 'Текст 🙂');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
  });
}
