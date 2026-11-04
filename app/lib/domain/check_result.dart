import 'package:korrekta_model_benchmark/ensemble.dart';
import 'package:korrekta_model_benchmark/text_guard.dart';

class Suggestion {
  const Suggestion(this.slot, this.recommended, this.sources);
  final WordChoices slot;
  final int recommended;
  final List<String> sources;
}

class CheckResult {
  CheckResult(this.original, Iterable<Suggestion> suggestions, {this.warning})
    : suggestions = List.unmodifiable(suggestions);
  final String original;
  final List<Suggestion> suggestions;
  final String? warning;

  String apply(String current, Map<int, int> choices, List<String> names) {
    final selected = selectEnsembleChoices(
      original,
      suggestions.map((s) => s.slot).toList(),
      List.generate(suggestions.length, (i) => choices[i] ?? 0),
    ).applyTo(current);
    final guarded = guardText(current, selected, names: names);
    if (guarded.failure != null || guarded.rejected.isNotEmpty) {
      throw StateError('Эта замена затрагивает имя или оформление');
    }
    return guarded.output;
  }

  Map<int, int> get recommended => {
    for (var i = 0; i < suggestions.length; i++)
      if (suggestions[i].recommended > 0) i: suggestions[i].recommended,
  };
}
