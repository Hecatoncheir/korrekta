import 'dart:convert';
import 'dart:io';

import 'correction_response.dart';
import 'desktop_generation.dart';
import 'desktop_request.dart' show desktopRequest;
import 'ensemble_runtime.dart' show ensembleModel;
import 'dictionary_engines.dart';
import 'ensemble.dart';
import 'hunspell_choices.dart';
import 'desktop_languagetool.dart';
import 'response_contract.dart';
import 'symspell.dart';

class DesktopRuntime {
  DesktopRuntime._(
    this.ru,
    this.en,
    this.symspell,
    this.hunspell,
    this.lt,
    this.endpoint,
    this.model,
  );
  final HunspellPipe ru, en;
  final OpenCorporaDictionary symspell;
  final HunspellDictionary hunspell;
  final DesktopLanguageTool lt;
  final Uri endpoint;
  final String model;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static Future<DesktopRuntime> open({
    String store = 'E:/korrekta/dictionaries-v1',
    String ollama = 'http://127.0.0.1:11435',
    String languageTool = 'http://127.0.0.1:8081',
    String model = ensembleModel,
    String? hunspellExecutable,
  }) async {
    final endpoint = Uri.parse(ollama);
    if (endpoint.scheme != 'http' ||
        !['127.0.0.1', 'localhost', '::1'].contains(endpoint.host)) {
      throw const FormatException('Нужен локальный Ollama');
    }
    final lt = DesktopLanguageTool(Uri.parse(languageTool));
    HunspellPipe? ru, en;
    try {
      final known = (await File('$store/known-ru.txt').readAsLines()).toSet();
      final frequencies = await _frequencies('$store/frequency-ru.tsv');
      final english = await _frequencies('$store/frequency-en.tsv');
      final symspell = OpenCorporaDictionary(
        known,
        english.keys.toSet(),
        SymSpellIndex(frequencies),
      );
      ru = await HunspellPipe.start(
        hunspellExecutable ?? defaultHunspell(store),
        '$store/hunspell/ru_RU',
      );
      en = await HunspellPipe.start(
        hunspellExecutable ?? defaultHunspell(store),
        '$store/hunspell/en_US',
      );
      return DesktopRuntime._(
        ru,
        en,
        symspell,
        HunspellDictionary(ru, en, frequencies: frequencies),
        lt,
        endpoint,
        model,
      );
    } catch (_) {
      await ru?.close();
      await en?.close();
      lt.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generate(
    String instruction,
    Map<String, dynamic> payload,
    Map<String, dynamic> schema,
    int tokens,
  ) async {
    final request = generationRequest(
      model,
      instruction,
      payload,
      schema,
      tokens,
    );
    final prompt =
        request.body['prompt'] as String? ??
        '$instruction${jsonEncode(payload)}';
    // Число байтов ограничивает сверху число токенов byte-level BPE.
    // Для chat служебный префикс добавляет сервер; truncate/shift=false
    // запрещают ему обрезать запрос или сдвигать контекст при генерации.
    if (utf8.encode(prompt).length > 8192 - tokens - 32) {
      throw const FormatException('Запрос слишком большой; разделите текст');
    }
    final response = await desktopRequest(
      client,
      endpoint,
      request.api,
      request.body,
    ).timeout(const Duration(seconds: 120));
    if (response['done'] != true || response['done_reason'] != 'stop') {
      throw const FormatException('Незавершённый ответ GigaChat');
    }
    return {...response, 'response': generationContent(response, request.api)};
  }

  static String defaultHunspell(String store) =>
      Platform.isWindows ? '$store/native/ucrt64/bin/hunspell.exe' : 'hunspell';

  Future<Map<String, dynamic>> collect(
    String text,
    String proposalPrompt, {
    List<String> names = const [],
    Map<String, dynamic>? cachedGiga,
  }) async {
    if (text.runes.length > 1200) {
      throw const FormatException(
        'Разделите текст на фрагменты до 1200 символов',
      );
    }
    final timer = Stopwatch()..start();
    final ltResponse = await lt.check(text);
    final hs = await collectHunspellChoices(
      text,
      SharedLexicon(hunspell, symspell),
      names: names,
    );
    final ss = await collectHunspellChoices(
      text,
      SharedLexicon(symspell, hunspell),
      names: names,
    );
    Map<String, dynamic> giga = {};
    String gigaOutput;
    String? error;
    try {
      if (cachedGiga != null) {
        if (cachedGiga['text'] != text ||
            cachedGiga['schema_valid'] != true ||
            cachedGiga['done_reason'] != 'stop' ||
            cachedGiga.containsKey('error')) {
          throw const FormatException('Неполный сохранённый ответ GigaChat');
        }
        giga = cachedGiga;
        gigaOutput = validateCorrectionText(text, giga['output'] as String);
      } else {
        giga = await generate(
          proposalPrompt,
          {'text': text},
          textResponseSchema,
          1024,
        );
        gigaOutput = readCorrectionText(text, giga['response'] as String);
      }
    } catch (failure) {
      error = failure.toString();
      giga = {...giga, 'error': error};
      gigaOutput = text;
    }
    final pool = buildEnsemble(
      text,
      hunspell: hs,
      symspell: ss,
      matches: ltResponse['matches'] as List<dynamic>,
      gigaOutput: gigaOutput,
      names: names,
    );
    timer.stop();
    return {
      ...pool.payload(),
      'rejected': pool.rejected,
      'hunspell_slots': hs.map((s) => s.toJson()).toList(),
      'symspell_slots': ss.map((s) => s.toJson()).toList(),
      'lt_response': ltResponse,
      'giga_response': giga,
      'giga_output': gigaOutput,
      'cached_giga': cachedGiga != null,
      'personal_names': names,
      'collection_seconds': timer.elapsedMicroseconds / 1e6,
      'collection_error': ?error,
    };
  }

  Future<Map<String, dynamic>> select(
    Map<String, dynamic> row,
    String prompt,
  ) async {
    final text = row['text'] as String;
    final slots = (row['slots'] as List<dynamic>)
        .map((s) => WordChoices.fromJson(s as Map<String, dynamic>))
        .toList();
    final timer = Stopwatch()..start();
    Map<String, dynamic>? response;
    try {
      var choices = <int>[];
      if (slots.isNotEmpty) {
        response = await generate(
          prompt,
          {'text': text, 'slots': row['slots']},
          choicesSchema(slots),
          512,
        );
        choices = parseChoices(response['response'] as String, slots.length);
      }
      final output = selectEnsembleChoices(text, slots, choices).output;
      return {
        'output': output,
        'choices': choices,
        'selection_response': ?response,
        'selection_seconds': timer.elapsedMicroseconds / 1e6,
      };
    } catch (error) {
      return {
        'output': text,
        'selection_error': error.toString(),
        'selection_response': ?response,
        'selection_seconds': timer.elapsedMicroseconds / 1e6,
      };
    }
  }

  Future<void> close() async {
    client.close(force: true);
    lt.close();
    await ru.close();
    await en.close();
  }
}

Future<Map<String, int>> _frequencies(String path) async => {
  for (final line in await File(path).readAsLines())
    line.split('\t')[0]: int.parse(line.split('\t')[1]),
};
