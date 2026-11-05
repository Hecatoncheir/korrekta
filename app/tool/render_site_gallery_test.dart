import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/generation.dart';
import 'package:korrekta/ui/generation_cubit.dart';

import '../test/editor_cubit_test.dart'
    show FakeChecker, MemoryStore, makeCubit;
import '../test/support/generation_fakes.dart';
import '../test/support/test_app.dart';
import 'render_preview_test.dart' show savePreview;

void main() {
  testWidgets('Снимок генерации для галереи сайта', (tester) async {
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
    editor.configure(editor.state.settings.copyWith(vimMode: true));
    final generation = GenerationCubit(
      generator: FakeGenerator(),
      store: MemoryGenerationStore(),
      draft: const GenerationDraft(
        prompt: 'Напиши короткое приглашение на прогулку в парк для друга. Два предложения на русском, без вступления.',
        output: 'Пойдём завтра прогуляемся в парк! Будет весело!',
      ),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: testApp(editor, generation: generation),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/mark.png'),
        boundary.currentContext!,
      ),
    );
    await tester.tap(find.byTooltip('Генерация'));
    await tester.pumpAndSettle();
    await savePreview(tester, boundary, 'generation-site');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await editor.close();
  });
}
