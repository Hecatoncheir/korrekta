import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:korrekta/domain/settings.dart';
import 'package:path/path.dart' as p;

import 'quality_data.dart';

Future<void> qualityEnvironment(String endpoint, Directory output) async {
  final client = http.Client();
  try {
    final base = localEndpoint(endpoint);
    final version = jsonDecode(
      (await client.get(base.resolve('/api/version'))).body,
    ) as Map<String, dynamic>;
    final tags = jsonDecode(
      (await client.get(base.resolve('/api/tags'))).body,
    ) as Map<String, dynamic>;
    final models =
        (tags['models'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where(
              (item) =>
                  LocalModel.values.any((model) => model.id == item['name']),
            )
            .map(
              (item) => {
                'name': item['name'],
                'digest': item['digest'],
                'bytes': item['size'],
                'details': item['details'],
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    final metadata = <String, Object?>{
      'ollama': version['version'],
      'models': models,
      'languageTool': '6.8',
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
    };
    final file = File(p.join(output.path, 'environment.json'));
    final content = '${const JsonEncoder.withIndent('  ').convert(metadata)}\n';
    if (await file.exists() && await file.readAsString() != content) {
      throw StateError('Среда изменилась между частями прогона');
    }
    await file.writeAsString(content, flush: true);
    await QualityLog(File(p.join(output.path, 'attempts.jsonl'))).append({
      'utc': DateTime.now().toUtc().toIso8601String(),
      'backend': endpoint,
      'pid': pid,
    });
  } finally {
    client.close();
  }
}
