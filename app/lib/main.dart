import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/checker_repository.dart';
import 'data/draft_store.dart';
import 'domain/settings.dart';
import 'ui/editor_cubit.dart';
import 'ui/editor_page.dart';
import 'ui/theme.dart';
import 'ui/window_chrome.dart';
import 'ui/window_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationSupportDirectory();
    final store = FileDraftStore(File(p.join(directory.path, 'draft.json')));
    final draft = await store.load(Settings.defaults(directory.path));
    final prompt = await rootBundle.loadString('assets/proposal.txt');
    final session = await WindowSession.restore(directory.path);
    runApp(
      BlocProvider(
        create: (_) => EditorCubit(
          checker: LocalChecker(prompt),
          store: store,
          draft: draft,
        ),
        child: KorrektaApp(session: session),
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
  const KorrektaApp({super.key, this.session});
  final WindowSession? session;
  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    buildWhen: (before, after) => before.settings.dark != after.settings.dark,
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
  );
}
