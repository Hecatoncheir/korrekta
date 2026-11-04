import 'dart:convert';
import 'dart:io';

import 'cli.dart' show request, generationOptions;
import 'dictionary_engines.dart';
import 'ensemble.dart';
import 'hunspell_choices.dart';
import 'local_languagetool.dart';
import 'response_contract.dart';
import 'symspell.dart';

const ensembleModel =
    'hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M';

class EnsembleRuntime {
  EnsembleRuntime._(
    this.ru,
    this.en,
    this.symspell,
    this.hunspell,
    this.lt,
    this.endpoint,
  );
  final HunspellPipe ru, en;
  final OpenCorporaDictionary symspell;
  final HunspellDictionary hunspell;
  final LocalLanguageTool lt;
  final Uri endpoint;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static Future<EnsembleRuntime> open({
    String store = 'E:/korrekta/dictionaries-v1',
    String ollama = 'http://127.0.0.1:11435',
    String languageTool = 'http://127.0.0.1:8081',
  }) async {
    final endpoint = Uri.parse(ollama);
    if (endpoint.scheme != 'http' ||
        !['127.0.0.1', 'localhost', '::1'].contains(endpoint.host)) {
      throw const FormatException('Нужен локальный Ollama');
    }
    final lt = LocalLanguageTool(Uri.parse(languageTool));
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
        '$store/native/ucrt64/bin/hunspell.exe',
        '$store/hunspell/ru_RU',
      );
      en = await HunspellPipe.start(
        '$store/native/ucrt64/bin/hunspell.exe',
        '$store/hunspell/en_US',
      );
      return EnsembleRuntime._(
        ru,
        en,
        symspell,
        HunspellDictionary(ru, en, frequencies: frequencies),
        lt,
        endpoint,
      );
    } catch (_) {
      await ru?.close();
      await en?.close();
      lt.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generate(
    String prompt,
    Map<String, dynamic> schema,
    int tokens,
  ) async {
    // Число байтов ограничивает сверху число токенов byte-level BPE.
    // Это не даёт серверу незаметно обрезать начало длинного запроса.
    if (utf8.encode(prompt).length > 8192 - tokens - 32) {
      throw const FormatException('Запрос слишком большой; разделите текст');
    }
    final response = await request(client, endpoint, 'generate', {
      'model': ensembleModel,
      'raw': true,
      'prompt': prompt,
      'format': schema,
      'stream': false,
      'think': false,
      'keep_alive': '10m',
      'options': {
        ...generationOptions(false),
        'num_ctx': 8192,
        'num_predict': tokens,
      },
    }).timeout(const Duration(seconds: 120));
    if (response['done_reason'] != 'stop') {
      throw const FormatException('Незавершённый ответ GigaChat');
    }
    return response;
  }

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
        gigaOutput = giga['output'] as String;
      } else {
        giga = await generate(
          gigaPrompt(proposalPrompt, {'text': text}),
          textResponseSchema,
          1024,
        );
        final parsed = jsonDecode(giga['response'] as String);
        if (parsed is! Map<String, dynamic> ||
            parsed.length != 1 ||
            parsed['text'] is! String) {
          throw const FormatException('Неправильная структура текста GigaChat');
        }
        gigaOutput = parsed['text'] as String;
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
          gigaPrompt(prompt, {'text': text, 'slots': row['slots']}),
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
