import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_binding.dart';
import 'editor_cubit.dart';
import 'panel_header.dart';
import 'vim/vim_cubit.dart';
import 'vim/vim_keyboard.dart';

class TextEditor extends StatelessWidget {
  const TextEditor({super.key});
  @override
  Widget build(BuildContext context) {
    final binding = context.read<EditorBinding>();
    return BlocBuilder<EditorCubit, EditorState>(
      builder: (context, state) => Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            PanelHeader(
              key: const Key('editor-header'),
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
                child: BlocBuilder<VimCubit, VimState>(
                  bloc: binding.vim,
                  builder: (context, vimState) => Focus(
                    onKeyEvent: (_, event) => vimKey(binding.vim, event),
                    child: TextField(
                      key: const Key('editor'),
                      controller: binding.controller,
                      focusNode: binding.focus,
                      readOnly:
                          vimState.enabled && vimState.mode != VimMode.insert,
                      showCursor: true,
                      cursorWidth:
                          vimState.enabled && vimState.mode != VimMode.insert
                          ? 11
                          : 2,
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
}
