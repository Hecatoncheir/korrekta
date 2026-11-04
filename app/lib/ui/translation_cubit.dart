import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../data/local_translator.dart';
import '../data/translation_store.dart';
import '../domain/settings.dart';
import '../domain/translation.dart';

class TranslationState {
  const TranslationState({
    this.draft = const TranslationDraft(),
    this.translating = false,
    this.saved = true,
    this.saveFailed = false,
    this.message,
  });
  final TranslationDraft draft;
  final bool translating, saved, saveFailed;
  final String? message;
  bool get ready =>
      draft.text.trim().isNotEmpty &&
      draft.text.runes.length <= translationLimit &&
      draft.from != draft.to;

  TranslationState copyWith({
    TranslationDraft? draft,
    bool? translating,
    bool? saved,
    bool? saveFailed,
    String? message,
    bool clearMessage = false,
  }) => TranslationState(
    draft: draft ?? this.draft,
    translating: translating ?? this.translating,
    saved: saved ?? this.saved,
    saveFailed: saveFailed ?? this.saveFailed,
    message: clearMessage ? null : message ?? this.message,
  );
}

class TranslationCubit extends Cubit<TranslationState> {
  TranslationCubit({
    required this._translator,
    required this._store,
    TranslationDraft draft = const TranslationDraft(),
  }) : super(TranslationState(draft: draft));
  final TextTranslator _translator;
  final TranslationStore _store;
  Timer? _timer;
  Future<void> _pendingSave = Future.value();
  int _request = 0, _revision = 0;

  void edit(String text) {
    if (text == state.draft.text) return;
    cancel();
    _change(state.draft.copyWith(text: text, output: ''));
  }

  void languages({TranslationLanguage? from, TranslationLanguage? to}) {
    if ((from ?? state.draft.from, to ?? state.draft.to) ==
        (state.draft.from, state.draft.to)) {
      return;
    }
    cancel();
    _change(state.draft.copyWith(from: from, to: to, output: ''));
  }

  void swap() {
    cancel();
    final draft = state.draft;
    _change(
      TranslationDraft(
        text: draft.output.isEmpty ? draft.text : draft.output,
        output: draft.output.isEmpty ? '' : draft.text,
        from: draft.to,
        to: draft.from,
      ),
    );
  }

  void clear() {
    cancel();
    _change(state.draft.copyWith(text: '', output: ''));
  }

  void _change(TranslationDraft draft) {
    _revision++;
    emit(
      state.copyWith(
        draft: draft,
        translating: false,
        saved: false,
        clearMessage: true,
      ),
    );
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _save);
  }

  void cancel() {
    _request++;
    _translator.cancel();
    if (state.translating) emit(state.copyWith(translating: false));
  }

  void modelChanged() {
    if (!state.translating) return;
    cancel();
    emit(
      state.copyWith(message: 'Настройки изменены. Запустите перевод снова.'),
    );
  }

  Future<void> translate(Settings settings) async {
    if (state.translating || !state.ready) return;
    final request = ++_request;
    emit(state.copyWith(translating: true, clearMessage: true));
    try {
      final output = await _translator.translate(state.draft, settings);
      if (isClosed || request != _request) return;
      _change(state.draft.copyWith(output: output));
    } catch (error) {
      if (isClosed || request != _request) return;
      emit(
        state.copyWith(translating: false, message: translationError(error)),
      );
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

String translationError(Object error) => switch (error) {
  SocketException() || TimeoutException() || http.ClientException() => 'Ollama не отвечает. Проверьте подключение в настройках и повторите перевод.',
  FormatException(:final message) => message,
  _ => 'Не удалось перевести текст. Повторите попытку.',
};
