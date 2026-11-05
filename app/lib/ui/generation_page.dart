import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/generation.dart';
import 'generation_binding.dart';
import 'generation_cubit.dart';
import 'panel_header.dart';
import 'vim/vim_input.dart';
import 'workspace.dart';

class GenerationPage extends StatelessWidget {
  const GenerationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final binding = context.read<GenerationBinding>();
    return BlocBuilder<GenerationCubit, GenerationState>(
      builder: (context, state) => WorkspaceColumns(
        leftFlex: 1,
        rightFlex: 1,
        verticalFlex: (1, 1),
        left: GenerationPanel(
          title: 'Запрос',
          status: switch (state) {
            GenerationState(saveFailed: true) => 'Не сохранён',
            GenerationState(saved: true) => 'Сохранён',
            _ => 'Сохраняем…',
          },
          count: '${state.draft.prompt.runes.length} / $generationLimit знаков',
          child: VimInput(
            controller: binding.input,
            focus: binding.focus,
            vim: binding.vim,
            fieldKey: const Key('generation-input'),
            hint: 'Опишите текст, который нужно создать…',
          ),
        ),
        right: GenerationPanel(
          title: 'Результат',
          status: state.generating ? 'Создаём…' : '',
          count: '${state.draft.output.runes.length} знаков',
          busy: state.generating,
          onCopy: state.draft.output.isEmpty
              ? null
              : () =>
                    Clipboard.setData(ClipboardData(text: state.draft.output)),
          child: TextField(
            key: const Key('generation-output'),
            controller: binding.output,
            readOnly: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 21, height: 1.7),
            decoration: const InputDecoration(
              hintText: 'Здесь появится готовый текст',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class GenerationPanel extends StatelessWidget {
  const GenerationPanel({
    super.key,
    required this.title,
    required this.status,
    required this.count,
    required this.child,
    this.busy = false,
    this.onCopy,
  });
  final String title, status, count;
  final Widget child;
  final bool busy;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        PanelHeader(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                  ),
                ),
              ),
              Text(status, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(padding: const EdgeInsets.all(24), child: child),
              ),
              if (busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (onCopy != null)
                  IconButton(
                    tooltip: 'Скопировать результат',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
