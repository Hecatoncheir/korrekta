import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'quality_data.dart';

class QualityProxy {
  QualityProxy(this.backend, this.log);
  final Uri backend;
  final QualityLog log;
  final _client = http.Client();
  late final HttpServer _server;
  String? currentCase;
  String? forcedContent;
  int sequence = 0;
  final observations = <Map<String, Object?>>[];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) => unawaited(_forward(request)));
  }

  String get endpoint => 'http://127.0.0.1:${_server.port}';

  Future<void> _forward(HttpRequest incoming) async {
    final id = currentCase;
    try {
      final body = await incoming.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );
      if (await _inject(incoming, id, body)) return;
      final target = backend.replace(
        path: incoming.uri.path,
        query: incoming.uri.hasQuery ? incoming.uri.query : null,
      );
      final request = http.Request(incoming.method, target)
        ..followRedirects = false;
      request.bodyBytes = body;
      if (incoming.headers.contentType case final type?) {
        request.headers['content-type'] = type.toString();
      }
      final response = await _client.send(request);
      final bytes = <int>[];
      incoming.response.statusCode = response.statusCode;
      incoming.response.headers.contentType = ContentType.json;
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        incoming.response.add(chunk);
      }
      if (['/api/generate', '/api/chat'].contains(incoming.uri.path)) {
        await _record(id, body, bytes, response.statusCode, incoming.uri.path);
      }
    } catch (error) {
      incoming.response.statusCode = 502;
      incoming.response.write(jsonEncode({'error': error.toString()}));
    } finally {
      await incoming.response.close();
    }
  }

  Future<bool> _inject(HttpRequest incoming, String? id, List<int> body) async {
    final content = forcedContent;
    if (id == null || content == null || incoming.uri.path != '/api/chat') {
      return false;
    }
    forcedContent = null;
    final request = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    final bytes = utf8.encode(
      jsonEncode({
        'model': request['model'],
        'done': true,
        'done_reason': 'stop',
        'message': {'role': 'assistant', 'content': content},
      }),
    );
    incoming.response.headers.contentType = ContentType.json;
    incoming.response.add(bytes);
    await _record(id, body, bytes, 200, incoming.uri.path, injected: true);
    return true;
  }

  Future<void> _record(
    String? id,
    List<int> body,
    List<int> response,
    int status,
    String api, {
    bool injected = false,
  }) async {
    final request = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    final row = <String, Object?>{
      'sequence': sequence++,
      'api': api,
      'injected': injected,
      'case': id,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'model': request['model'],
      'raw': request['raw'],
      'options': request['options'],
      'requestSha256': sha256.convert(body).toString(),
      'requestBody': utf8.decode(body),
      'responseStatus': status,
      'responseBody': utf8.decode(response, allowMalformed: true),
    };
    observations.add(row);
    await log.append(row);
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close();
  }
}
