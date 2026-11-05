import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/editor_binding.dart';
import 'package:korrekta/ui/suggestions_panel.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import 'quality_data.dart';
import 'quality_fixture.dart';

Future<void> waitQuality(
  WidgetTester tester,
  bool Function() ready,
  String label,
) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(minutes: 5)) {
      throw TimeoutException(label);
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

Future<void> qualitySettings(
  WidgetTester tester,
  QualityFixture fixture,
  LocalModel model,
  List<String> names,
) async {
  fixture.proxy.currentCase = null;
  await tester.tap(find.byTooltip('Настройки'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(model.label));
  final personal = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Норвета\nКорректа',
  );
  await tester.ensureVisible(personal);
  await tester.enterText(personal, names.join('\n'));
  await tester.tap(find.text('Сохранить'));
  await tester.pump();
  await waitQuality(
    tester,
    () => fixture.components.state.ready || !fixture.components.state.busy,
    'Подготовка выбранной модели',
  );
  expect(
    fixture.components.state.ready,
    isTrue,
    reason: fixture.components.state.message,
  );
  expect(fixture.editor.state.settings.model, model);
  expect(fixture.editor.state.settings.names, names);
  await tester.tap(find.byTooltip('Редактор'));
  await tester.pumpAndSettle();
}

Future<Map<String, Object?>> qualityCase(
  WidgetTester tester,
  QualityFixture fixture,
  QualityCase item,
  LocalModel model,
) async {
  final field = find.byKey(const Key('editor'));
  fixture.proxy.currentCase = item.id;
  final wireStart = fixture.proxy.observations.length;
  await tester.enterText(field, item.text);
  await tester.pumpAndSettle();
  expect(fixture.editor.state.text, item.text);
  final timer = Stopwatch()..start();
  await tester.tap(find.byKey(const Key('check')));
  await tester.pump();
  await waitQuality(
    tester,
    () => !fixture.editor.state.checking,
    'Проверка ${item.id}',
  );
  final elapsed = timer.elapsedMilliseconds;
  final state = fixture.editor.state;
  final result = state.result;
  expect(state.text, item.text, reason: 'Проверка не должна менять исходник');
  final cards = await inspectCards(tester, result?.suggestions.length ?? 0);
  final recommended = result?.recommended ?? <int, int>{};
  if (recommended.isNotEmpty) {
    await tester.tap(find.text('Принять рекомендованные'));
    await tester.pump();
  }
  final output = fixture.editor.state.text;
  final controller = tester.element(field).read<EditorBinding>().controller;
  expect(controller.text, output);
  final wire = fixture.proxy.observations
      .skip(wireStart)
      .where((row) => row['case'] == item.id)
      .toList();
  final modelMatches =
      wire.isNotEmpty && wire.every((row) => row['model'] == model.id);
  expect(
    modelMatches,
    isTrue,
    reason: 'Выбранная модель должна дойти до реального HTTP-запроса',
  );
  final complete = result != null && result.warning == null;
  final row = <String, Object?>{
    ...item.json,
    'model': model.id,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'output': output,
    'complete': complete,
    'message': state.message,
    'elapsedMs': elapsed,
    'wireModelVerified': modelMatches,
    'cards': cards,
    'recommendedCount': recommended.length,
    'score': score(item, output, complete),
  };
  if (recommended.isNotEmpty) {
    await tester.tap(find.byTooltip('Отменить замену'));
    await tester.pumpAndSettle();
    expect(fixture.editor.state.text, item.text);
    expect(controller.text, item.text);
  }
  return row;
}

Future<List<Map<String, Object?>>> inspectCards(
  WidgetTester tester,
  int count,
) async {
  final rows = <Map<String, Object?>>[];
  for (var index = 0; index < count; index++) {
    final card = find.byWidgetPredicate(
      (widget) => widget is SuggestionCard && widget.index == index,
    );
    final scrollable = find
        .descendant(
          of: find.byType(SuggestionsPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      card,
      180,
      scrollable: scrollable,
      maxScrolls: 80,
    );
    final widget = tester.widget<SuggestionCard>(card);
    rows.add({
      ...widget.suggestion.slot.toJson(),
      'recommended': widget.suggestion.recommended,
      'sources': widget.suggestion.sources,
    });
  }
  return rows;
}

Future<void> saveQualityScreenshot(
  WidgetTester tester,
  GlobalKey key,
  Directory output,
  String name,
) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(p.join(output.path, '$name.png'))
      .writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}
