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
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Vim mode',
              child: SizedBox(
                width: 36,
                height: 26,
                child: FittedBox(
                  child: Switch(
                    value: editor.settings.vimMode,
                    onChanged: onToggle,
                    key: const Key('vim-toggle'),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('Vim mode', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 10),
            if (state.enabled)
              Text(
                '${vimModeName(state.mode)} ${state.pending}',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.primary,
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
