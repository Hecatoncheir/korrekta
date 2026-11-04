import 'dart:async';

class SetupFailure implements Exception {
  const SetupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class SetupCancelled implements Exception {
  const SetupCancelled();
}

class SetupTask {
  bool _cancelled = false;
  final _callbacks = <void Function()>{};
  bool get cancelled => _cancelled;

  void check() {
    if (_cancelled) throw const SetupCancelled();
  }

  void Function() onCancel(void Function() callback) {
    if (_cancelled) callback();
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  void cancel() {
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }

  Future<void> pause(Duration duration) async {
    check();
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    final remove = onCancel(() {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    remove();
    check();
  }
}

typedef SetupProgress = ({String label, int? completed, int? total});
typedef SetupReporter = void Function(SetupProgress progress);
