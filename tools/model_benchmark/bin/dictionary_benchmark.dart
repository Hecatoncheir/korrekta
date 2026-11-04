import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/dictionary_checker.dart';
import 'package:korrekta_model_benchmark/src/dictionary_engines.dart';
import 'package:korrekta_model_benchmark/src/scoring.dart';
import 'package:korrekta_model_benchmark/src/symspell.dart';
import 'package:korrekta_model_benchmark/src/text_scoring.dart';

Future<Map<String, int>> frequencies(String path) async => {
  for (final line in await File(path).readAsLines())
    line.split('\t')[0]: int.parse(line.split('\t')[1]),
};

JsonMap record(
  JsonMap item,
  DictionaryResult result,
  double seconds,
  String type,
) {
  final expected = item['edits'] as List<dynamic>;
  final text = item['text'] as String;
  return {
    'type': type,
    'id': item['id'],
    'category': item['category'],
    'text': text,
    'expected': expected,
    'output': result.output,
    'seconds': seconds,
    'decisions': result.decisions,
    'edits': [
      for (final edit in result.edits)
        {
          'start': edit.start,
          'original': edit.original,
          'replacement': edit.replacement,
        },
    ],
    ...scoreText(text, expected, result.output),
  };
}

Future<void> evaluate(
  JsonMap run,
  JsonMap profile,
  WordDictionary engine,
  String outputDirectory,
  JsonMap metadata,
  List<String> names,
) async {
  final output = File('$outputDirectory/${run['id']}-${profile['id']}.jsonl');
  if (output.existsSync()) {
    final last = jsonDecode((await output.readAsLines()).last) as JsonMap;
    if (last['type'] != 'summary') {
      throw StateError('Незавершённый файл: ${output.path}');
    }
    return;
  }
  final cases = (await File(run['data'] as String).readAsLines())
      .map((line) => jsonDecode(line) as JsonMap)
      .where((item) => item['split'] == run['split'])
      .toList();
  if (cases.length != run['count']) throw StateError('Другой размер набора');
  final sink = output.openWrite();
  try {
    sink.writeln(
      jsonEncode({
        'type': 'metadata',
        ...metadata,
        'dataset': run,
        'profile': profile,
        'personal_names': names,
      }),
    );
    Future<void> check(JsonMap item, String type) async {
      final timer = Stopwatch()..start();
      final result = await checkDictionaryText(
        item['text'] as String,
        engine,
        layout: profile['layout'] as bool,
        names: names,
      );
      timer.stop();
      sink.writeln(
        jsonEncode(record(item, result, timer.elapsedMicroseconds / 1e6, type)),
      );
      await sink.flush();
    }

    await check(cases.first, 'cold_start');
    for (final item in cases) {
      await check(item, 'case');
    }
    sink.writeln(
      jsonEncode({
        'type': 'summary',
        'completed': true,
        'count': cases.length,
        'dart_rss_bytes': ProcessInfo.currentRss,
      }),
    );
    stdout.writeln('${run['id']} / ${profile['id']}: ${cases.length}');
  } finally {
    await sink.close();
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('protocol', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('store', defaultsTo: 'E:/korrekta/dictionaries-v1');
  HunspellPipe? ru, en;
  try {
    final options = parser.parse(arguments);
    final protocol = jsonDecode(
      await File(options.option('protocol')!).readAsString(),
    ) as JsonMap;
    final workspace = File(options.option('protocol')!)
        .absolute
        .parent
        .parent
        .parent;
    final store = options.option('store')!;
    final timer = Stopwatch()..start();
    final known = (await File('$store/known-ru.txt').readAsLines()).toSet();
    final ruFrequency = await frequencies('$store/frequency-ru.tsv');
    final enFrequency = await frequencies('$store/frequency-en.tsv');
    final symspell = OpenCorporaDictionary(
      known,
      enFrequency.keys.toSet(),
      SymSpellIndex(ruFrequency),
    );
    timer.stop();
    final symspellLoad = timer.elapsedMicroseconds / 1e6;
    timer
      ..reset()
      ..start();
    ru = await HunspellPipe.start(
      '$store/native/ucrt64/bin/hunspell.exe',
      '$store/hunspell/ru_RU',
    );
    en = await HunspellPipe.start(
      '$store/native/ucrt64/bin/hunspell.exe',
      '$store/hunspell/en_US',
    );
    timer.stop();
    final engines = <String, WordDictionary>{
      'symspell': symspell,
      'hunspell': HunspellDictionary(ru, en),
      'hunspell-frequency': HunspellDictionary(
        ru,
        en,
        frequencies: ruFrequency,
      ),
    };
    final metadata = <String, dynamic>{
      'version': 'dictionary-v1',
      'time': DateTime.now().toUtc().toIso8601String(),
      'dictionary_manifest': jsonDecode(
        await File('$store/manifest.json').readAsString(),
      ),
      'symspell_load_seconds': symspellLoad,
      'hunspell_load_seconds': timer.elapsedMicroseconds / 1e6,
      'dart_rss_bytes': ProcessInfo.currentRss,
      'native_pids': [ru.process.pid, en.process.pid],
      'memory_note': 'RSS процесса Dart; память двух отдельных процессов Hunspell не включена',
    };
    await Directory(options.option('output')!).create(recursive: true);
    for (final run in (protocol['runs'] as List<dynamic>).cast<JsonMap>()) {
      final resolved = <String, dynamic>{
        ...run,
        'data': File.fromUri(workspace.uri.resolve(run['data'] as String)).path,
      };
      final names = run['names_file'] == null
          ? <String>[]
          : (jsonDecode(
              await File.fromUri(
                workspace.uri.resolve(run['names_file'] as String),
              ).readAsString(),
            ) as List<dynamic>).cast<String>();
      for (final profile
          in (protocol['profiles'] as List<dynamic>).cast<JsonMap>()) {
        await evaluate(
          resolved,
          profile,
          engines[profile['engine']]!,
          options.option('output')!,
          metadata,
          names,
        );
      }
    }
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 64;
  } finally {
    await ru?.close();
    await en?.close();
  }
}
