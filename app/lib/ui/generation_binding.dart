import 'dart:async';

import 'package:flutter/widgets.dart';

import 'editor_cubit.dart';
import 'generation_cubit.dart';
import 'vim/vim_cubit.dart';

class GenerationBinding {
  GenerationBinding(this.generation, this.editor) {
    input.text = generation.state.draft.prompt;
    output.text = generation.state.draft.output;
    vim = VimCubit(input)..enable(editor.state.settings.vimMode);
    input.addListener(textChanged);
    _generation = generation.stream.listen(update);
    _settings = editor.stream.listen(
      (state) => vim.enable(state.settings.vimMode),
    );
  }
  final GenerationCubit generation;
  final EditorCubit editor;
  final input = TextEditingController(), output = TextEditingController();
  final focus = FocusNode();
  late final VimCubit vim;
  late final StreamSubscription<GenerationState> _generation;
  late final StreamSubscription<EditorState> _settings;

  void textChanged() => generation.edit(input.text);

  void toggleVim(bool enabled) {
    editor.configure(editor.state.settings.copyWith(vimMode: enabled));
    vim.enable(enabled);
    focus.requestFocus();
  }

  void update(GenerationState state) {
    syncGenerationController(input, state.draft.prompt);
    syncGenerationController(output, state.draft.output);
  }

  void dispose() {
    _generation.cancel();
    _settings.cancel();
    input.removeListener(textChanged);
    vim.close();
    input.dispose();
    output.dispose();
    focus.dispose();
  }
}

void syncGenerationController(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(
      offset: controller.selection.extentOffset.clamp(0, text.length),
    ),
  );
}
