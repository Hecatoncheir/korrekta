import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_cubit.dart';
import 'settings_dialog.dart';
import 'suggestions_panel.dart';
import 'text_editor.dart';
import 'window_session.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.session});
  final WindowSession? session;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final lifecycle = AppLifecycleListener(onExitRequested: saveBeforeExit);

  @override
  void initState() {
    super.initState();
    lifecycle;
    widget.session?.beforeClose = () async =>
        await saveBeforeExit() == AppExitResponse.exit;
  }

  @override
  void dispose() {
    widget.session?.beforeClose = null;
    lifecycle.dispose();
    super.dispose();
  }

  Future<AppExitResponse> saveBeforeExit() async {
    final cubit = context.read<EditorCubit>();
    await cubit.flush();
    if (cubit.state.saved) return AppExitResponse.exit;
    if (!mounted) return AppExitResponse.cancel;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Черновик не сохранён'),
        content: const Text(
          'Вернитесь к тексту и скопируйте его, чтобы не потерять изменения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('К тексту'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Закрыть без сохранения'),
          ),
        ],
      ),
    );
    return exit == true ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<void> newDraft() async {
    final cubit = context.read<EditorCubit>();
    if (cubit.state.text.isEmpty) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Начать новый текст?'),
        content: const Text(
          'Текущий черновик будет очищен. Сначала скопируйте его, если он нужен.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Новый текст'),
          ),
        ],
      ),
    );
    if (clear == true) cubit.edit('');
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          context.read<EditorCubit>().check(),
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          context.read<EditorCubit>().check(),
    },
    child: Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const SideBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorHeader(onNew: newDraft),
                    const SizedBox(height: 20),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 720) {
                            return const Column(
                              children: [
                                Expanded(flex: 3, child: TextEditor()),
                                SizedBox(height: 12),
                                Expanded(flex: 2, child: SuggestionsPanel()),
                              ],
                            );
                          }
                          return const Row(
                            children: [
                              Expanded(flex: 7, child: TextEditor()),
                              SizedBox(width: 20),
                              Expanded(flex: 4, child: SuggestionsPanel()),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const EditorFooter(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SideBar extends StatelessWidget {
  const SideBar({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(
          width: 0.6,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.07),
        ),
      ),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Image.asset('assets/mark.png', width: 44, height: 44),
        ),
        IconButton(
          tooltip: 'Редактор',
          onPressed: () {},
          icon: const Icon(Icons.edit_note_rounded, size: 30),
        ),
        const Spacer(),
        BlocBuilder<EditorCubit, EditorState>(
          builder: (context, state) => IconButton(
            tooltip: state.settings.dark ? 'Светлая тема' : 'Тёмная тема',
            onPressed: () => context.read<EditorCubit>().configure(
              state.settings.copyWith(dark: !state.settings.dark),
            ),
            icon: Icon(
              state.settings.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Настройки',
          onPressed: () => openSettings(context),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

class EditorHeader extends StatelessWidget {
  const EditorHeader({super.key, required this.onNew});
  final VoidCallback onNew;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('корректа.', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Место для ваших мыслей',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Новый текст',
        onPressed: onNew,
        icon: const Icon(Icons.note_add_outlined),
      ),
      IconButton(
        tooltip: 'Скопировать текст',
        onPressed: () => Clipboard.setData(
          ClipboardData(text: context.read<EditorCubit>().state.text),
        ),
        icon: const Icon(Icons.copy_rounded),
      ),
    ],
  );
}

class EditorFooter extends StatelessWidget {
  const EditorFooter({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.message case final message?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              '${state.settings.model.shortName} · Локально',
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
              ),
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Отменить замену',
                  onPressed: state.previous == null
                      ? null
                      : context.read<EditorCubit>().undo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                FilledButton.icon(
                  key: const Key('check'),
                  onPressed: state.checking || state.text.trim().isEmpty
                      ? null
                      : context.read<EditorCubit>().check,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: Text(state.checking ? 'Проверяем…' : 'Проверить'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}
