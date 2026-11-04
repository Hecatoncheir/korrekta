import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../editor_cubit.dart';
import 'vim_cubit.dart';

class VimStatus extends StatelessWidget {
  const VimStatus({super.key, required this.vim, required this.onToggle});
  final VimCubit vim;
  final ValueChanged<bool> onToggle;
  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, editor) => BlocBuilder<VimCubit, VimState>(
      bloc: vim,
      builder: (context, state) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 24, 16),
        child: Row(
          children: [
            Switch(
              value: editor.settings.vimMode,
              onChanged: onToggle,
              key: const Key('vim-toggle'),
            ),
            const SizedBox(width: 8),
            const Text('Vim mode'),
            const SizedBox(width: 16),
            if (state.enabled)
              Expanded(
                child: Text(
                  '${vimModeName(state.mode)} ${state.pending}',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String vimModeName(VimMode mode) => switch (mode) {
  VimMode.normal => 'NORMAL',
  VimMode.insert => 'INSERT',
  VimMode.visual => 'VISUAL',
  VimMode.visualLine => 'VISUAL LINE',
};
