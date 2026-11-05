import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final target = File('../benchmarks/app-quality/protocol-v1.json');
  if (await target.exists()) throw StateError('Протокол уже зафиксирован');
  final sources = <String, String>{};
  for (final folder in [
    Directory('lib'),
    Directory('../tools/model_benchmark/lib'),
  ]) {
    await for (final file
        in folder
            .list(recursive: true)
            .where((file) => file is File)
            .cast<File>()) {
      final name = p.posix.joinAll(
        p.split(p.normalize(p.join('app', file.path))),
      );
      sources[name] = await digest(file);
    }
  }
  for (final name in ['assets/proposal.txt', 'assets/components.json']) {
    sources[p.posix.join('app', name)] = await digest(File(name));
  }
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final dataset = File('../benchmarks/app-quality/cases-v1.jsonl');
  final protocol = {
    'version': 1,
    'frozenUtc': DateTime.now().toUtc().toIso8601String(),
    'productionCommit': (commit.stdout as String).trim(),
    'datasetSha256': await digest(dataset),
    'sourceSha256': sources,
    'primary': {
      'uniqueTexts': 140,
      'errors': 60,
      'controls': 80,
      'personalDictionary': 'empty',
    },
    'secondary': {
      'repeatedTexts': 20,
      'errors': 10,
      'controls': 10,
      'personalDictionary': 'fixed glossary in dataset',
    },
    'models': [
      'hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M',
      'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
    ],
    'context': 8192,
    'selection': 'inflections',
    'seed': 5112026,
    'path': 'Native Windows Flutter → real TextField → check button → EditorCubit → LocalChecker → all production engines → rendered cards → accept recommended → undo',
    'wire': 'Transparent loopback HTTP proxy records original generation request/response and verifies model ID. Gold and protected annotations never enter inference.',
    'metrics': [
      'exact clean error texts /60',
      'changed correct controls /80',
      'incomplete checks counted separately and never clean',
      'annotated names/code/emoji lost',
      'whitespace-run and Markdown-marker preservation',
      'visible optional cards on correct controls',
      'UI apply/undo invariants',
      'full request duration including production dictionary loading',
    ],
    'rules': [
      'No prompt, engine, thresholds or gold changes after first new inference.',
      'No best-of-N: completed JSONL rows, including errors, are never rerun on resume.',
      'Partial-dictionary results are a paired side experiment, not 20 independent new texts.',
      'Same model order and shuffled case order are fixed. Model loading/warmup is excluded from per-case timing.',
      'A semantically acceptable alternative outside frozen gold is documented in manual review without rewriting exact-match scores.',
    ],
    'acceptance': 'Zero changed correct controls and zero protected/formatting violations are the safety target. Report all misses and incomplete checks. Do not replace the stored quality baseline on this study alone.',
    'limits': 'New author-created Russian challenge set, not an external representative corpus. Names include intentional pseudonyms and identifiers. Native app is built from unchanged v0.1.6 production sources in an isolated test profile; this is not installed-package/update/OS-IME acceptance. Translation is outside this run.',
  };
  await target.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(protocol)}\n',
    flush: true,
  );
  stdout.writeln(
    jsonEncode({
      'datasetSha256': protocol['datasetSha256'],
      'sourceFiles': sources.length,
      'protocolSha256': await digest(target),
    }),
  );
}

Future<String> digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
