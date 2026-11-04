import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/ensemble.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('text-file', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('names')
    ..addOption('store', defaultsTo: 'E:/korrekta/dictionaries-v1')
    ..addOption('ollama', defaultsTo: 'http://127.0.0.1:11435')
    ..addOption('lt', defaultsTo: 'http://127.0.0.1:8081')
    ..addOption(
      'prompt',
      defaultsTo: '../../benchmarks/gigachat-prompts/text-json.txt',
    );
  EnsembleRuntime? runtime;
  try {
    final options = parser.parse(arguments);
    final destination = File(options.option('output')!);
    if (destination.existsSync()) {
      throw const FormatException('Файл результата уже существует');
    }
    final source = File(options.option('text-file')!);
    if (destination.absolute.path.toLowerCase() ==
        source.absolute.path.toLowerCase()) {
      throw const FormatException('Результат должен быть отдельным файлом');
    }
    final names = options.option('names') == null
        ? <String>[]
        : (jsonDecode(
            await File(options.option('names')!).readAsString(),
          ) as List<dynamic>).cast<String>();
    final text = await source.readAsString();
    final prompt = await File(options.option('prompt')!).readAsString();
    runtime = await EnsembleRuntime.open(
      store: options.option('store')!,
      ollama: options.option('ollama')!,
      languageTool: options.option('lt')!,
    );
    final collected = await runtime.collect(text, prompt, names: names);
    final slots = (collected['slots'] as List<dynamic>)
        .map((s) => WordChoices.fromJson(s as Map<String, dynamic>))
        .toList();
    final proposal = selectEnsembleChoices(
      text,
      slots,
      List.filled(slots.length, 1),
    );
    final complete = !collected.containsKey('collection_error');
    final result = {
      'status': !complete
          ? 'incomplete'
          : (slots.isEmpty ? 'no_suggestions' : 'review_required'),
      'original': text,
      'proposed_text': proposal.output,
      'automatic_application': false,
      'note': 'Предварительный вариант. Проверьте правки перед принятием. Отсутствие подсказок не гарантирует отсутствие ошибок.',
      'details': collected,
    };
    await destination.parent.create(recursive: true);
    await destination.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    stdout.writeln(
      complete
          ? 'Вариант подготовлен для просмотра'
          : 'Проверка неполная; подробности в результате',
    );
    if (!complete) exitCode = 2;
  } catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } finally {
    await runtime?.close();
  }
}
