import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/check_result.dart';
import 'package:korrekta/ui/marked_text_controller.dart';
import 'package:korrekta/ui/theme.dart';
import 'package:korrekta_model_benchmark/ensemble.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;
import 'support/test_app.dart';

List<TextSpan> markedSpans(TextSpan span) => span.children!
    .whereType<TextSpan>()
    .where((child) => child.style?.backgroundColor != null)
    .toList();

void main() {
  testWidgets(
    'Ошибка, принятая правка и отмена обновляют подсветку без изменения текста',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = makeCubit(FakeChecker(), MemoryStore());
      await tester.pumpWidget(testApp(editor));
      final field = find.byKey(const Key('editor'));
      TextSpan span() => tester
          .widget<TextField>(field)
          .controller!
          .buildTextSpan(context: tester.element(field), withComposing: true);

      await tester.tap(find.byKey(const Key('check')));
      await tester.pumpAndSettle();
      expect(markedSpans(span()).single.text, 'нравиться');
      expect(span().toPlainText(), editor.state.text);
      final errorColor = markedSpans(span()).single.style!.decorationColor;
      await tester.tap(find.text('Принять рекомендованные'));
      await tester.pumpAndSettle();
      expect(markedSpans(span()).single.text, 'нравится');
      expect(
        markedSpans(span()).single.style!.decorationColor,
        isNot(errorColor),
      );
      expect(span().toPlainText(), 'Мне нравится читать.');
      await tester.tap(find.byTooltip('Отменить замену'));
      await tester.pumpAndSettle();
      expect(markedSpans(span()), isEmpty);
      expect(span().toPlainText(), 'Мне нравиться читать.');
      await tester.pumpWidget(const SizedBox());
      await editor.close();
    },
  );

  test('Места вставки знака видны и не разрывают эмодзи', () {
    const text = '🙂 текст';
    final result = CheckResult(text, [
      Suggestion(WordChoices(2, '', ['', ',']), 1, ['languagetool']),
    ]);
    final mark = marksFor(text, result, null).single;
    expect(mark.range.textInside(text), '🙂');
    expect(mark.kind, EditorMarkKind.error);
    final optional = CheckResult(text, [
      Suggestion(WordChoices(3, 'текст', ['текст', 'текста']), 0, ['hunspell']),
    ]);
    expect(
      marksFor(text, optional, null).single.kind,
      EditorMarkKind.suggestion,
    );
  });

  test(
    'Принятые правки отмечают слова с учётом UTF-16 и снимаются при вводе',
    () {
      final controller = MarkedTextController()
        ..text = '🙂 Всё хорошо. Всё верно.';
      controller.review(null, previous: '🙂 Все хорошо. Все верно.');
      final marks = marksFor(
        controller.text,
        null,
        '🙂 Все хорошо. Все верно.',
      );
      expect(marks.map((mark) => mark.range.textInside(controller.text)), [
        'Всё',
        'Всё',
      ]);
      controller.text = '🙂 Новый текст';
      controller.review(null);
      expect(marksFor(controller.text, null, null), isEmpty);
      controller.dispose();
    },
  );

  test('Текст поверх каждой подсветки читаем в светлой и тёмной темах', () {
    for (final dark in [false, true]) {
      final theme = gruvbox(dark);
      for (final kind in EditorMarkKind.values) {
        final style = markStyle(theme, kind);
        final background = Color.alphaBlend(
          style.backgroundColor!,
          theme.colorScheme.surface,
        ).computeLuminance();
        final ink = style.color!.computeLuminance();
        final contrast = ink > background
            ? (ink + .05) / (background + .05)
            : (background + .05) / (ink + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: '$dark $kind');
      }
    }
  });
}
