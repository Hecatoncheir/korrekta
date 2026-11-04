import 'dart:convert';
import 'dart:io';

import 'package:korrekta/data/checker_repository.dart';
import 'package:korrekta/domain/settings.dart';

Future<void> main() async {
  final checker = LocalChecker(
    await File('assets/proposal.txt').readAsString(),
  );
  final defaults = Settings.defaults(Directory.current.path);
  for (final model in LocalModel.values) {
    final settings = defaults.copyWith(model: model, names: ['Норвета']);
    for (final (text, expected) in [
      ('Мне нравиться читать.', 'Мне нравится читать.'),
      (
        'Норвета пишет в Flutter.\n  `final x = 1;` 🙂',
        'Норвета пишет в Flutter.\n  `final x = 1;` 🙂',
      ),
    ]) {
      final timer = Stopwatch()..start();
      final result = await checker.check(text, settings);
      final output = result.apply(text, result.recommended, settings.names);
      stdout.writeln(
        jsonEncode({
          'model': model.id,
          'seconds': timer.elapsedMilliseconds / 1000,
          'original': text,
          'output': output,
          'expected': expected,
          'complete': result.warning == null,
          'pass': output == expected,
        }),
      );
      if (output != expected || result.warning != null) exitCode = 1;
    }
  }
}
