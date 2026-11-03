import 'dart:io';

import 'package:korrekta_model_benchmark/src/languagetool_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLanguageTool(arguments);
}
