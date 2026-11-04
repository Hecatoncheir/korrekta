import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/check_result.dart';
import 'editor_cubit.dart';
import 'panel_header.dart';

class SuggestionsPanel extends StatelessWidget {
  const SuggestionsPanel({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, state) {
      final result = state.result;
      return Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            PanelHeader(
              key: const Key('suggestions-header'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Подсказки',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text('${result?.suggestions.length ?? 0}'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: SuggestionsBody(state: state)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: result == null || result.recommended.isEmpty
                    ? null
                    : () => context.read<EditorCubit>().accept(
                        result.recommended,
                      ),
                icon: const Icon(Icons.done_all),
                label: const Text('Принять рекомендованные'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class SuggestionsBody extends StatelessWidget {
  const SuggestionsBody({super.key, required this.state});
  final EditorState state;
  @override
  Widget build(BuildContext context) {
    if (state.checking) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Проверяем на вашем компьютере…'),
          ],
        ),
      );
    }
    final result = state.result;
    if (result == null) return const EmptySuggestions();
    if (result.suggestions.isEmpty) {
      return const EmptySuggestions(checked: true);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: result.suggestions.length,
      separatorBuilder: (_, _) => const Divider(height: 28),
      itemBuilder: (context, index) =>
          SuggestionCard(index: index, suggestion: result.suggestions[index]),
    );
  }
}

class EmptySuggestions extends StatelessWidget {
  const EmptySuggestions({super.key, this.checked = false});
  final bool checked;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_rounded : Icons.edit_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              checked ? 'Проверка завершена' : 'Здесь будут подсказки',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              checked
                  ? 'Подходящих правок не найдено.'
                  : 'Напишите текст и нажмите «Проверить».',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.index,
    required this.suggestion,
  });
  final int index;
  final Suggestion suggestion;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              suggestion.recommended == 0
                  ? 'На ваше усмотрение'
                  : 'Рекомендуем исправить',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          IconButton(
            tooltip: 'Пропустить',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.read<EditorCubit>().dismiss(index),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      SelectableText(
        suggestion.slot.original.isEmpty
            ? 'Вставить знак'
            : suggestion.slot.original,
        style: const TextStyle(
          fontSize: 20,
          decoration: TextDecoration.lineThrough,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (
            var choice = 1;
            choice < suggestion.slot.options.length;
            choice++
          )
            ActionChip(
              avatar: choice == suggestion.recommended
                  ? const Icon(Icons.check, size: 16)
                  : null,
              label: Text(suggestion.slot.options[choice]),
              onPressed: () =>
                  context.read<EditorCubit>().accept({index: choice}),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        suggestion.sources.map(sourceName).join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

String sourceName(String source) => switch (source) {
  'gigachat' => 'GigaChat',
  'languagetool' => 'LanguageTool',
  'hunspell' => 'Hunspell',
  'symspell' => 'SymSpell',
  _ => source,
};
