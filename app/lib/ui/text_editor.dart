import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_binding.dart';
import 'editor_cubit.dart';
import 'panel_header.dart';
import 'vim/vim_input.dart';

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
                child: VimInput(
                  controller: binding.controller,
                  focus: binding.focus,
                  vim: binding.vim,
                  fieldKey: const Key('editor'),
                  hint: 'Начните писать…',
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
