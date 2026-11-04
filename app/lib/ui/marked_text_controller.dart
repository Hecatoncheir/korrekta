import 'package:flutter/material.dart';

import '../domain/check_result.dart';

class MarkedTextController extends TextEditingController {
  List<Suggestion> suggestions = const [];
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
    for (final suggestion in suggestions) {
      final slot = suggestion.slot;
      if (slot.start < offset || slot.end > text.length) continue;
      spans.add(TextSpan(text: text.substring(offset, slot.start)));
      spans.add(
        TextSpan(
          text: text.substring(slot.start, slot.end),
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
      offset = slot.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}
