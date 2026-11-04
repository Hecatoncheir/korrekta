import 'package:characters/characters.dart';

typedef LineBounds = ({int start, int end, int next});

List<int> characterOffsets(String text) {
  var offset = 0;
  return [
    0,
    for (final character in text.characters) offset += character.length,
  ];
}

int nextCharacter(String text, int offset) =>
    characterOffsets(text)
        .firstWhere((position) => position > offset, orElse: () => text.length);

int previousCharacter(String text, int offset) =>
    characterOffsets(text)
        .lastWhere((position) => position < offset, orElse: () => 0);

LineBounds lineAt(String text, int offset) {
  final start = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  final newline = text.indexOf('\n', offset);
  final next = newline < 0 ? text.length : newline + 1;
  var end = newline < 0 ? text.length : newline;
  if (end > start && text[end - 1] == '\r') end--;
  return (start: start, end: end, next: next);
}

int normalPosition(String text, int offset) {
  offset = offset.clamp(0, text.length);
  final line = lineAt(text, offset);
  if (line.start == line.end) return line.start;
  return offset >= line.end ? previousCharacter(text, line.end) : offset;
}

int lineMotion(String text, int cursor, int delta) {
  final original = lineAt(text, cursor);
  final column = text.substring(original.start, cursor).characters.length;
  var target = original;
  for (var step = 0; step < delta.abs(); step++) {
    final offset = delta > 0
        ? target.next
        : (target.start - 1).clamp(0, text.length);
    target = lineAt(text, offset);
  }
  final positions = characterOffsets(text.substring(target.start, target.end));
  return normalPosition(
    text,
    target.start + positions[column.clamp(0, positions.length - 1)],
  );
}

int wordKind(String text, int offset) {
  if (offset >= text.length) return 0;
  final character = text.substring(offset, nextCharacter(text, offset));
  if (character.trim().isEmpty) return 0;
  return RegExp(r'[\p{L}\p{M}\p{N}_]', unicode: true).hasMatch(character)
      ? 1
      : 2;
}

int wordForward(String text, int cursor) {
  final kind = wordKind(text, cursor);
  var next = cursor;
  while (next < text.length && wordKind(text, next) == kind) {
    next = nextCharacter(text, next);
  }
  while (next < text.length && wordKind(text, next) == 0) {
    next = nextCharacter(text, next);
  }
  return next;
}

int wordBackward(String text, int cursor) {
  var previous = previousCharacter(text, cursor);
  while (previous > 0 && wordKind(text, previous) == 0) {
    previous = previousCharacter(text, previous);
  }
  final kind = wordKind(text, previous);
  while (previous > 0 &&
      wordKind(text, previousCharacter(text, previous)) == kind) {
    previous = previousCharacter(text, previous);
  }
  return previous;
}

int changeWordEnd(String text, int cursor, int target) {
  if (wordKind(text, cursor) == 0) return target;
  var end = target;
  while (end > cursor && wordKind(text, previousCharacter(text, end)) == 0) {
    end = previousCharacter(text, end);
  }
  return end;
}

int wordEnd(String text, int cursor) {
  var next = nextCharacter(text, cursor);
  while (next < text.length && wordKind(text, next) == 0) {
    next = nextCharacter(text, next);
  }
  final kind = wordKind(text, next);
  while (next < text.length &&
      wordKind(text, nextCharacter(text, next)) == kind) {
    next = nextCharacter(text, next);
  }
  return normalPosition(text, next);
}

int motionTarget(String text, int cursor, String motion, int count) {
  final line = lineAt(text, cursor);
  final targets = <String, int Function()>{
    'h': () => previousCharacter(text, cursor).clamp(line.start, line.end),
    'l': () => nextCharacter(text, cursor).clamp(line.start, line.end),
    'j': () => lineMotion(text, cursor, count),
    'k': () => lineMotion(text, cursor, -count),
    '0': () => line.start,
    '^': () =>
        line.start +
        (RegExp(r'\S')
                .firstMatch(text.substring(line.start, line.end))
                ?.start ??
            0),
    r'$': () => normalPosition(text, line.end),
    'w': () => wordForward(text, cursor),
    'b': () => wordBackward(text, cursor),
    'e': () => wordEnd(text, cursor),
    'gg': () => 0,
    'G': () => normalPosition(text, text.length),
  };
  final action = targets[motion];
  if (action == null) return cursor;
  if (count == 1) return action();
  if (const {'j', 'k', '0', '^', r'$', 'gg', 'G'}.contains(motion)) {
    return action();
  }
  var position = cursor;
  for (var i = 0; i < count; i++) {
    position = motionTarget(text, position, motion, 1);
  }
  return position;
}
