import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/local_components.dart';
import '../domain/settings.dart';
import 'components_cubit.dart';
import 'editor_cubit.dart';

Future<void> openSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider.value(
    value: context.read<EditorCubit>(),
    child: BlocProvider(
      create: (_) =>
          ComponentsCubit(LocalComponents())
            ..refresh(context.read<EditorCubit>().state.settings),
      child: const SettingsDialog(),
    ),
  ),
);

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 600,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Настройки',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const ModelPicker(),
              const SizedBox(height: 16),
              const ComponentPanel(),
              const Divider(height: 32),
              const ConnectionFields(),
            ],
          ),
        ),
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
        context.read<ComponentsCubit>().refresh(settings);
      },
      child: BlocBuilder<ComponentsCubit, ComponentsState>(
        builder: (context, components) => Column(
          children: [
            for (final model in LocalModel.values)
              RadioListTile<LocalModel>(
                value: model,
                enabled: !components.busy,
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
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ComponentsCubit, ComponentsState>(
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => context.read<ComponentsCubit>().refresh(settings),
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить подключение'),
              ),
              FilledButton.icon(
                onPressed: state.busy || status?.ollama != true
                    ? null
                    : () => context.read<ComponentsCubit>().download(settings),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Скачать модель'),
              ),
            ],
          ),
          if (state.busy)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(value: state.progress?.fraction),
            ),
          if (state.progress case (:final fraction?, status: _))
            Text('Загрузка модели: ${(fraction * 100).round()}%'),
          if (state.message case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message),
            ),
          const SizedBox(height: 12),
          const Text(
            'Запустите установленные Ollama и LanguageTool. Словари и Hunspell настраиваются ниже. Модели скачиваются в папку Ollama (OLLAMA_MODELS).',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://ollama.com/download'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Установить Ollama'),
            ),
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
      context.read<ComponentsCubit>().refresh(settings);
      setState(() => error = 'Настройки сохранены');
    } on FormatException catch (failure) {
      setState(() => error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
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
        decoration: const InputDecoration(labelText: 'Программа Hunspell'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: ollama,
        decoration: const InputDecoration(labelText: 'Локальный адрес Ollama'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: lt,
        decoration: const InputDecoration(
          labelText: 'Локальный адрес LanguageTool',
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
        decoration: const InputDecoration(hintText: 'Норвета\nКорректа'),
      ),
      const SizedBox(height: 16),
      if (error case final message?)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(message),
        ),
      BlocBuilder<ComponentsCubit, ComponentsState>(
        builder: (context, state) => FilledButton(
          onPressed: state.busy ? null : save,
          child: const Text('Сохранить'),
        ),
      ),
    ],
  );
}
