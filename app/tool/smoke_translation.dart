import 'dart:convert';
import 'dart:io';

import 'package:korrekta/data/local_translator.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/translation.dart';

Future<void> main() async {
  final translator = LocalTranslator();
  for (final model in [LocalModel.balanced, LocalModel.quality]) {
    for (final draft in [
      const TranslationDraft(
        text: 'Привет! Это локальный перевод.\n\nВерсия Flutter 3.47.9.',
      ),
      const TranslationDraft(
        text: 'Hello! This is a local translation.\n\nFlutter version 3.47.9.',
        from: TranslationLanguage.english,
        to: TranslationLanguage.russian,
      ),
    ]) {
      final clock = Stopwatch()..start();
      final output = await translator.translate(draft, Settings(model: model));
      final translated = output != draft.text;
      final preservesVersion = output.contains('3.47.9');
      final preservesParagraphs = output.contains('\n\n');
      stdout.writeln(
        jsonEncode({
          'model': model.shortName,
          'direction': '${draft.from.code}-${draft.to.code}',
          'seconds': clock.elapsedMilliseconds / 1000,
          'output': output,
          'translated': translated,
          'preserves_version': preservesVersion,
          'preserves_paragraphs': preservesParagraphs,
        }),
      );
      if (!translated || !preservesVersion || !preservesParagraphs) {
        exitCode = 1;
      }
    }
  }
  translator.cancel();
}
