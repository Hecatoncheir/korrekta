import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'editor_cubit.dart';
import 'editor_binding.dart';
import 'editor_footer.dart';
import 'components_cubit.dart';
import 'setup_banner.dart';
import 'navigation_cubit.dart';
import 'workspace.dart';
import 'update_announcer.dart';
import 'window_session.dart';
import 'translation_cubit.dart';
import 'translation_footer.dart';
import 'translation_binding.dart';
import 'generation_binding.dart';
import 'generation_cubit.dart';
import 'generation_footer.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.session});
  final WindowSession? session;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final lifecycle = AppLifecycleListener(onExitRequested: saveBeforeExit);
  late final EditorBinding binding;
  late final TranslationBinding translationBinding;
  late final GenerationBinding generationBinding;

  @override
  void initState() {
    super.initState();
    binding = EditorBinding(context.read<EditorCubit>());
    translationBinding = TranslationBinding(
      context.read<TranslationCubit>(),
      context.read<EditorCubit>(),
    );
    generationBinding = GenerationBinding(
      context.read<GenerationCubit>(),
      context.read<EditorCubit>(),
    );
    lifecycle;
    widget.session?.beforeClose = () async =>
        await saveBeforeExit() == AppExitResponse.exit;
    widget.session?.onFailure = (message) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };
  }

  @override
  void dispose() {
    widget.session?.beforeClose = null;
    widget.session?.onFailure = null;
    lifecycle.dispose();
    binding.dispose();
    translationBinding.dispose();
    generationBinding.dispose();
    super.dispose();
  }

  Future<AppExitResponse> saveBeforeExit() async {
    final cubit = context.read<EditorCubit>();
    final translation = context.read<TranslationCubit>();
    final generation = context.read<GenerationCubit>();
    final components = context.read<ComponentsCubit>();
    await Future.wait([cubit.flush(), translation.flush(), generation.flush()]);
    if (cubit.state.saved &&
        translation.state.saved &&
        generation.state.saved) {
      translation.cancel();
      generation.cancel();
      await components.shutdown();
      return AppExitResponse.exit;
    }
    if (!mounted) return AppExitResponse.cancel;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Текст не сохранён'),
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
    if (exit != true) return AppExitResponse.cancel;
    translation.cancel();
    generation.cancel();
    await components.shutdown();
    return AppExitResponse.exit;
  }

  Future<void> newDraft() async {
    final cubit = context.read<EditorCubit>();
    final translation = context.read<TranslationCubit>();
    final generation = context.read<GenerationCubit>();
    final section = context.read<NavigationCubit>().state;
    final text = switch (section) {
      AppSection.generation =>
        '${generation.state.draft.prompt}${generation.state.draft.output}',
      AppSection.translation =>
        '${translation.state.draft.text}${translation.state.draft.output}',
      _ => cubit.state.text,
    };
    if (text.isEmpty) return;
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
    if (clear != true) return;
    switch (section) {
      case AppSection.generation:
        generation.clear();
      case AppSection.translation:
        translation.clear();
      case AppSection.editor:
        cubit.edit('');
      case AppSection.settings:
        break;
    }
  }

  Future<void> runPrimary() {
    final editor = context.read<EditorCubit>();
    final translation = context.read<TranslationCubit>();
    final generation = context.read<GenerationCubit>();
    if (!context.read<ComponentsCubit>().state.ready ||
        editor.state.checking ||
        translation.state.translating ||
        generation.state.generating) {
      return Future.value();
    }
    return switch (context.read<NavigationCubit>().state) {
      AppSection.editor => editor.check(),
      AppSection.translation => translation.translate(editor.state.settings),
      AppSection.generation => generation.generate(editor.state.settings),
      AppSection.settings => Future.value(),
    };
  }

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: binding),
      RepositoryProvider.value(value: translationBinding),
      RepositoryProvider.value(value: generationBinding),
    ],
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            runPrimary(),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            runPrimary(),
      },
      child: Scaffold(
        body: UpdateAnnouncer(
          child: SafeArea(
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
                        const SetupBanner(),
                        const Expanded(child: Workspace()),
                        const SizedBox(height: 12),
                        BlocBuilder<NavigationCubit, AppSection>(
                          builder: (context, section) => switch (section) {
                            AppSection.editor => const EditorFooter(),
                            AppSection.translation => const TranslationFooter(),
                            AppSection.generation => const GenerationFooter(),
                            AppSection.settings => const SizedBox(height: 48),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
        const SectionButton(
          section: AppSection.editor,
          label: 'Редактор',
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 8),
        const SectionButton(
          section: AppSection.generation,
          label: 'Генерация',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 8),
        const SectionButton(
          section: AppSection.translation,
          label: 'Переводчик',
          icon: Icons.translate_rounded,
        ),
        const Spacer(),
        BlocBuilder<EditorCubit, EditorState>(
          builder: (context, state) => IconButton(
            style: bottomIconStyle(context),
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
          style: bottomIconStyle(context),
          onPressed: () {
            FocusScope.of(context).unfocus();
            context.read<NavigationCubit>().select(AppSection.settings);
            context.read<ComponentsCubit>().refresh(
              context.read<EditorCubit>().state.settings,
            );
          },
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

ButtonStyle bottomIconStyle(BuildContext context) => IconButton.styleFrom(
  foregroundColor: Color(
    Theme.of(context).brightness == Brightness.dark ? 0xfffabd2f : 0xffb57614,
  ),
);

class EditorHeader extends StatelessWidget {
  const EditorHeader({super.key, required this.onNew});
  final VoidCallback onNew;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NavigationCubit, AppSection>(
        builder: (context, section) => Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'корректа.',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(switch (section) {
                        AppSection.generation => 'Текст по вашему запросу',
                        AppSection.translation => 'Перевод на вашем компьютере',
                        _ => 'Место для ваших мыслей',
                      }, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (section != AppSection.settings)
                  IconButton(
                    tooltip: 'Новый текст',
                    onPressed: onNew,
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                if (section != AppSection.settings)
                  IconButton(
                    tooltip: 'Скопировать текст',
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: sectionClipboard(context, section)),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                  ),
              ],
            ),
            if (section == AppSection.translation)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: IconButton(
                    key: const Key('swap-languages'),
                    tooltip: 'Поменять языки местами',
                    onPressed: context.read<TranslationCubit>().swap,
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

String translationClipboard(TranslationState state) =>
    state.draft.output.isEmpty ? state.draft.text : state.draft.output;

String sectionClipboard(BuildContext context, AppSection section) =>
    switch (section) {
      AppSection.translation => translationClipboard(
        context.read<TranslationCubit>().state,
      ),
      AppSection.generation =>
        context.read<GenerationCubit>().state.draft.output,
      _ => context.read<EditorCubit>().state.text,
    };

class SectionButton extends StatelessWidget {
  const SectionButton({
    super.key,
    required this.section,
    required this.label,
    required this.icon,
  });
  final AppSection section;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NavigationCubit, AppSection>(
        builder: (context, active) => IconButton(
          tooltip: label,
          isSelected: active == section,
          style: IconButton.styleFrom(
            foregroundColor: active == section
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).iconTheme.color,
            backgroundColor: active == section
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .10)
                : null,
          ),
          onPressed: () {
            FocusScope.of(context).unfocus();
            context.read<NavigationCubit>().select(section);
          },
          icon: Icon(icon, size: 28),
        ),
      );
}
