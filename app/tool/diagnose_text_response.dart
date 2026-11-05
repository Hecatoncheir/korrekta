import 'dart:convert';
import 'dart:io';

import 'package:korrekta/data/runtime/runtime_manager.dart';
import 'package:korrekta/data/runtime/setup_asset.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/setup.dart';

import 'evaluate_app_quality.dart' show rows;

Future<void> main(List<String> args) async {
  final output = Directory(
    '../benchmarks/results/2026-11-05/text-response-fix/diagnosis',
  );
  await output.create(recursive: true);
  final catalog = jsonDecode(
    await File('assets/components.json').readAsString(),
  ) as Map<String, dynamic>;
  final runtime = RuntimeManager(
    Directory('E:/korrekta/app-quality-runtime'),
    SetupCatalog(catalog, SetupCatalog.currentPlatform()),
  );
  final client = HttpClient();
  try {
    final settings = await runtime.prepare(
      Settings.defaults(output.path).copyWith(model: LocalModel.balanced),
      SetupTask(),
      (progress) => stdout.writeln(progress.label),
    );
    final wire = await rows(
      File('../benchmarks/results/2026-11-05/app-quality/wire.jsonl'),
    );
    final ids = args.where((arg) => !arg.startsWith('--')).toList();
    final wanted = ids.isEmpty
        ? [
            'control-technical-18',
            'error-format-19',
            'error-names-6',
            'control-names-3',
          ]
        : ids;
    for (final id in wanted) {
      final original = wire.singleWhere(
        (row) => row['case'] == id && row['model'] == LocalModel.balanced.id,
      );
      await diagnose(
        client,
        settings.ollama,
        original,
        output,
        templates: args.contains('--templates'),
      );
    }
  } finally {
    client.close(force: true);
    await runtime.close();
  }
}

Future<void> diagnose(
  HttpClient client,
  String endpoint,
  Map<String, dynamic> original,
  Directory output, {
  required bool templates,
}) async {
  final variants = templates
      ? ['official31', 'chat']
      : ['schema', 'json', 'unconstrained'];
  for (final variant in variants) {
    final body = await variantBody(original, variant, templates);
    final request = await client.postUrl(
      Uri.parse(endpoint)
          .resolve(variant == 'chat' ? '/api/chat' : '/api/generate'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(minutes: 3));
    final raw = await response.transform(utf8.decoder).join();
    final result = jsonDecode(raw) as Map<String, dynamic>;
    final row = {
      'case': original['case'],
      'variant': variant,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'request': body,
      'responseStatus': response.statusCode,
      'response': result,
    };
    await File(
      '${output.path}/wire.jsonl',
    ).writeAsString('${jsonEncode(row)}\n', mode: FileMode.append, flush: true);
    stdout.writeln(
      jsonEncode({
        'case': original['case'],
        'variant': variant,
        'content': result['response'] ?? result['message'],
        'done': result['done_reason'],
      }),
    );
  }
}

Future<Map<String, dynamic>> variantBody(
  Map<String, dynamic> original,
  String variant,
  bool templates,
) async {
  final body =
      jsonDecode(original['requestBody'] as String) as Map<String, dynamic>;
  if (variant == 'json') body['format'] = 'json';
  if (variant == 'unconstrained') body.remove('format');
  if (templates) await changeTemplate(body, variant);
  return body;
}

Future<void> changeTemplate(Map<String, dynamic> body, String variant) async {
  final prompt = body['prompt'] as String;
  const user = '<|message_sep|>user<|role_sep|>';
  const functions = '<|message_sep|>available functions<|role_sep|>';
  final system = prompt.substring(3, prompt.indexOf(user));
  final payload = prompt.substring(
    prompt.indexOf(user) + user.length,
    prompt.indexOf(functions),
  );
  if (variant == 'chat') {
    body.remove('raw');
    body.remove('prompt');
    body['messages'] = [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ];
    return;
  }
  final template = await File(
    '../benchmarks/text-response-fix/gigachat31-chat-template.jinja',
  ).readAsString();
  final developer = RegExp(r'\{%- set DEVSYSTEM -%\}([\s\S]*?)\{%- endset -%\}')
      .firstMatch(template)!
      .group(1)!
      .trim();
  body['prompt'] =
      '<s>developer system<|role_sep|>\n$developer<|message_sep|>\n\n'
      'system<|role_sep|>\n$system<|message_sep|>\n\n'
      'user<|role_sep|>\n$payload<|message_sep|>\n\nassistant<|role_sep|>\n';
}
