import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/translation.dart';
import 'panel_header.dart';
import 'translation_cubit.dart';
import 'workspace.dart';
import 'translation_binding.dart';
import 'vim/vim_input.dart';

class TranslationPage extends StatelessWidget {
  const TranslationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final binding = context.read<TranslationBinding>();
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, state) => WorkspaceColumns(
        leftFlex: 1,
        rightFlex: 1,
        verticalFlex: (1, 1),
        left: TranslationPanel(
          controller: binding.input,
          language: state.draft.from,
          source: true,
          input: VimInput(
            controller: binding.input,
            focus: binding.focus,
            vim: binding.vim,
            fieldKey: const Key('translation-input'),
            hint: 'Введите текст…',
          ),
          onLanguage: (language) =>
              context.read<TranslationCubit>().languages(from: language),
        ),
        right: TranslationPanel(
          controller: binding.output,
          language: state.draft.to,
          busy: state.translating,
          onLanguage: (language) =>
              context.read<TranslationCubit>().languages(to: language),
        ),
      ),
    );
  }
}

class TranslationPanel extends StatelessWidget {
  const TranslationPanel({
    super.key,
    required this.controller,
    required this.language,
    required this.onLanguage,
    this.source = false,
    this.busy = false,
    this.input,
  });
  final TextEditingController controller;
  final TranslationLanguage language;
  final ValueChanged<TranslationLanguage> onLanguage;
  final bool source, busy;
  final Widget? input;

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
                  source ? 'ОРИГИНАЛ' : 'ПЕРЕВОД',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                  ),
                ),
              ),
              Flexible(
                child: LanguagePicker(
                  language: language,
                  onChanged: onLanguage,
                  source: source,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child:
                      input ??
                      TextField(
                        key: Key(
                          source ? 'translation-input' : 'translation-output',
                        ),
                        controller: controller,
                        readOnly: !source,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        onChanged: source
                            ? context.read<TranslationCubit>().edit
                            : null,
                        style: const TextStyle(fontSize: 21, height: 1.7),
                        decoration: InputDecoration(
                          hintText: source
                              ? 'Введите текст…'
                              : 'Здесь появится перевод',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                ),
              ),
              if (busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 20),
                          Text('Переводим…'),
                        ],
                      ),
                    ),
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
                    source
                        ? '${controller.text.runes.length} / $translationLimit знаков'
                        : '${controller.text.runes.length} знаков',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          source &&
                              controller.text.runes.length > translationLimit
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
                if (!source)
                  IconButton(
                    tooltip: 'Скопировать перевод',
                    onPressed: controller.text.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: controller.text),
                          ),
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

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
    required this.language,
    required this.onChanged,
    required this.source,
  });
  final TranslationLanguage language;
  final ValueChanged<TranslationLanguage> onChanged;
  final bool source;
  @override
  Widget build(BuildContext context) => Semantics(
    label: source ? 'Язык оригинала' : 'Язык перевода',
    child: DropdownButtonHideUnderline(
      child: DropdownButton<TranslationLanguage>(
        key: Key(source ? 'source-language' : 'target-language'),
        value: language,
        isExpanded: true,
        alignment: Alignment.centerRight,
        style: Theme.of(context).textTheme.bodyMedium,
        items: [
          for (final item in TranslationLanguage.values)
            DropdownMenuItem(
              value: item,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ),
  );
}
