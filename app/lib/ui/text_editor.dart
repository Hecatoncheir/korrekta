import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/check_result.dart';
import 'editor_cubit.dart';

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

class TextEditor extends StatefulWidget {
  const TextEditor({super.key});
  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  late final controller = MarkedTextController()
    ..text = context.read<EditorCubit>().state.text;
  final focus = FocusNode();
  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  void update(EditorState state) {
    controller.suggestions = state.result?.suggestions ?? const [];
    if (controller.text == state.text) return;
    final offset = controller.selection.extentOffset.clamp(
      0,
      state.text.length,
    );
    controller.value = TextEditingValue(
      text: state.text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<EditorCubit, EditorState>(
    listener: (_, state) => update(state),
    builder: (context, state) => Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ЧЕРНОВИК',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  state.saved ? 'Сохранён' : 'Сохраняем…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TextField(
                key: const Key('editor'),
                controller: controller,
                focusNode: focus,
                onChanged: context.read<EditorCubit>().edit,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 21, height: 1.7),
                decoration: const InputDecoration(
                  hintText: 'Ваш голос остаётся.\nНачните писать…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${RegExp(r"\S+").allMatches(state.text).length} слов · ${state.text.runes.length} знаков',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Text('Русский'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
