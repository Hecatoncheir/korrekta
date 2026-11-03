import 'dart:io';

import 'package:korrekta_model_benchmark/src/text_comparison.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runTextComparison(arguments);
}
