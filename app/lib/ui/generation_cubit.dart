import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/generation_store.dart';
import '../data/local_generator.dart';
import '../domain/generation.dart';
import '../domain/settings.dart';

class GenerationState {
  const GenerationState({
    this.draft = const GenerationDraft(),
    this.generating = false,
    this.saved = true,
    this.saveFailed = false,
    this.message,
  });
  final GenerationDraft draft;
  final bool generating, saved, saveFailed;
  final String? message;
  bool get ready =>
      draft.prompt.trim().isNotEmpty &&
      draft.prompt.runes.length <= generationLimit;

  GenerationState copyWith({
    GenerationDraft? draft,
    bool? generating,
    bool? saved,
    bool? saveFailed,
    String? message,
    bool clearMessage = false,
  }) => GenerationState(
    draft: draft ?? this.draft,
    generating: generating ?? this.generating,
    saved: saved ?? this.saved,
    saveFailed: saveFailed ?? this.saveFailed,
    message: clearMessage ? null : message ?? this.message,
  );
}

class GenerationCubit extends Cubit<GenerationState> {
  GenerationCubit({
    required this._generator,
    required this._store,
    GenerationDraft draft = const GenerationDraft(),
  }) : super(GenerationState(draft: draft));
  final TextGenerator _generator;
  final GenerationStore _store;
  Timer? _timer;
  Future<void> _pendingSave = Future.value();
  int _request = 0, _revision = 0;

  void edit(String prompt) {
    if (prompt == state.draft.prompt) return;
    cancel();
    _change(GenerationDraft(prompt: prompt));
  }

  void clear() {
    cancel();
    _change(const GenerationDraft());
  }

  void _change(GenerationDraft draft) {
    _revision++;
    emit(
      state.copyWith(
        draft: draft,
        generating: false,
        saved: false,
        clearMessage: true,
      ),
    );
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _save);
  }

  void cancel() {
    _request++;
    _generator.cancel();
    if (state.generating) emit(state.copyWith(generating: false));
  }

  void modelChanged() {
    if (!state.generating) return;
    cancel();
    emit(
      state.copyWith(message: 'Настройки изменены. Запустите генерацию снова.'),
    );
  }

  Future<void> generate(Settings settings) async {
    if (state.generating || !state.ready) return;
    final request = ++_request;
    emit(state.copyWith(generating: true, clearMessage: true));
    try {
      final (:text, :limited) = await _generator.generate(
        state.draft.prompt,
        settings,
      );
      if (isClosed || request != _request) return;
      _change(state.draft.copyWith(output: text, limited: limited));
    } catch (error) {
      if (isClosed || request != _request) return;
      emit(state.copyWith(generating: false, message: generationError(error)));
    }
  }

  Future<void> _save() {
    final draft = state.draft;
    final revision = _revision;
    _pendingSave = _pendingSave
        .then((_) => _store.save(draft))
        .then((_) {
          if (!isClosed && revision == _revision) {
            emit(state.copyWith(saved: true, saveFailed: false));
          }
        })
        .catchError((Object error) {
          if (!isClosed) emit(state.copyWith(saved: false, saveFailed: true));
        });
    return _pendingSave;
  }

  Future<void> flush() async {
    _timer?.cancel();
    await _save();
  }

  @override
  Future<void> close() async {
    cancel();
    await flush();
    return super.close();
  }
}

String? generationMessage(GenerationState state) {
  if (state.saveFailed) {
    return 'Не удалось сохранить текст. Скопируйте его перед закрытием.';
  }
  if (state.draft.prompt.runes.length > generationLimit) {
    return 'Запрос — до $generationLimit знаков. Сократите его и повторите попытку.';
  }
  if (state.message case final message?) return message;
  if (state.draft.limited) {
    return 'Модель достигла предела ответа. Текст может быть неполным. Уточните объём в запросе.';
  }
  return null;
}
