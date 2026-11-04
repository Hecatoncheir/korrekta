import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/checker_repository.dart';
import '../data/draft_store.dart';
import '../domain/check_result.dart';
import '../domain/settings.dart';

class EditorState {
  const EditorState({
    required this.settings,
    this.text = '',
    this.result,
    this.previous,
    this.checking = false,
    this.saved = true,
    this.message,
  });
  final Settings settings;
  final String text;
  final CheckResult? result;
  final String? previous, message;
  final bool checking, saved;

  EditorState copyWith({
    Settings? settings,
    String? text,
    CheckResult? result,
    String? previous,
    bool? checking,
    bool? saved,
    String? message,
    bool clearReview = false,
    bool clearUndo = false,
  }) => EditorState(
    settings: settings ?? this.settings,
    text: text ?? this.text,
    result: clearReview ? null : result ?? this.result,
    previous: clearUndo ? null : previous ?? this.previous,
    checking: checking ?? this.checking,
    saved: saved ?? this.saved,
    message: message,
  );
}

class EditorCubit extends Cubit<EditorState> {
  EditorCubit({
    required this._checker,
    required this._store,
    required SavedDraft draft,
  }) : super(EditorState(settings: draft.settings, text: draft.text));
  final TextChecker _checker;
  final DraftStore _store;
  Timer? _saveTimer;
  Future<void> _pendingSave = Future.value();
  int _revision = 0;

  void edit(String text) {
    if (text == state.text) return;
    _revision++;
    emit(
      state.copyWith(
        text: text,
        clearReview: true,
        clearUndo: true,
        saved: false,
      ),
    );
    _scheduleSave();
  }

  void configure(Settings settings) {
    _revision++;
    emit(state.copyWith(settings: settings, clearReview: true, saved: false));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() {
    final draft = (text: state.text, settings: state.settings);
    final revision = _revision;
    _pendingSave = _pendingSave
        .then((_) => _store.save(draft))
        .then((_) {
          if (!isClosed && revision == _revision) {
            emit(state.copyWith(saved: true, message: state.message));
          }
        })
        .catchError((Object error) {
          if (!isClosed) {
            emit(
              state.copyWith(
                saved: false,
                message: 'Не удалось сохранить черновик. Скопируйте текст или повторите сохранение.',
              ),
            );
          }
        });
    return _pendingSave;
  }

  Future<void> check() async {
    if (state.checking || state.text.trim().isEmpty) return;
    if (state.text.runes.length > 1200) {
      emit(
        state.copyWith(
          message: 'Пока проверяем фрагменты до 1200 знаков. Разделите длинный текст.',
        ),
      );
      return;
    }
    final revision = _revision;
    final snapshot = state.text;
    final settings = state.settings;
    emit(state.copyWith(checking: true, clearReview: true));
    try {
      final result = await _checker.check(snapshot, settings);
      if (isClosed || revision != _revision) return;
      emit(state.copyWith(result: result, message: result.warning));
    } catch (error) {
      if (!isClosed && revision == _revision) {
        emit(state.copyWith(message: checkError(error)));
      }
    } finally {
      if (!isClosed) {
        emit(state.copyWith(checking: false, message: state.message));
      }
    }
  }

  void accept(Map<int, int> choices) {
    final result = state.result;
    if (result == null || choices.isEmpty) return;
    try {
      final next = result.apply(state.text, choices, state.settings.names);
      _revision++;
      emit(
        state.copyWith(
          text: next,
          previous: state.text,
          clearReview: true,
          saved: false,
        ),
      );
      _scheduleSave();
    } on StateError catch (error) {
      emit(
        state.copyWith(clearReview: true, message: error.message.toString()),
      );
    }
  }

  void undo() {
    final previous = state.previous;
    if (previous == null) return;
    _revision++;
    emit(
      state.copyWith(
        text: previous,
        clearReview: true,
        clearUndo: true,
        saved: false,
      ),
    );
    _scheduleSave();
  }

  void dismiss(int index) {
    final result = state.result;
    if (result == null) return;
    emit(
      state.copyWith(
        result: CheckResult(
          result.original,
          result.suggestions.indexed
              .where((item) => item.$1 != index)
              .map((item) => item.$2),
          warning: result.warning,
        ),
        message: state.message,
      ),
    );
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  @override
  Future<void> close() async {
    await flush();
    return super.close();
  }
}

String checkError(Object error) => switch (error) {
  FileSystemException() =>
    'Не найдены словари. Выберите папку dictionaries-v1 в настройках.',
  ProcessException() =>
    'Не удалось запустить Hunspell. Проверьте путь к программе в настройках.',
  SocketException() || TimeoutException() => 'Локальные компоненты не отвечают. Проверьте Ollama и LanguageTool в настройках.',
  FormatException(:final message) => message,
  _ => 'Проверка не завершилась. Проверьте состояние компонентов в настройках и повторите попытку.',
};
