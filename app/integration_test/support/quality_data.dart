import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class QualityCase {
  QualityCase(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get text => json['text'] as String;
  String get profile => json['profile'] as String;
  List<String> get names => (json['names'] as List<dynamic>).cast<String>();
}

Future<List<QualityCase>> readCases(String root, bool pilot) async {
  if (pilot) {
    return [
      QualityCase({
        'id': 'pilot',
        'profile': 'empty',
        'group': 'pilot',
        'kind': 'error',
        'text': 'Мне нравиться читать.',
        'expected': ['Мне нравится читать.'],
        'protected': <String>[],
        'names': <String>[],
      }),
      QualityCase({
        'id': 'pilot-after-undo',
        'profile': 'empty',
        'group': 'pilot',
        'kind': 'control',
        'text': 'Норвета пишет в Flutter.\n  `final x = 1;` 🙂',
        'expected': ['Норвета пишет в Flutter.\n  `final x = 1;` 🙂'],
        'protected': ['Норвета', '`final x = 1;`', '🙂'],
        'names': <String>[],
      }),
    ];
  }
  final file = File(
    p.join(root, 'benchmarks', 'app-quality', 'cases-v1.jsonl'),
  );
  return (await file.readAsLines())
      .where((line) => line.isNotEmpty)
      .map((line) => QualityCase(jsonDecode(line) as Map<String, dynamic>))
      .toList();
}

class QualityLog {
  QualityLog(this.file);
  final File file;

  Future<Set<String>> completed() async {
    if (!await file.exists()) return {};
    return (await file.readAsLines())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => (jsonDecode(line) as Map<String, dynamic>)['id'] as String,
        )
        .toSet();
  }

  Future<void> append(Map<String, Object?> row) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(row)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

Map<String, Object> score(QualityCase item, String output, bool complete) {
  final expected = (item.json['expected'] as List<dynamic>).cast<String>();
  final protected = (item.json['protected'] as List<dynamic>).cast<String>();
  final lost = protected
      .where(
        (fragment) =>
            occurrences(item.text, fragment) != occurrences(output, fragment),
      )
      .toList();
  final whitespace =
      whitespaceParts(item.text).join('\u0000') ==
      whitespaceParts(output).join('\u0000');
  final markup =
      markupParts(item.text).join('\u0000') ==
      markupParts(output).join('\u0000');
  return {
    'clean': complete && expected.contains(output),
    'changed': output != item.text,
    'falseControl': item.json['kind'] == 'control' && output != item.text,
    'protectedLost': lost,
    'whitespacePreserved': whitespace,
    'markupPreserved': markup,
    'graphemes': output.characters.length,
  };
}

List<String> whitespaceParts(String text) =>
    RegExp(r'\s+').allMatches(text).map((match) => match.group(0)!).toList();
List<String> markupParts(String text) => RegExp(
  r'^[ \t]*(?:#{1,6}|[-*+]|\|)|```|\*\*',
  multiLine: true,
).allMatches(text).map((match) => match.group(0)!).toList();
int occurrences(String text, String fragment) =>
    RegExp(RegExp.escape(fragment)).allMatches(text).length;

Future<void> verifyQualityFreeze(
  String root, {
  String study = 'app-quality',
}) async {
  final folder = p.join(root, 'benchmarks', study);
  final protocol = jsonDecode(
    await File(p.join(folder, 'protocol-v1.json')).readAsString(),
  ) as Map<String, dynamic>;
  final data = File(
    p.join(root, 'benchmarks', 'app-quality', 'cases-v1.jsonl'),
  );
  if (await fileHash(data) != protocol['datasetSha256']) {
    throw StateError('Набор изменён после фиксации');
  }
  final sources = (protocol['sourceSha256'] as Map<String, dynamic>)
      .cast<String, String>();
  for (final entry in sources.entries) {
    final file = File(p.joinAll([root, ...p.posix.split(entry.key)]));
    if (await fileHash(file) != entry.value) {
      throw StateError('Изменён рабочий источник: ${entry.key}');
    }
  }
}

Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
