import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:korrekta_model_benchmark/src/dictionary_engines.dart';
import 'package:korrekta_model_benchmark/src/hunspell_choices.dart';
import 'package:korrekta_model_benchmark/src/scoring.dart';
import 'package:korrekta_model_benchmark/src/symspell.dart';

List<int> frequencyChoices(List<WordChoices> slots, Map<String, int> counts) =>
    [for (final slot in slots) bestOption(slot, counts)];

int bestOption(WordChoices slot, Map<String, int> counts) {
  final indexes = List.generate(slot.options.length - 1, (i) => i + 1);
  indexes.sort((a, b) {
    final distance =
        spellingDistance(
          dictionaryKey(slot.original),
          dictionaryKey(slot.options[a]),
        ).compareTo(
          spellingDistance(
            dictionaryKey(slot.original),
            dictionaryKey(slot.options[b]),
          ),
        );
    if (distance != 0) return distance;
    final frequency = (counts[slot.options[b]] ?? 0).compareTo(
      counts[slot.options[a]] ?? 0,
    );
    return frequency != 0 ? frequency : a.compareTo(b);
  });
  return indexes.first;
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('protocol', mandatory: true)
    ..addOption('output', mandatory: true);
  HunspellPipe? ru, en;
  IOSink? sink;
  try {
    final options = parser.parse(arguments);
    final file = File(options.option('protocol')!).absolute;
    final workspace = file.parent.parent.parent;
    final protocol = jsonDecode(await file.readAsString()) as JsonMap;
    final output = File(options.option('output')!);
    if (output.existsSync()) throw const FormatException('Файл уже существует');
    const store = 'E:/korrekta/dictionaries-v1';
    ru = await HunspellPipe.start(
      '$store/native/ucrt64/bin/hunspell.exe',
      '$store/hunspell/ru_RU',
    );
    en = await HunspellPipe.start(
      '$store/native/ucrt64/bin/hunspell.exe',
      '$store/hunspell/en_US',
    );
    final dictionary = HunspellDictionary(ru, en);
    final counts = <String, int>{
      for (final line in await File('$store/frequency-ru.tsv').readAsLines())
        line.split('\t')[0]: int.parse(line.split('\t')[1]),
    };
    await output.parent.create(recursive: true);
    sink = output.openWrite();
    var total = 0;
    for (final run in (protocol['runs'] as List<dynamic>).cast<JsonMap>()) {
      final names = run['names_file'] == null
          ? <String>[]
          : (jsonDecode(
              await File.fromUri(
                workspace.uri.resolve(run['names_file'] as String),
              ).readAsString(),
            ) as List<dynamic>).cast<String>();
      final cases =
          (await File.fromUri(workspace.uri.resolve(run['data'] as String))
                  .readAsLines())
              .map((line) => jsonDecode(line) as JsonMap)
              .where((row) => row['split'] == run['split'])
              .toList();
      if (cases.length != run['count']) {
        throw const FormatException('Другой набор');
      }
      for (final layout in [false, true]) {
        for (final item in cases) {
          final text = item['text'] as String;
          final timer = Stopwatch()..start();
          final slots = await collectHunspellChoices(
            text,
            dictionary,
            layout: layout,
            names: names,
          );
          timer.stop();
          final first = List<int>.filled(slots.length, 1);
          final frequency = frequencyChoices(slots, counts);
          sink.writeln(
            jsonEncode({
              'run': run['id'],
              'mode': layout ? 'layout' : 'spelling',
              'id': item['id'],
              'category': item['category'],
              'text': text,
              'expected': item['edits'],
              'slots': slots.map((slot) => slot.toJson()).toList(),
              'hunspell_seconds': timer.elapsedMicroseconds / 1e6,
              'first_output': selectChoices(text, slots, first).output,
              'frequency_output': selectChoices(text, slots, frequency).output,
              'personal_names': names,
            }),
          );
          total++;
        }
        await sink.flush();
        stdout.writeln(
          'Варианты: ${run['id']} / ${layout ? 'layout' : 'spelling'}',
        );
      }
    }
    stdout.writeln('Подготовлено строк: $total');
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 64;
  } finally {
    await sink?.close();
    await ru?.close();
    await en?.close();
  }
}
