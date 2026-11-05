import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:korrekta/data/checker_repository.dart';
import 'package:korrekta/data/draft_store.dart';
import 'package:korrekta/data/local_translator.dart';
import 'package:korrekta/data/runtime/runtime_manager.dart';
import 'package:korrekta/data/runtime/setup_asset.dart';
import 'package:korrekta/data/translation_store.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/setup.dart';
import 'package:korrekta/main.dart';
import 'package:korrekta/ui/components_cubit.dart';
import 'package:korrekta/ui/editor_cubit.dart';
import 'package:korrekta/ui/translation_cubit.dart';
import 'package:korrekta/ui/update_cubit.dart';
import 'package:path/path.dart' as p;

import 'quality_data.dart';
import 'quality_proxy.dart';
import 'quality_environment.dart';

import 'package:korrekta/data/generation_store.dart';
import 'package:korrekta/data/local_generator.dart';
import 'package:korrekta/ui/generation_cubit.dart';

class QualityFixture {
  QualityFixture(this.root, this.output, this.runtimeDirectory);
  final String root, runtimeDirectory;
  final Directory output;
  late final RuntimeManager runtime;
  late final QualityProxy proxy;
  late final EditorCubit editor;
  late final TranslationCubit translation;
  late final GenerationCubit generation;
  late final UpdateCubit updates;
  late ComponentsCubit components;

  Future<void> prepare() async {
    await output.create(recursive: true);
    final state = Directory(p.join(root, 'work', 'app-quality-profile'));
    await state.create(recursive: true);
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/components.json'),
    ) as Map<String, dynamic>;
    runtime = RuntimeManager(
      Directory(runtimeDirectory),
      SetupCatalog(catalog, SetupCatalog.currentPlatform()),
    );
    final settings = await runtime.prepare(
      Settings.defaults(output.path),
      SetupTask(),
      (progress) => stdout.writeln(progress.label),
      loadModel: false,
    );
    proxy = QualityProxy(
      Uri.parse(settings.ollama),
      QualityLog(File(p.join(output.path, 'wire.jsonl'))),
    );
    await proxy.start();
    await qualityEnvironment(settings.ollama, output);
    final prompt = await rootBundle.loadString('assets/proposal.txt');
    editor = EditorCubit(
      checker: LocalChecker(prompt),
      store: FileDraftStore(File(p.join(state.path, 'draft.json'))),
      draft: (text: '', settings: settings.copyWith(ollama: proxy.endpoint)),
    );
    translation = TranslationCubit(
      translator: LocalTranslator(),
      store: FileTranslationStore(File(p.join(state.path, 'translation.json'))),
    );
    generation = GenerationCubit(
      generator: LocalGenerator(),
      store: FileGenerationStore(File(p.join(state.path, 'generation.json'))),
    );
    updates = UpdateCubit.live(
      Directory(p.join(state.path, 'updates')),
      editor.flush,
    );
  }

  Widget get app => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: editor),
      BlocProvider.value(value: translation),
      BlocProvider.value(value: generation),
      BlocProvider.value(value: updates),
    ],
    child: KorrektaApp(setup: runtime),
  );

  void bind(BuildContext context) =>
      components = context.read<ComponentsCubit>();

  Future<void> close() async {
    await components.shutdown();
    await editor.close();
    await translation.close();
    await generation.close();
    await updates.close();
    await proxy.close();
  }
}
