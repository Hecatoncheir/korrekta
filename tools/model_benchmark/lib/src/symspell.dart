import 'dart:math';

String dictionaryKey(String word) => word.toLowerCase().replaceAll('ё', 'е');

int spellingDistance(String left, String right) {
  final a = left.runes.toList(), b = right.runes.toList();
  final rows = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      rows[i][j] = min(
        min(rows[i - 1][j] + 1, rows[i][j - 1] + 1),
        rows[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1);
      }
    }
  }
  return rows.last.last;
}

Set<String> _deletes(String word, int distance) {
  final prefix = word.substring(0, min(7, word.length));
  final result = <String>{prefix};
  var frontier = <String>{prefix};
  for (var level = 0; level < distance; level++) {
    final next = <String>{};
    for (final item in frontier) {
      for (var i = 0; i < item.length; i++) {
        final shorter = item.replaceRange(i, i + 1, '');
        if (result.add(shorter)) next.add(shorter);
      }
    }
    frontier = next;
  }
  return result;
}

/// Симметричные удаления префикса, затем точная проверка OSA-расстояния.
class SymSpellIndex {
  SymSpellIndex(this.frequencies) {
    for (final word in frequencies.keys) {
      if (word.length < 3 || word.length > 32) continue;
      for (final deletion in _deletes(dictionaryKey(word), 2)) {
        _index.putIfAbsent(deletion, () => []).add(word);
      }
    }
  }
  final Map<String, int> frequencies;
  final _index = <String, List<String>>{};

  List<String> lookup(String word, {int distance = 2}) {
    if (word.length < 3 || word.length > 32) return const [];
    final key = dictionaryKey(word);
    final candidates = <String>{};
    for (final deletion in _deletes(key, distance)) {
      candidates.addAll(_index[deletion] ?? const []);
    }
    final scored = <String, int>{};
    for (final candidate in candidates) {
      if ((candidate.length - word.length).abs() > distance) continue;
      final value = spellingDistance(key, dictionaryKey(candidate));
      if (value <= distance) scored[candidate] = value;
    }
    return scored.keys.toList()..sort((a, b) {
      final byDistance = scored[a]!.compareTo(scored[b]!);
      if (byDistance != 0) return byDistance;
      final byFrequency = frequencies[b]!.compareTo(frequencies[a]!);
      return byFrequency != 0 ? byFrequency : a.compareTo(b);
    });
  }
}
