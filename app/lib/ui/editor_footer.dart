import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_binding.dart';
import 'editor_cubit.dart';
import 'components_cubit.dart';
import 'vim/vim_status.dart';
import 'translation_cubit.dart';
import 'generation_cubit.dart';

class EditorFooter extends StatelessWidget {
  const EditorFooter({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.message case final message?
            when message != state.result?.warning)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final status = EditorStatus(state: state);
            final actions = EditorActions(state: state);
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 7, child: status),
                const SizedBox(width: 20),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actions,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class EditorStatus extends StatelessWidget {
  const EditorStatus({super.key, required this.state});
  final EditorState state;
  @override
  Widget build(BuildContext context) {
    final binding = context.read<EditorBinding>();
    return Row(
      children: [
        Expanded(
          child: Text(
            '${state.settings.model.shortName} · Локально',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        VimStatus(vim: binding.vim, onToggle: binding.toggleVim),
      ],
    );
  }
}

class EditorActions extends StatelessWidget {
  const EditorActions({super.key, required this.state});
  final EditorState state;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Отменить замену',
        onPressed: state.previous == null
            ? null
            : context.read<EditorCubit>().undo,
        icon: const Icon(Icons.undo_rounded),
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        key: const Key('check'),
        onPressed:
            !context.select<ComponentsCubit, bool>(
                  (cubit) => cubit.state.ready,
                ) ||
                state.checking ||
                context.select<TranslationCubit, bool>(
                  (cubit) => cubit.state.translating,
                ) ||
                context.select<GenerationCubit, bool>(
                  (cubit) => cubit.state.generating,
                ) ||
                state.text.trim().isEmpty
            ? null
            : context.read<EditorCubit>().check,
        icon: const Icon(Icons.auto_fix_high_outlined),
        label: Text(state.checking ? 'Проверяем…' : 'Проверить'),
      ),
    ],
  );
}
