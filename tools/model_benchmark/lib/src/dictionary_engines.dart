import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dictionary_checker.dart';
import 'symspell.dart';

class OpenCorporaDictionary implements WordDictionary {
  OpenCorporaDictionary(this.known, this.english, this.index);
  final Set<String> known;
  final Set<String> english;
  final SymSpellIndex index;

  @override
  Future<bool> knows(String word, String language) async =>
      (language == 'ru' ? known : english).contains(dictionaryKey(word));

  @override
  Future<List<String>> suggest(String word) async => index.lookup(word);
}

class HunspellReply {
  const HunspellReply(this.correct, this.suggestions);
  final bool correct;
  final List<String> suggestions;
}

HunspellReply parseHunspellReply(List<String> lines) {
  if (lines.length != 1) throw const FormatException('Неполный ответ Hunspell');
  final line = lines.single;
  if (line.startsWith('*') || line.startsWith('+') || line.startsWith('-')) {
    return const HunspellReply(true, []);
  }
  if (line.startsWith('#')) return const HunspellReply(false, []);
  if (!line.startsWith('&') || !line.contains(':')) {
    throw FormatException('Неизвестный ответ Hunspell: $line');
  }
  return HunspellReply(
    false,
    line
        .substring(line.indexOf(':') + 1)
        .split(',')
        .map((word) => word.trim().toLowerCase())
        .toList(),
  );
}

class HunspellPipe {
  HunspellPipe._(this.process, this.lines);
  final Process process;
  final StreamIterator<String> lines;
  String? _lastWord;
  HunspellReply? _lastReply;

  static Future<HunspellPipe> start(
    String executable,
    String dictionary,
  ) async {
    final dictionaryFile = File(dictionary);
    final process = await Process.start(executable, [
      '-a',
      '-i',
      'UTF-8',
      '-d',
      dictionaryFile.uri.pathSegments.last,
    ], workingDirectory: dictionaryFile.parent.path);
    process.stderr.drain<void>();
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final ready = await lines.moveNext().timeout(const Duration(seconds: 30));
    if (!ready || !lines.current.contains('Hunspell')) {
      process.kill();
      throw const FormatException('Hunspell не прислал заголовок');
    }
    return HunspellPipe._(process, lines);
  }

  Future<HunspellReply> lookup(String word) async {
    if (_lastWord == word) return _lastReply!;
    process.stdin.writeln('^$word');
    await process.stdin.flush();
    final response = <String>[];
    while (await lines.moveNext().timeout(const Duration(seconds: 15))) {
      if (lines.current.isEmpty) {
        final result = parseHunspellReply(response);
        _lastWord = word;
        _lastReply = result;
        return result;
      }
      response.add(lines.current);
    }
    throw const FormatException('Hunspell завершился до конца ответа');
  }

  Future<void> close() async {
    await process.stdin.close();
    process.kill();
    await lines.cancel();
    await process.exitCode;
  }
}

class HunspellDictionary implements WordDictionary {
  HunspellDictionary(this.russian, this.english, {this.frequencies});
  final HunspellPipe russian;
  final HunspellPipe english;
  final Map<String, int>? frequencies;

  @override
  Future<bool> knows(String word, String language) async {
    if (!RegExp(r'^[a-zа-яё]+$').hasMatch(word)) return false;
    return (await (language == 'ru' ? russian : english).lookup(word)).correct;
  }

  @override
  Future<List<String>> suggest(String word) async {
    final suggestions = [...(await russian.lookup(word)).suggestions];
    if (frequencies == null) return suggestions;
    final order = {
      for (var i = 0; i < suggestions.length; i++) suggestions[i]: i,
    };
    suggestions.sort((a, b) {
      final distance = spellingDistance(
        dictionaryKey(word),
        dictionaryKey(a),
      ).compareTo(spellingDistance(dictionaryKey(word), dictionaryKey(b)));
      if (distance != 0) return distance;
      final frequency = (frequencies![b] ?? 0).compareTo(frequencies![a] ?? 0);
      return frequency != 0 ? frequency : order[a]!.compareTo(order[b]!);
    });
    return suggestions;
  }
}
