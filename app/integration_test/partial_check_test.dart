import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/editor_page.dart';

import 'app_quality_test.dart' show QualityBinding;
import 'support/quality_data.dart';
import 'support/quality_fixture.dart';
import 'support/quality_steps.dart';

void main() {
  QualityBinding();
  testWidgets('Непригодный ответ: предупреждение, словари, повтор', (
    tester,
  ) async {
    const root = String.fromEnvironment('QUALITY_ROOT');
    final output = Directory('$root/work/partial-check-proof');
    final fixture = QualityFixture(
      root,
      output,
      'E:/korrekta/app-quality-runtime',
    );
    await fixture.prepare();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: fixture.app));
    fixture.bind(tester.element(find.byType(EditorPage)));
    try {
      await qualitySettings(tester, fixture, LocalModel.balanced, []);
      for (final text in ['Я проверел документ.', 'Все службы работают.']) {
        fixture.proxy.forcedContent = '{"text":"{"}';
        final item = QualityCase({
          'id': 'injected-${text.length}',
          'text': text,
          'profile': 'empty',
          'kind': 'error',
          'expected': [text],
          'names': <String>[],
          'protected': <String>[],
        });
        final result = await qualityCase(
          tester,
          fixture,
          item,
          LocalModel.balanced,
        );
        expect(result['complete'], isFalse);
        expect(fixture.editor.state.text, text);
        // qualityCase проверяет также применение и отмену. После отмены
        // баннер исчезает, поэтому отдельно проверяем состояние до принятия.
        fixture.proxy.forcedContent = '{"text":"{"}';
        fixture.proxy.currentCase = 'warning-${text.length}';
        await tester.tap(find.byKey(const Key('check')));
        await waitQuality(
          tester,
          () => !fixture.editor.state.checking,
          'Предупреждение',
        );
        expect(find.byKey(const Key('partial-check-warning')), findsOneWidget);
        expect(find.text('Проверка неполная'), findsOneWidget);
        expect(find.text('Проверка завершена'), findsNothing);
        expect(fixture.editor.state.result!.warning, isNotNull);
        expect(fixture.editor.state.text, text);
        if (text.startsWith('Я')) {
          final cards = await inspectCards(
            tester,
            fixture.editor.state.result!.suggestions.length,
          );
          expect(
            cards.any((card) => (card['options'] as List).contains('проверил')),
            isTrue,
          );
        }
        await saveQualityScreenshot(
          tester,
          boundary,
          output,
          'partial-${text.length}',
        );
        fixture.proxy.currentCase = 'retry-${text.length}';
        await tester.tap(find.byKey(const Key('check')));
        await waitQuality(
          tester,
          () => !fixture.editor.state.checking,
          'Повтор',
        );
        expect(fixture.editor.state.result!.warning, isNull);
        expect(find.byKey(const Key('partial-check-warning')), findsNothing);
      }
    } finally {
      await fixture.close();
      await tester.pumpWidget(const SizedBox());
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
