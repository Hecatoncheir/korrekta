import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/local_components.dart';
import '../data/runtime/runtime_manager.dart';
import '../domain/settings.dart';
import '../domain/setup.dart';

class ComponentsState {
  const ComponentsState({
    this.status,
    this.busy = false,
    this.ready = false,
    this.progress,
    this.message,
    this.stopped = false,
  });
  final ComponentStatus? status;
  final bool busy, ready, stopped;
  final SetupProgress? progress;
  final String? message;
}

class ComponentsCubit extends Cubit<ComponentsState> {
  ComponentsCubit(this.components, {this.setup, this.onReady})
    : super(ComponentsState(ready: setup == null));
  final LocalComponents components;
  final ComponentSetup? setup;
  final void Function(Settings)? onReady;
  SetupTask? _task;
  Settings? _desired, _lastSettings;
  Object? _resolvedKey;
  Future<void> _pending = Future.value();
  Future<void>? _shutdown;
  Timer? _monitor;
  bool _closing = false;

  Future<void> prepare(Settings settings) {
    if (_closing || settings.runtimeKey == _resolvedKey && state.ready) {
      return Future.value();
    }
    if (setup == null) return refresh(settings);
    _desired = settings;
    _lastSettings = settings;
    _task?.cancel();
    emit(
      const ComponentsState(
        busy: true,
        progress: (label: 'Проверяем компоненты', completed: null, total: null),
      ),
    );
    return _pending = _pending.then((_) => _prepareLatest());
  }

  Future<void> _prepareLatest() async {
    final settings = _desired;
    _desired = null;
    if (settings == null || _closing) return;
    final task = SetupTask();
    _task = task;
    try {
      final resolved = await setup!.prepare(settings, task, (progress) {
        if (!_closing && !task.cancelled) {
          emit(ComponentsState(busy: true, progress: progress));
        }
      });
      task.check();
      if (_closing) return;
      _resolvedKey = resolved.runtimeKey;
      _lastSettings = resolved;
      emit(
        const ComponentsState(
          ready: true,
          status: (ollama: true, model: true, languageTool: true),
        ),
      );
      onReady?.call(resolved);
      _monitor ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _health(),
      );
    } catch (error) {
      if (!_closing && _desired == null) emit(_failure(error, task));
    } finally {
      if (identical(_task, task)) _task = null;
    }
  }

  ComponentsState _failure(Object error, SetupTask task) {
    if (task.cancelled || error is SetupCancelled) {
      return const ComponentsState(
        stopped: true,
        message: 'Подготовка остановлена. Загруженные файлы сохранены.',
      );
    }
    return ComponentsState(
      message: switch (error) {
        SetupFailure(:final message) => message,
        FileSystemException() => 'Не удалось записать компоненты. Проверьте свободное место и права папки приложения, затем повторите.',
        ProcessException() => 'Не удалось запустить компонент. Проверьте ограничения антивируса и права запуска, затем повторите.',
        TimeoutException() => 'Компонент не ответил вовремя. Повторите подготовку. Если модель не загружается в память, выберите 10В в настройках.',
        _ => 'Не удалось подготовить компоненты. Проверьте интернет и доступную память, затем повторите. Загрузка продолжится с сохранённого места.',
      },
    );
  }

  void cancel() {
    _desired = null;
    _task?.cancel();
    if (!state.busy) return;
    if (_task == null) {
      emit(
        const ComponentsState(
          stopped: true,
          message: 'Подготовка остановлена. Загруженные файлы сохранены.',
        ),
      );
      return;
    }
    emit(
      const ComponentsState(
        busy: true,
        progress: (
          label: 'Останавливаем подготовку…',
          completed: null,
          total: null,
        ),
      ),
    );
  }

  Future<void> refresh(Settings settings) async {
    if (state.busy || _closing) return;
    final status = await components.status(settings);
    if (_closing || state.busy) return;
    if (setup != null &&
        !(status.ollama && status.model && status.languageTool)) {
      _resolvedKey = null;
      return prepare(settings);
    }
    emit(ComponentsState(status: status, ready: state.ready));
  }

  Future<void> _health() async {
    final settings = _lastSettings;
    if (settings == null || !state.ready || state.busy || _closing) return;
    await refresh(settings);
  }

  Future<void> shutdown() => _shutdown ??= _stop();
  Future<void> _stop() async {
    _closing = true;
    _monitor?.cancel();
    _desired = null;
    _task?.cancel();
    await _pending;
    components.close();
    await setup?.close();
  }

  @override
  Future<void> close() async {
    await shutdown();
    return super.close();
  }
}
