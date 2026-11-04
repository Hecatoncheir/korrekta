import 'dart:async';

import 'package:flutter/widgets.dart';

import 'editor_cubit.dart';
import 'marked_text_controller.dart';
import 'vim/vim_cubit.dart';

class EditorBinding {
  EditorBinding(this.editor) {
    controller.text = editor.state.text;
    _lastText = controller.text;
    vim = VimCubit(controller);
    update(editor.state);
    controller.addListener(textChanged);
    _subscription = editor.stream.listen(update);
  }
  final EditorCubit editor;
  final controller = MarkedTextController();
  final focus = FocusNode();
  late final VimCubit vim;
  late String _lastText;
  late final StreamSubscription<EditorState> _subscription;

  void textChanged() {
    if (controller.text == _lastText) return;
    _lastText = controller.text;
    editor.edit(_lastText);
  }

  void toggleVim(bool enabled) {
    editor.configure(editor.state.settings.copyWith(vimMode: enabled));
    vim.enable(enabled);
    focus.requestFocus();
  }

  void update(EditorState state) {
    vim.enable(state.settings.vimMode);
    if (controller.text != state.text) {
      final offset = controller.selection.extentOffset.clamp(
        0,
        state.text.length,
      );
      controller.value = TextEditingValue(
        text: state.text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    controller.review(state.result, previous: state.previous);
  }

  void dispose() {
    _subscription.cancel();
    controller.removeListener(textChanged);
    vim.close();
    controller.dispose();
    focus.dispose();
  }
}
