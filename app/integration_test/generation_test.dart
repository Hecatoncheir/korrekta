import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/generation_store.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/editor_page.dart';

import 'app_quality_test.dart' show QualityBinding;
import 'support/quality_fixture.dart';
import 'support/quality_steps.dart';

void main() {
  QualityBinding();
  testWidgets('Генерация через интерфейс с настоящими 10В и 20В', (
    tester,
  ) async {
    const root = String.fromEnvironment('QUALITY_ROOT');
    const study = String.fromEnvironment(
      'GENERATION_STUDY',
      defaultValue: 'template-fix',
    );
    if (root.isEmpty) throw StateError('Укажите QUALITY_ROOT');
    final output = Directory('$root/work/generation-proof/$study');
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
      for (final model in [LocalModel.balanced, LocalModel.quality]) {
        await qualitySettings(tester, fixture, model, []);
        await tester.tap(find.byTooltip('Генерация'));
        await tester.pumpAndSettle();
        const prompt =
            'Напиши короткое приглашение на прогулку в парк для друга. '
            'Два предложения на русском, без вступления.';
        await tester.enterText(
          find.byKey(const Key('generation-input')),
          prompt,
        );
        await tester.pumpAndSettle();
        fixture.proxy.currentCase = 'generation-${model.name}';
        await tester.tap(find.byKey(const Key('generate')));
        await tester.pump();
        await waitQuality(
          tester,
          () => !fixture.generation.state.generating,
          'Генерация',
        );
        final state = fixture.generation.state;
        expect(state.message, isNull);
        expect(state.draft.output.trim(), isNotEmpty);
        expect(state.draft.limited, isFalse);
        expect(state.draft.output, isNot(contains('availableassistant')));
        expect(state.draft.output, isNot(contains('<|role_sep|>')));
        final wire = fixture.proxy.observations.lastWhere(
          (row) => row['case'] == 'generation-${model.name}',
        );
        expect(wire['model'], model.id);
        expect(
          wire['api'],
          model == LocalModel.quality ? '/api/generate' : '/api/chat',
        );
        expect(wire['injected'], isFalse);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('generation-output')))
              .controller!
              .text,
          state.draft.output,
        );
        await fixture.generation.flush();
        final file = File('${output.path}/restored-${model.name}.json');
        final store = FileGenerationStore(file);
        await store.save(state.draft);
        expect((await store.load()).toJson(), state.draft.toJson());
        await saveQualityScreenshot(
          tester,
          boundary,
          output,
          'generation-${model.name}',
        );
        stdout.writeln(
          jsonEncode({
            'model': model.name,
            'text': state.draft.output,
            'requestModel': wire['model'],
            'restored': true,
          }),
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await fixture.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
