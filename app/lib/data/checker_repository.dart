import 'dart:isolate';

import 'package:korrekta_model_benchmark/desktop.dart';

import '../domain/check_result.dart';
import '../domain/settings.dart';

abstract interface class TextChecker {
  Future<CheckResult> check(String text, Settings settings);
}

class LocalChecker implements TextChecker {
  const LocalChecker(this.prompt);
  final String prompt;

  @override
  Future<CheckResult> check(String text, Settings settings) async {
    localEndpoint(settings.ollama);
    localEndpoint(settings.languageTool);
    final prompt = this.prompt;
    // Словари и вычисление различий не блокируют поток интерфейса.
    return Isolate.run(() => collectText(text, settings, prompt));
  }
}

Future<CheckResult> collectText(
  String text,
  Settings settings,
  String prompt,
) async {
  final runtime = await DesktopRuntime.open(
    store: settings.store,
    ollama: localEndpoint(settings.ollama).toString(),
    languageTool: localEndpoint(settings.languageTool).toString(),
    model: settings.model.id,
    hunspellExecutable: settings.hunspell,
  );
  try {
    final row = await runtime.collect(text, prompt, names: settings.names);
    final features = await roleFeatures(
      row,
      SharedLexicon(runtime.hunspell, runtime.symspell),
    );
    final decision = chooseRoles({
      ...row,
      'role_features': features,
    }, 'inflections');
    return resultFromRows(row, decision);
  } finally {
    await runtime.close();
  }
}

CheckResult resultFromRows(
  Map<String, dynamic> row,
  Map<String, dynamic> decision,
) {
  final slots = (row['slots'] as List<dynamic>).cast<Map<String, dynamic>>();
  final choices = (decision['choices'] as List<dynamic>).cast<int>();
  return CheckResult(
    row['text'] as String,
    List.generate(slots.length, (i) {
      final sources = (slots[i]['sources'] as List<dynamic>)
          .expand((s) => (s as List<dynamic>).cast<String>())
          .toSet()
          .toList();
      return Suggestion(WordChoices.fromJson(slots[i]), choices[i], sources);
    }),
    warning: row.containsKey('collection_error')
        ? 'GigaChat не вернул пригодный ответ. Показаны предложения словарей и LanguageTool. Повторите проверку.'
        : null,
  );
}
