class Edit {
  const Edit(this.start, this.original, this.replacement);
  final int start;
  final String original;
  final String replacement;
  int get end => start + original.length;
}

String applyEdits(String text, List<Edit> edits) {
  var result = text;
  for (final edit in edits.reversed) {
    if (text.substring(edit.start, edit.end) != edit.original) {
      throw StateError('Исходный текст изменился');
    }
    result = result.replaceRange(edit.start, edit.end, edit.replacement);
  }
  return result;
}

List<Edit> diffEdits(String before, String after) {
  final left = before.runes.toList(), right = after.runes.toList();
  final lengths = List.generate(
    left.length + 1,
    (_) => List<int>.filled(right.length + 1, 0),
  );
  for (var i = left.length - 1; i >= 0; i--) {
    for (var j = right.length - 1; j >= 0; j--) {
      lengths[i][j] = left[i] == right[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] > lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  var i = 0, j = 0, offset = 0;
  int? start;
  var insertion = <int>[];
  final edits = <Edit>[];
  void flush() {
    if (start == null) return;
    edits.add(
      Edit(
        start!,
        before.substring(start!, offset),
        String.fromCharCodes(insertion),
      ),
    );
    start = null;
    insertion = [];
  }

  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] == right[j]) {
      flush();
      offset += left[i] > 0xffff ? 2 : 1;
      i++;
      j++;
    } else if (j < right.length &&
        (i == left.length || lengths[i][j + 1] >= lengths[i + 1][j])) {
      start ??= offset;
      insertion.add(right[j++]);
    } else {
      start ??= offset;
      offset += left[i] > 0xffff ? 2 : 1;
      i++;
    }
  }
  flush();
  return edits;
}
