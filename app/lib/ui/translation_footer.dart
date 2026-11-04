import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/translation.dart';
import 'editor_cubit.dart';
import 'components_cubit.dart';
import 'translation_cubit.dart';
import 'translation_binding.dart';
import 'vim/vim_status.dart';

class TranslationFooter extends StatelessWidget {
  const TranslationFooter({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TranslationCubit, TranslationState>(
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (translationMessage(state) case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            TranslationControls(state: state),
          ],
        ),
      );
}

class TranslationControls extends StatelessWidget {
  const TranslationControls({super.key, required this.state});
  final TranslationState state;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final action = TranslationAction(state: state);
      if (constraints.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TranslationStatus(),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      }
      return Row(
        children: [
          const Expanded(child: TranslationStatus()),
          const SizedBox(width: 20),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      );
    },
  );
}

class TranslationStatus extends StatelessWidget {
  const TranslationStatus({super.key});
  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorCubit>().state;
    final binding = context.read<TranslationBinding>();
    return Row(
      children: [
        Expanded(
          child: Text(
            '${editor.settings.model.shortName} · Локально',
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

class TranslationAction extends StatelessWidget {
  const TranslationAction({super.key, required this.state});
  final TranslationState state;
  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorCubit>().state;
    final cubit = context.read<TranslationCubit>();
    return FilledButton.icon(
      key: const Key('translate'),
      onPressed: state.translating
          ? cubit.cancel
          : context.select<ComponentsCubit, bool>(
                  (cubit) => cubit.state.ready,
                ) &&
                state.ready &&
                !editor.checking
          ? () => cubit.translate(editor.settings)
          : null,
      icon: Icon(
        state.translating ? Icons.stop_rounded : Icons.translate_rounded,
      ),
      label: Text(state.translating ? 'Отменить' : 'Перевести'),
    );
  }
}

String? translationMessage(TranslationState state) {
  if (state.saveFailed) {
    return 'Не удалось сохранить перевод. Скопируйте текст перед закрытием.';
  }
  if (state.draft.text.runes.length > translationLimit) {
    return 'Переводим до $translationLimit знаков за раз. Разделите текст на части.';
  }
  if (state.draft.from == state.draft.to) {
    return 'Выберите разные языки оригинала и перевода.';
  }
  return state.message;
}
