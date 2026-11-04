import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/ui/translation_cubit.dart';
import 'package:korrekta/domain/settings.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'support/test_app.dart';
import 'support/translation_fakes.dart';
import 'support/vim_keys.dart';

void main() {
  testWidgets('Vim в переводе: y/p, обычный ввод и переходы между разделами', (
    tester,
  ) async {
    mockVimClipboard();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = makeCubit(FakeChecker(), MemoryStore());
    final translation = TranslationCubit(
      translator: FakeTranslator(),
      store: MemoryTranslationStore(),
    );
    await tester.pumpWidget(testApp(editor, translation: translation));
    await tester.tap(find.byTooltip('Переводчик'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('translation-input')), 'А🙂Б');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vim-toggle')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('translation-input')),
    );
    expect(field.readOnly, isTrue);
    field.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );
    await russianKey(tester, PhysicalKeyboardKey.keyY, 'н');
    await tester.pumpAndSettle();
    expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, '🙂');
    field.controller!.selection = const TextSelection.collapsed(offset: 3);
    await russianKey(tester, PhysicalKeyboardKey.keyP, 'з');
    await tester.pumpAndSettle();
    expect(translation.state.draft.text, 'А🙂Б🙂');
    await russianKey(tester, PhysicalKeyboardKey.keyI, 'ш');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('translation-input')))
          .readOnly,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('translation-input')),
      'Новый текст',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(translation.state.draft.text, 'Новый текст');
    await tester.tap(find.byTooltip('Редактор'));
    await tester.pumpAndSettle();
    expect(editor.state.text, 'Мне нравиться читать.');
    await tester.tap(find.byTooltip('Переводчик'));
    await tester.pumpAndSettle();
    expect(translation.state.draft.text, 'Новый текст');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await editor.close();
  });

  testWidgets(
    'Кнопка отмены и смена модели во время перевода отклоняют старый результат',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = makeCubit(FakeChecker(), MemoryStore());
      final service = FakeTranslator()..pending = Completer();
      final translation = TranslationCubit(
        translator: service,
        store: MemoryTranslationStore(),
      );
      await tester.pumpWidget(testApp(editor, translation: translation));
      await tester.tap(find.byTooltip('Переводчик'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('translation-input')),
        'Привет',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate')));
      await tester.pump();
      expect(find.text('Переводим…'), findsOneWidget);
      editor.configure(
        editor.state.settings.copyWith(model: LocalModel.balanced),
      );
      await tester.pumpAndSettle();
      service.pending!.complete('Запоздавший перевод');
      await tester.pumpAndSettle();
      expect(translation.state.draft.output, isEmpty);
      service.pending = Completer();
      await tester.tap(find.byKey(const Key('translate')));
      await tester.pump();
      expect(service.requests.last.settings.model, LocalModel.balanced);
      await tester.tap(find.byKey(const Key('translate')));
      service.pending!.complete('Отменённый перевод');
      await tester.pumpAndSettle();
      expect(translation.state.draft.output, isEmpty);
      expect(translation.state.translating, isFalse);
      await tester.pumpWidget(const SizedBox());
      await editor.close();
    },
  );

  for (final width in [1280.0, 640.0]) {
    testWidgets(
      'Перевод, выбор языка и переходы между разделами при ширине $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final editor = makeCubit(FakeChecker(), MemoryStore());
        final translation = TranslationCubit(
          translator: FakeTranslator(),
          store: MemoryTranslationStore(),
        );
        await tester.pumpWidget(testApp(editor, translation: translation));
        await tester.tap(find.byTooltip('Переводчик'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('source-language')), findsOneWidget);
        expect(find.byKey(const Key('target-language')), findsOneWidget);
        await tester.tap(find.byKey(const Key('target-language')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Немецкий').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('translation-input')),
          'Привет!',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('translate')));
        await tester.pumpAndSettle();
        final output = tester.widget<TextField>(
          find.byKey(const Key('translation-output')),
        );
        expect(output.controller!.text, 'Hello!');
        expect(output.readOnly, isTrue);
        await tester.tap(find.byTooltip('Поменять языки местами'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('translation-input')))
              .controller!
              .text,
          'Hello!',
        );
        await tester.tap(find.byTooltip('Настройки'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Переводчик'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('translation-input')))
              .controller!
              .text,
          'Hello!',
        );
        await tester.tap(find.byTooltip('Редактор'));
        await tester.pumpAndSettle();
        expect(editor.state.text, 'Мне нравиться читать.');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await editor.close();
      },
    );
  }

  testWidgets('Ctrl+Enter переводит текст и не запускает корректуру', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final checker = FakeChecker();
    final editor = makeCubit(checker, MemoryStore());
    final service = FakeTranslator();
    final translation = TranslationCubit(
      translator: service,
      store: MemoryTranslationStore(),
    );
    await tester.pumpWidget(testApp(editor, translation: translation));
    await tester.tap(find.byTooltip('Переводчик'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('translation-input')),
      'Привет',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(1));
    expect(checker.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await editor.close();
  });
}
