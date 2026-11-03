import 'dart:io';

import 'package:korrekta_model_benchmark/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
