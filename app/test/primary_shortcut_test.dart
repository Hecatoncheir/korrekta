import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/ui/generation_cubit.dart';
import 'package:korrekta/ui/translation_cubit.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'support/generation_fakes.dart';
import 'support/test_app.dart';
import 'support/translation_fakes.dart';

const source = 'Мне нравиться читать.';

class ShortcutFixture {
  final checker = FakeChecker();
  final generator = FakeGenerator();
  final translator = FakeTranslator();
  late final editor = makeCubit(checker, MemoryStore());
  late final generation = GenerationCubit(
    generator: generator,
    store: MemoryGenerationStore(),
  );
  late final translation = TranslationCubit(
    translator: translator,
    store: MemoryTranslationStore(),
  );

  Widget get app =>
      testApp(editor, generation: generation, translation: translation);
  List<int> get requests => [
    checker.requests.length,
    generator.requests.length,
    translator.requests.length,
  ];

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await editor.close();
  }
}

void main() {
  for (final (index, section, field) in [
    (0, 'Редактор', 'editor'),
    (1, 'Генерация', 'generation-input'),
    (2, 'Переводчик', 'translation-input'),
  ]) {
    testWidgets(
      'Enter в Vim Normal: $section, режимы, модификаторы и удержание',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = ShortcutFixture();
        await tester.pumpWidget(fixture.app);
        await tester.tap(find.byTooltip(section));
        await tester.pumpAndSettle();
        final input = find.byKey(Key(field));
        await tester.enterText(input, source);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(fixture.requests, [0, 0, 0]);
        await tester.enterText(input, source);
        await tester.tap(find.byKey(const Key('vim-toggle')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(fixture.requests, [0, 0, 0]);
        await tester.enterText(input, source);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(fixture.requests, [0, 0, 0]);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(fixture.requests, [0, 0, 0]);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(fixture.requests, [
          for (var i = 0; i < 3; i++) i == index ? 1 : 0,
        ]);
        // В Windows-таблице тестового симулятора нет отдельного Numpad Enter.
        await tester.sendKeyEvent(
          LogicalKeyboardKey.numpadEnter,
          physicalKey: PhysicalKeyboardKey.numpadEnter,
          platform: 'macos',
        );
        await tester.pumpAndSettle();
        expect(fixture.requests, [
          for (var i = 0; i < 3; i++) i == index ? 2 : 0,
        ]);
        expect(tester.widget<TextField>(input).controller!.text, source);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        expect(fixture.requests, [
          for (var i = 0; i < 3; i++) i == index ? 3 : 0,
        ]);

        for (final modifier in [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.metaLeft,
        ]) {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
        }
        expect(fixture.requests, [
          for (var i = 0; i < 3; i++) i == index ? 5 : 0,
        ]);
        expect(tester.takeException(), isNull);
        await fixture.dispose(tester);
      },
    );
  }

  testWidgets('Enter не запускает другую операцию во время генерации', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ShortcutFixture();
    fixture.generator.pending = Completer();
    await tester.pumpWidget(fixture.app);
    await tester.tap(find.byTooltip('Генерация'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('generation-input')), source);
    await tester.tap(find.byKey(const Key('vim-toggle')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.generation.state.generating, isTrue);
    await tester.tap(find.byTooltip('Редактор'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('editor')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.requests, [0, 1, 0]);
    fixture.translation.edit(source);
    await tester.tap(find.byTooltip('Переводчик'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('translation-input')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.requests, [0, 1, 0]);
    fixture.generator.pending!.complete((text: 'Готово', limited: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Редактор'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.requests, [1, 1, 0]);
    await fixture.dispose(tester);
  });
}
