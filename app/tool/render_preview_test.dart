import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/settings.dart';

import '../test/editor_cubit_test.dart'
    show FakeChecker, MemoryStore, makeCubit;
import '../test/support/test_app.dart';

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
    await tester.pumpWidget(
      RepaintBoundary(key: boundaryKey, child: testApp(editor)),
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
