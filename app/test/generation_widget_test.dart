import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/ui/generation_cubit.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'support/generation_fakes.dart';
import 'support/test_app.dart';
import 'support/vim_keys.dart';

void main() {
  for (final width in [1280.0, 640.0]) {
    testWidgets(
      'Генерация: два поля, копирование и переходы при ширине $width',
      (tester) async {
        mockVimClipboard();
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final editor = makeCubit(FakeChecker(), MemoryStore());
        final service = FakeGenerator();
        final generation = GenerationCubit(
          generator: service,
          store: MemoryGenerationStore(),
        );
        await tester.pumpWidget(testApp(editor, generation: generation));
        expect(
          tester.getCenter(find.byTooltip('Генерация')).dy,
          lessThan(tester.getCenter(find.byTooltip('Переводчик')).dy),
        );
        await tester.tap(find.byTooltip('Генерация'));
        await tester.pumpAndSettle();
        expect(find.text('Запрос'), findsOneWidget);
        expect(find.text('Результат'), findsOneWidget);
        if (width >= 720) {
          final prompt = tester.getRect(
            find.byKey(const Key('generation-input')),
          );
          final toggle = tester.getRect(find.byKey(const Key('vim-toggle')));
          expect(toggle.right, lessThanOrEqualTo(prompt.right + 24));
          expect(toggle.left, greaterThan(prompt.center.dx));
        }
        await tester.enterText(
          find.byKey(const Key('generation-input')),
          'Сочини рассказ',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(service.requests.single.prompt, 'Сочини рассказ');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('generation-output')))
              .controller!
              .text,
          'Готовый текст.',
        );
        await tester.tap(find.byTooltip('Скопировать результат'));
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))!.text,
          'Готовый текст.',
        );
        await tester.tap(find.byTooltip('Переводчик'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Генерация'));
        await tester.pumpAndSettle();
        expect(generation.state.draft.prompt, 'Сочини рассказ');
        expect(editor.state.text, 'Мне нравиться читать.');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await editor.close();
      },
    );
  }

  testWidgets(
    'Генерация отменяется, Vim работает, проверка не запускается параллельно',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = makeCubit(FakeChecker(), MemoryStore());
      final service = FakeGenerator()..pending = Completer();
      final generation = GenerationCubit(
        generator: service,
        store: MemoryGenerationStore(),
      );
      await tester.pumpWidget(testApp(editor, generation: generation));
      await tester.tap(find.byTooltip('Генерация'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('generation-input')),
        'Запрос',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vim-toggle')));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find.byKey(const Key('generation-input')),
      );
      expect(input.focusNode!.hasFocus, isTrue);
      input.controller!.selection = const TextSelection.collapsed(offset: 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('generation-input')))
            .readOnly,
        isTrue,
      );
      await russianKey(tester, PhysicalKeyboardKey.keyS, 'ы');
      await tester.pumpAndSettle();
      expect(generation.state.draft.prompt, 'апрос');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('generation-output')))
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('generation-input')))
            .readOnly,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('generate')));
      await tester.pump();
      expect(generation.state.generating, isTrue);
      await tester.tap(find.byTooltip('Редактор'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('check'))).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Переводчик'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('translation-input')),
        'Привет',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('translate')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Генерация'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('generate')));
      service.pending!.complete((text: 'Запоздавший ответ', limited: false));
      await tester.pumpAndSettle();
      expect(generation.state.draft.output, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await editor.close();
    },
  );
}
