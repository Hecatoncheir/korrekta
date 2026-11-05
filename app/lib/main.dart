import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/checker_repository.dart';
import 'data/runtime/runtime_manager.dart';
import 'data/runtime/setup_asset.dart';
import 'data/draft_store.dart';
import 'domain/settings.dart';
import 'ui/editor_cubit.dart';
import 'ui/editor_page.dart';
import 'ui/theme.dart';
import 'ui/window_chrome.dart';
import 'ui/window_session.dart';
import 'ui/update_cubit.dart';
import 'ui/components_cubit.dart';
import 'ui/navigation_cubit.dart';
import 'data/local_components.dart';
import 'data/local_translator.dart';
import 'data/translation_store.dart';
import 'ui/translation_cubit.dart';
import 'data/generation_store.dart';
import 'data/local_generator.dart';
import 'ui/generation_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationSupportDirectory();
    final store = FileDraftStore(File(p.join(directory.path, 'draft.json')));
    final draft = await store.load(Settings.defaults(directory.path));
    final prompt = await rootBundle.loadString('assets/proposal.txt');
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/components.json'),
    ) as Map<String, dynamic>;
    final runtime = RuntimeManager(
      Directory(p.join(directory.path, 'runtime')),
      SetupCatalog(catalog, SetupCatalog.currentPlatform()),
    );
    final session = await WindowSession.restore(directory.path);
    final editor = EditorCubit(
      checker: LocalChecker(prompt),
      store: store,
      draft: draft,
    );
    final translationStore = FileTranslationStore(
      File(p.join(directory.path, 'translation.json')),
    );
    final translation = TranslationCubit(
      translator: LocalTranslator(),
      store: translationStore,
      draft: await translationStore.load(),
    );
    final generationStore = FileGenerationStore(
      File(p.join(directory.path, 'generation.json')),
    );
    final generation = GenerationCubit(
      generator: LocalGenerator(),
      store: generationStore,
      draft: await generationStore.load(),
    );
    final updates = UpdateCubit.live(
      Directory(p.join(directory.path, 'updates')),
      () async {
        if (editor.state.checking) throw StateError('Проверка ещё выполняется');
        if (translation.state.translating) {
          throw StateError('Перевод ещё выполняется');
        }
        if (generation.state.generating) {
          throw StateError('Генерация ещё выполняется');
        }
        await Future.wait([
          editor.flush(),
          translation.flush(),
          generation.flush(),
        ]);
        if (!editor.state.saved ||
            !translation.state.saved ||
            !generation.state.saved) {
          throw StateError('Текст не сохранён');
        }
        await session.flush();
        await runtime.close();
      },
    );
    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => editor),
          BlocProvider(create: (_) => translation),
          BlocProvider(create: (_) => generation),
          BlocProvider(create: (_) => updates..check()),
        ],
        child: KorrektaApp(session: session, setup: runtime),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: gruvbox(true),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: SelectableText(
                'Не удалось открыть черновик или настройки. Файлы не изменены.\nПроверьте папку данных приложения и права доступа.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KorrektaApp extends StatelessWidget {
  const KorrektaApp({super.key, this.session, this.setup});
  final WindowSession? session;
  final ComponentSetup? setup;

  ComponentsCubit components(BuildContext context) {
    final editor = context.read<EditorCubit>();
    final cubit = ComponentsCubit(
      LocalComponents(),
      setup: setup,
      onReady: (resolved) {
        editor.configure(
          editor.state.settings.copyWith(
            store: resolved.store,
            hunspell: resolved.hunspell,
            ollama: resolved.ollama,
            languageTool: resolved.languageTool,
          ),
        );
      },
    );
    if (setup != null) cubit.prepare(editor.state.settings);
    return cubit;
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => NavigationCubit()),
      BlocProvider(create: components, lazy: false),
    ],
    child: BlocListener<EditorCubit, EditorState>(
      listenWhen: (before, after) =>
          before.settings.runtimeKey != after.settings.runtimeKey,
      listener: (context, state) {
        context.read<TranslationCubit>().modelChanged();
        context.read<GenerationCubit>().modelChanged();
        context.read<ComponentsCubit>().prepare(state.settings);
      },
      child: BlocBuilder<EditorCubit, EditorState>(
        buildWhen: (before, after) =>
            before.settings.dark != after.settings.dark,
        builder: (context, state) => MaterialApp(
          title: 'Корректа',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: gruvbox(false),
          darkTheme: gruvbox(true),
          themeMode: state.settings.dark ? ThemeMode.dark : ThemeMode.light,
          themeAnimationDuration:
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 250),
          home: EditorPage(session: session),
          builder: (_, child) => WindowChrome(child: child!),
        ),
      ),
    ),
  );
}
