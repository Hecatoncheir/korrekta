import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/checker_repository.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'support/test_app.dart';

void main() {
  for (final width in [1280.0, 640.0]) {
    testWidgets('Неполная проверка без карточек при ширине $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final checker = FakeChecker();
      final cubit = makeCubit(checker, MemoryStore())..edit('Всё готово.');
      checker.pending = Completer()
        ..complete(
          resultFromRows(
            {
              'text': 'Всё готово.',
              'slots': <dynamic>[],
              'collection_error': 'Непригодный текст',
            },
            {'choices': <int>[]},
          ),
        );
      await tester.pumpWidget(testApp(cubit));
      await tester.tap(find.byKey(const Key('check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partial-check-warning')), findsOneWidget);
      expect(find.text('Проверка неполная'), findsOneWidget);
      expect(find.text('Проверка завершена'), findsNothing);
      expect(cubit.state.text, 'Всё готово.');
      expect(tester.takeException(), isNull);
      cubit.edit('Другой текст.');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partial-check-warning')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await cubit.close();
    });
  }
}
