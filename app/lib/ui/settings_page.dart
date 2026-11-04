import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/settings.dart';
import 'components_cubit.dart';
import 'editor_cubit.dart';
import 'update_panel.dart';
import 'workspace.dart';
import 'theme.dart';
import 'translation_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const WorkspaceColumns(
    left: Card(margin: EdgeInsets.zero, child: ConnectionFields()),
    right: SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModelPicker(),
          SizedBox(height: 24),
          ComponentPanel(),
          Divider(height: 40),
          UpdatePanel(),
        ],
      ),
    ),
  );
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: SizedBox.expand(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    ),
  );
}

class ModelPicker extends StatelessWidget {
  const ModelPicker({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    builder: (context, state) => RadioGroup<LocalModel>(
      groupValue: state.settings.model,
      onChanged: (model) {
        if (model == null) return;
        final settings = state.settings.copyWith(model: model);
        context.read<EditorCubit>().configure(settings);
      },
      child: BlocBuilder<ComponentsCubit, ComponentsState>(
        builder: (context, components) => Column(
          children: [
            for (final model in LocalModel.values)
              RadioListTile<LocalModel>(
                value: model,
                enabled:
                    !state.checking &&
                    !context.select<TranslationCubit, bool>(
                      (cubit) => cubit.state.translating,
                    ),
                title: Text(model.label),
                dense: true,
              ),
          ],
        ),
      ),
    ),
  );
}

class ComponentPanel extends StatelessWidget {
  const ComponentPanel({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ComponentsCubit, ComponentsState>(
        builder: (context, state) {
          final settings = context.read<EditorCubit>().state.settings;
          final status = state.status;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Всё на вашем компьютере',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              StatusLine('Ollama', status?.ollama),
              StatusLine(settings.model.shortName, status?.model),
              StatusLine('LanguageTool 6.8', status?.languageTool),
              StatusLine('Словари и Hunspell', state.ready ? true : null),
              const SizedBox(height: 12),
              if (!state.ready && !state.busy)
                FilledButton.icon(
                  style: settingsActionStyle(),
                  onPressed: () =>
                      context.read<ComponentsCubit>().prepare(settings),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Продолжить подготовку'),
                ),
              const SizedBox(height: 12),
              const Text(
                'Компоненты скачиваются и запускаются автоматически. Первый запуск требует интернета и свободного места. После подготовки проверка и перевод работают локально.',
              ),
            ],
          );
        },
      );
}

class StatusLine extends StatelessWidget {
  const StatusLine(this.label, this.ready, {super.key});
  final String label;
  final bool? ready;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          ready == true ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 16,
          color: ready == true ? Theme.of(context).colorScheme.primary : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(switch (ready) {
          true => 'Готово',
          false => 'Не найдено',
          null => 'Проверяем…',
        }),
      ],
    ),
  );
}

class ConnectionFields extends StatefulWidget {
  const ConnectionFields({super.key});
  @override
  State<ConnectionFields> createState() => _ConnectionFieldsState();
}

class _ConnectionFieldsState extends State<ConnectionFields> {
  late final Settings initial = context.read<EditorCubit>().state.settings;
  late final store = TextEditingController(text: initial.store);
  late final hunspell = TextEditingController(text: initial.hunspell);
  late final ollama = TextEditingController(text: initial.ollama);
  late final lt = TextEditingController(text: initial.languageTool);
  late final names = TextEditingController(text: initial.names.join('\n'));
  late Settings previous = initial;
  String? error;

  @override
  void dispose() {
    for (final field in [store, hunspell, ollama, lt, names]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> chooseFolder() async {
    final directory = await getDirectoryPath(
      confirmButtonText: 'Выбрать словари',
    );
    if (directory != null) store.text = directory;
  }

  void save() {
    try {
      localEndpoint(ollama.text.trim());
      localEndpoint(lt.text.trim());
      final current = context.read<EditorCubit>().state.settings;
      final settings = Settings(
        model: current.model,
        dark: current.dark,
        vimMode: current.vimMode,
        store: store.text.trim(),
        hunspell: hunspell.text.trim(),
        ollama: ollama.text.trim(),
        languageTool: lt.text.trim(),
        names: List.unmodifiable(
          names.text
              .split(RegExp(r'[,\n]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet(),
        ),
      );
      context.read<EditorCubit>().configure(settings);
      setState(() => error = 'Настройки сохранены');
    } on FormatException catch (failure) {
      setState(() => error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<EditorCubit, EditorState>(
    listenWhen: (before, after) => before.settings != after.settings,
    listener: (_, state) => sync(state.settings),
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: fields(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  error ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: BlocBuilder<ComponentsCubit, ComponentsState>(
                  builder: (context, state) => FilledButton(
                    style: settingsActionStyle(),
                    onPressed: save,
                    child: const Text('Сохранить'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void sync(Settings settings) {
    final fields = [
      (store, previous.store, settings.store),
      (hunspell, previous.hunspell, settings.hunspell),
      (ollama, previous.ollama, settings.ollama),
      (lt, previous.languageTool, settings.languageTool),
      (names, previous.names.join('\n'), settings.names.join('\n')),
    ];
    for (final (controller, oldValue, newValue) in fields) {
      if (controller.text == oldValue && oldValue != newValue) {
        controller.text = newValue;
      }
    }
    previous = settings;
  }

  Widget fields(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Подключение и словари',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: store,
        decoration: InputDecoration(
          labelText: 'Папка dictionaries-v1',
          contentPadding: settingsFieldPadding,
          suffixIcon: IconButton(
            tooltip: 'Выбрать папку',
            onPressed: chooseFolder,
            icon: const Icon(Icons.folder_open),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: hunspell,
        decoration: const InputDecoration(
          labelText: 'Программа Hunspell',
          contentPadding: settingsFieldPadding,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: ollama,
        decoration: const InputDecoration(
          labelText: 'Локальный адрес Ollama',
          contentPadding: settingsFieldPadding,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: lt,
        decoration: const InputDecoration(
          labelText: 'Локальный адрес LanguageTool',
          contentPadding: settingsFieldPadding,
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: BlocBuilder<ComponentsCubit, ComponentsState>(
          builder: (context, state) => OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () => context.read<ComponentsCubit>().refresh(
                    context.read<EditorCubit>().state.settings,
                  ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Проверить подключение'),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('Личный словарь', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text(
        'Имена и термины, которые нужно сохранить. По одному на строку.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: names,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: 'Норвета\nКорректа',
          contentPadding: settingsFieldPadding,
        ),
      ),
    ],
  );
}
