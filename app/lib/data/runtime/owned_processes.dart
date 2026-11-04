import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/setup.dart';

class OwnedProcesses {
  OwnedProcesses(this.logs);
  final Directory logs;
  final _services = <String, _Service>{};
  bool alive(String name) => _services[name]?.alive == true;

  Future<void> start(
    String name,
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    await stop(name);
    await logs.create(recursive: true);
    final process = await Process.start(
      executable,
      args,
      environment: environment,
    );
    final log = File(p.join(logs.path, '$name.log')).openWrite();
    final service = _Service(process, log);
    _services[name] = service;
    process.stdout.listen(service.record);
    process.stderr.listen(service.record);
    service.finished = process.exitCode.then((_) async {
      service.alive = false;
      await log.close();
    });
    unawaited(service.finished);
  }

  Future<void> stop(String name) async {
    final service = _services.remove(name);
    if (service == null) return;
    if (!service.alive) return service.finished;
    if (Platform.isWindows) {
      await Process.run('taskkill.exe', [
        '/PID',
        '${service.process.pid}',
        '/T',
        '/F',
      ]);
    } else {
      service.process.kill(ProcessSignal.sigterm);
    }
    try {
      await service.finished.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      service.process.kill(ProcessSignal.sigkill);
      await service.finished;
    }
  }

  Future<void> close() async {
    for (final name in _services.keys.toList().reversed) {
      await stop(name);
    }
  }

  String logPath(String name) => p.join(logs.path, '$name.log');
}

class _Service {
  _Service(this.process, this.log);
  final Process process;
  final IOSink log;
  bool alive = true;
  late final Future<void> finished;
  int _recorded = 0;
  void record(List<int> bytes) {
    if (!alive || _recorded >= 256 * 1024) return;
    final limited = bytes.take(256 * 1024 - _recorded).toList();
    _recorded += limited.length;
    log.add(limited);
  }
}

Future<String?> findProgram(
  List<String> candidates,
  String version,
  List<String> args,
) async {
  for (final candidate
      in candidates.where((value) => value.isNotEmpty).toSet()) {
    try {
      final result = await Process.run(
        candidate,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0 &&
          '${result.stdout}\n${result.stderr}'.contains(version)) {
        return candidate;
      }
    } on Exception {
      continue;
    }
  }
  return null;
}

Future<String> availableEndpoint(String requested) async {
  final uri = Uri.parse(requested);
  ServerSocket socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, uri.port);
  } on SocketException {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  }
  final port = socket.port;
  await socket.close();
  return 'http://127.0.0.1:$port';
}

Future<void> waitForService({
  required String name,
  required Future<bool> Function() ready,
  required OwnedProcesses processes,
  required SetupTask task,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(minutes: 2)) {
    task.check();
    if (await ready()) return;
    if (!processes.alive(name)) {
      throw SetupFailure(
        'Не удалось запустить $name. Подробности: ${processes.logPath(name)}. Повторите подготовку.',
      );
    }
    await task.pause(const Duration(milliseconds: 500));
  }
  throw SetupFailure(
    '$name запускается слишком долго. Повторите подготовку. Журнал: ${processes.logPath(name)}',
  );
}
