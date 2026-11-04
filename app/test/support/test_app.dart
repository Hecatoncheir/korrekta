import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/update_api.dart';
import 'package:korrekta/data/update_download.dart';
import 'package:korrekta/data/update_installer.dart';
import 'package:korrekta/main.dart';
import 'package:korrekta/ui/editor_cubit.dart';
import 'package:korrekta/ui/update_cubit.dart';

Widget testApp(EditorCubit editor) {
  final client = MockClient((_) async => http.Response('[]', 200));
  final downloads = UpdateDownload(client, Directory.systemTemp);
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: editor),
      BlocProvider(
        create: (_) => UpdateCubit(
          api: UpdateApi(client),
          downloads: downloads,
          installer: UpdateInstaller(downloads),
          version: Future.value('0.1.0'),
        ),
      ),
    ],
    child: const KorrektaApp(),
  );
}
