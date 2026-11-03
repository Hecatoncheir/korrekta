import 'scoring.dart';

// Общая оценка итогового текста для JSON-правок и моделей seq2seq.
JsonMap scoreText(String text, List<dynamic> expected, String output) {
  final gold = locateEdits(text, expected);
  if (gold.rejected.isNotEmpty) {
    throw FormatException('Ошибка эталона: ${gold.rejected}');
  }
  final target = applyEdits(text, gold.edits);
  final actualEffects = diffKeys(text, output);
  final goldEffects = diffKeys(text, target);
  final matchedCorrections = gold.edits.where((edit) {
    return diffKeys(
      text,
      applyEdits(text, [edit]),
    ).difference(actualEffects).isEmpty;
  }).length;
  return {
    'atomic_tp': actualEffects.intersection(goldEffects).length,
    'atomic_fp': actualEffects.difference(goldEffects).length,
    'atomic_fn': goldEffects.difference(actualEffects).length,
    'matched_corrections': matchedCorrections,
    'gold_corrections': gold.edits.length,
    'control': expected.isEmpty,
    'changed_control': expected.isEmpty && text != output,
    'exact': target == output,
  };
}
