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
      if (incoming.uri.path == '/api/generate') {
        await _record(id, body, bytes, response.statusCode);
      }
    } catch (error) {
      incoming.response.statusCode = 502;
      incoming.response.write(jsonEncode({'error': error.toString()}));
    } finally {
      await incoming.response.close();
    }
  }

  Future<void> _record(
    String? id,
    List<int> body,
    List<int> response,
    int status,
  ) async {
    final request = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    final row = <String, Object?>{
      'sequence': sequence++,
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
