import 'dart:async';

import 'package:flutter/widgets.dart';

import 'editor_cubit.dart';
import 'translation_cubit.dart';
import 'vim/vim_cubit.dart';

class TranslationBinding {
  TranslationBinding(this.translation, this.editor) {
    input.text = translation.state.draft.text;
    output.text = translation.state.draft.output;
    vim = VimCubit(input)..enable(editor.state.settings.vimMode);
    input.addListener(textChanged);
    _translation = translation.stream.listen(update);
    _settings = editor.stream.listen(
      (state) => vim.enable(state.settings.vimMode),
    );
  }
  final TranslationCubit translation;
  final EditorCubit editor;
  final input = TextEditingController(), output = TextEditingController();
  final focus = FocusNode();
  late final VimCubit vim;
  late final StreamSubscription<TranslationState> _translation;
  late final StreamSubscription<EditorState> _settings;

  void textChanged() => translation.edit(input.text);

  void toggleVim(bool enabled) {
    editor.configure(editor.state.settings.copyWith(vimMode: enabled));
    vim.enable(enabled);
    focus.requestFocus();
  }

  void update(TranslationState state) {
    syncTranslationController(input, state.draft.text);
    syncTranslationController(output, state.draft.output);
  }

  void dispose() {
    _translation.cancel();
    _settings.cancel();
    input.removeListener(textChanged);
    vim.close();
    input.dispose();
    output.dispose();
    focus.dispose();
  }
}

void syncTranslationController(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(
      offset: controller.selection.extentOffset.clamp(0, text.length),
    ),
  );
}
