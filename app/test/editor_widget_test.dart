import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;

void main() {
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
