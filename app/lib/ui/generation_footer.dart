import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components_cubit.dart';
import 'editor_cubit.dart';
import 'generation_binding.dart';
import 'generation_cubit.dart';
import 'translation_cubit.dart';
import 'vim/vim_status.dart';

class GenerationFooter extends StatelessWidget {
  const GenerationFooter({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<GenerationCubit, GenerationState>(
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (generationMessage(state) case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(message),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GenerationStatus(),
                      SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GenerationAction(),
                      ),
                    ],
                  );
                }
                return const Row(
                  children: [
                    Expanded(child: GenerationStatus()),
                    SizedBox(width: 20),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GenerationAction(),
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

class GenerationStatus extends StatelessWidget {
  const GenerationStatus({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<EditorCubit>().state.settings;
    final binding = context.read<GenerationBinding>();
    return Row(
      children: [
        Expanded(
          child: Text(
            '${settings.model.shortName} · Локально',
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

class GenerationAction extends StatelessWidget {
  const GenerationAction({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<GenerationCubit>().state;
    final editor = context.watch<EditorCubit>().state;
    final translating = context.select<TranslationCubit, bool>(
      (c) => c.state.translating,
    );
    final ready = context.select<ComponentsCubit, bool>((c) => c.state.ready);
    final cubit = context.read<GenerationCubit>();
    final enabled = ready && state.ready && !editor.checking && !translating;
    return FilledButton.icon(
      key: const Key('generate'),
      onPressed: state.generating
          ? cubit.cancel
          : enabled
          ? () => cubit.generate(editor.settings)
          : null,
      icon: Icon(
        state.generating ? Icons.stop_rounded : Icons.auto_awesome_rounded,
      ),
      label: Text(state.generating ? 'Отменить' : 'Сгенерировать'),
    );
  }
}
