import 'package:flutter/material.dart';
import 'package:korrekta_model_benchmark/text_guard.dart';

import '../domain/check_result.dart';

enum EditorMarkKind { error, suggestion, correction }

typedef EditorMark = ({TextRange range, EditorMarkKind kind});

class MarkedTextController extends TextEditingController {
  List<EditorMark> _marks = const [];
  ({String text, CheckResult? result, String? previous})? _review;

  void review(CheckResult? result, {String? previous}) {
    final snapshot = (text: text, result: result, previous: previous);
    if (snapshot == _review) return;
    _review = snapshot;
    _marks = marksFor(text, result, previous);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    var offset = 0;
    for (final mark in _marks) {
      final range = mark.range;
      if (range.start < offset || range.end > text.length) continue;
      spans.add(TextSpan(text: text.substring(offset, range.start)));
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: markStyle(Theme.of(context), mark.kind),
        ),
      );
      offset = range.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}

List<EditorMark> marksFor(String text, CheckResult? result, String? previous) {
  final marks = <EditorMark>[];
  if (result?.original == text) {
    for (final suggestion in result!.suggestions) {
      final slot = suggestion.slot;
      marks.add((
        range: visibleRange(text, slot.start, slot.end),
        kind: suggestion.recommended > 0
            ? EditorMarkKind.error
            : EditorMarkKind.suggestion,
      ));
    }
  } else if (previous != null) {
    for (final edit in diffEdits(text, previous)) {
      marks.add((
        range: correctedWord(text, visibleRange(text, edit.start, edit.end)),
        kind: EditorMarkKind.correction,
      ));
    }
  }
  marks.sort((a, b) => a.range.start.compareTo(b.range.start));
  return marks;
}

TextRange visibleRange(String text, int start, int end) {
  var offset = 0;
  final boundaries = [
    0,
    for (final character in text.characters) offset += character.length,
  ];
  start = boundaries.lastWhere(
    (position) => position <= start,
    orElse: () => 0,
  );
  end = boundaries.firstWhere(
    (position) => position >= end,
    orElse: () => text.length,
  );
  if (start == end) {
    final index = boundaries.indexOf(start);
    start = boundaries[(index - 1).clamp(0, boundaries.length - 1)];
    end =
        boundaries[index == 0
            ? (index + 1).clamp(0, boundaries.length - 1)
            : index];
  }
  return TextRange(start: start, end: end);
}

TextRange correctedWord(String text, TextRange range) {
  final words = RegExp(r'[\p{L}\p{M}\p{N}_]+', unicode: true).allMatches(text);
  for (final word in words) {
    if (word.start <= range.start && word.end >= range.end) {
      return TextRange(start: word.start, end: word.end);
    }
  }
  return range;
}

TextStyle markStyle(ThemeData theme, EditorMarkKind kind) {
  final dark = theme.brightness == Brightness.dark;
  final accent = switch (kind) {
    EditorMarkKind.error => theme.colorScheme.error,
    EditorMarkKind.suggestion => Color(dark ? 0xfffabd2f : 0xffb57614),
    EditorMarkKind.correction => theme.colorScheme.primary,
  };
  final decoration = switch (kind) {
    EditorMarkKind.error => TextDecorationStyle.wavy,
    EditorMarkKind.suggestion => TextDecorationStyle.dotted,
    EditorMarkKind.correction => TextDecorationStyle.solid,
  };
  return TextStyle(
    color: theme.colorScheme.onSurface,
    backgroundColor: accent.withValues(alpha: dark ? .22 : .14),
    decoration: TextDecoration.underline,
    decorationColor: accent,
    decorationThickness: 2,
    decorationStyle: decoration,
  );
}
