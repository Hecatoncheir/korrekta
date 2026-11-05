import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/editor_page.dart';
import 'package:path/path.dart' as p;

import 'support/quality_data.dart';
import 'support/quality_fixture.dart';
import 'support/quality_steps.dart';

void main() {
  final binding = QualityBinding();
  testWidgets(
    'Новый набор через настоящий интерфейс и локальные движки',
    (tester) => runQualitySuite(tester, binding),
    timeout: const Timeout(Duration(hours: 2)),
  );
}

Future<void> runQualitySuite(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  const root = String.fromEnvironment('QUALITY_ROOT');
  const runtimeRoot = String.fromEnvironment('QUALITY_RUNTIME');
  const pilot = bool.fromEnvironment('QUALITY_PILOT');
  const inspect = bool.fromEnvironment('QUALITY_INSPECT');
  const study = String.fromEnvironment(
    'QUALITY_STUDY',
    defaultValue: 'app-quality',
  );
  if (root.isEmpty) {
    throw StateError('Укажите QUALITY_ROOT — абсолютный путь к репозиторию');
  }
  if (!pilot) await verifyQualityFreeze(root, study: study);
  final output = Directory(
    pilot
        ? p.join(
            root,
            'work',
            'app-quality-pilot',
            '${DateTime.now().millisecondsSinceEpoch}',
          )
        : p.join(root, 'benchmarks', 'results', '2026-11-05', study),
  );
  final fixture = QualityFixture(
    root,
    output,
    runtimeRoot.isEmpty
        ? p.join(root, 'work', 'app-quality-runtime')
        : runtimeRoot,
  );
  await fixture.prepare();
  final boundary = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: boundary, child: fixture.app));
  fixture.bind(tester.element(find.byType(EditorPage)));
  await waitQuality(
    tester,
    () => fixture.components.state.ready || !fixture.components.state.busy,
    'Начальная подготовка',
  );
  expect(
    fixture.components.state.ready,
    isTrue,
    reason: fixture.components.state.message,
  );
  if (inspect) await Future<void>.delayed(const Duration(seconds: 45));
  final cases = await readCases(root, pilot);
  try {
    for (final model in LocalModel.values) {
      await runQualityModel(tester, fixture, cases, model, boundary);
    }
    if (!pilot) await verifyQualityFreeze(root, study: study);
    binding.reportData = {
      'output': output.path,
      'casesPerModel': cases.length,
      'pilot': pilot,
    };
  } finally {
    await fixture.close();
    await tester.pumpWidget(const SizedBox());
  }
}

class QualityBinding extends IntegrationTestWidgetsFlutterBinding {
  // Ввод для пакетного сценария идёт через тестовый канал Flutter, без ОС IME.
  @override
  bool get registerTestTextInput => true;
}

Future<void> runQualityModel(
  WidgetTester tester,
  QualityFixture fixture,
  List<QualityCase> cases,
  LocalModel model,
  GlobalKey boundary,
) async {
  final log = QualityLog(
    File(p.join(fixture.output.path, '${model.name}.jsonl')),
  );
  final completed = await log.completed();
  String? profile;
  var screenshots = 0;
  for (final item in cases.where((item) => !completed.contains(item.id))) {
    if (profile != item.profile) {
      await qualitySettings(tester, fixture, model, item.names);
      profile = item.profile;
    }
    final row = await qualityCase(tester, fixture, item, model);
    await log.append(row);
    final result = row['score']! as Map<String, Object>;
    stdout.writeln(
      jsonEncode({
        'model': model.name,
        'id': item.id,
        'clean': result['clean'],
        'complete': row['complete'],
        'ms': row['elapsedMs'],
      }),
    );
    if (screenshots < 2 && result['clean'] != true) {
      await saveQualityScreenshot(
        tester,
        boundary,
        fixture.output,
        '${model.name}-${item.id}',
      );
      screenshots++;
    }
  }
}
