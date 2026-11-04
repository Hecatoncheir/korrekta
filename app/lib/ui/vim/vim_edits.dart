import 'vim_motions.dart';

typedef PastePlacement = ({int start, String insert, int cursor});

String lineBreak(String text) => text.contains('\r\n') ? '\r\n' : '\n';

PastePlacement pastePlacement(
  String text,
  int cursor,
  String value, {
  required bool before,
  required bool linewise,
  required int count,
}) {
  if (linewise) return linePaste(text, cursor, value * count, before);
  final start = before ? cursor : nextCharacter(text, cursor);
  final insert = value * count;
  final changed = text.replaceRange(start, start, insert);
  return (
    start: start,
    insert: insert,
    cursor: previousCharacter(changed, start + insert.length),
  );
}

PastePlacement linePaste(String text, int cursor, String value, bool before) {
  final line = lineAt(text, cursor);
  final start = before ? line.start : line.next;
  var insert = value;
  var target = start;
  if (!before && start == text.length && line.end == text.length) {
    final newline = lineBreak(text);
    insert = '$newline$insert';
    target += newline.length;
  }
  if (start < text.length && !insert.endsWith('\n')) {
    insert = '$insert${lineBreak(text)}';
  }
  return (start: start, insert: insert, cursor: target);
}
