import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/translation.dart';
import 'package:korrekta/ui/translation_cubit.dart';
import 'package:korrekta/ui/components_cubit.dart';

import '../test/editor_cubit_test.dart'
    show FakeChecker, MemoryStore, makeCubit;
import '../test/support/test_app.dart';
import '../test/support/translation_fakes.dart';

void main() {
  testWidgets('Снимок интерфейса без управления открытым приложением', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      for (final (family, asset) in [
        ('Nunito', 'assets/fonts/font-5.ttf'),
        ('Nunito Sans', 'assets/fonts/font-7.ttf'),
        ('JetBrains Mono', 'assets/fonts/font-0.ttf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
      }
    });
    final editor = makeCubit(FakeChecker(), MemoryStore());
    editor.configure(
      editor.state.settings.copyWith(model: LocalModel.balanced, vimMode: true),
    );
    final boundaryKey = GlobalKey();
    final translation = TranslationCubit(
      translator: FakeTranslator(),
      store: MemoryTranslationStore(),
      draft: const TranslationDraft(
        text: 'Привет! Это локальный перевод.\n\nВерсия Flutter 3.47.9.',
        output:
            'Hello! This is a local translation.\n\nFlutter version 3.47.9.',
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: testApp(editor, translation: translation),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/mark.png'),
        boundaryKey.currentContext!,
      ),
    );
    await editor.check();
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'editor-vim');
    editor.configure(editor.state.settings.copyWith(dark: false));
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'editor-errors-light');
    editor.accept(editor.state.result!.recommended);
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'editor-corrections-light');
    editor.configure(editor.state.settings.copyWith(dark: true));
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'editor-corrections-dark');
    editor.edit('');
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'editor-empty');
    await tester.tap(find.byTooltip('Переводчик'));
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'translation-dark');
    editor.configure(editor.state.settings.copyWith(dark: false));
    await editor.flush();
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'translation-light');
    await tester.binding.setSurfaceSize(const Size(640, 800));
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'translation-narrow');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    editor.configure(editor.state.settings.copyWith(dark: true));
    await editor.flush();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    final components = tester
        .element(find.text('Всё на вашем компьютере'))
        .read<ComponentsCubit>();
    // Фиксированное состояние только для снимка интерфейса.
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    components.emit(
      const ComponentsState(
        status: (ollama: true, model: true, languageTool: true),
        busy: false,
        progress: null,
        message: null,
        ready: true,
      ),
    );
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'settings-buttons');
    await tester.binding.setSurfaceSize(const Size(900, 800));
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'settings-compact');
    await tester.binding.setSurfaceSize(const Size(640, 800));
    await tester.pumpAndSettle();
    await savePreview(tester, boundaryKey, 'settings-narrow');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await editor.close();
  });
}

Future<void> savePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('../work/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List());
    image.dispose();
  });
}
