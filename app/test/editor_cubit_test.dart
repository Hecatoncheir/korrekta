import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/checker_repository.dart';
import 'package:korrekta/data/draft_store.dart';
import 'package:korrekta/domain/check_result.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/editor_cubit.dart';
import 'package:korrekta_model_benchmark/ensemble.dart';

class MemoryStore implements DraftStore {
  SavedDraft? draft;
  bool fail = false;
  @override
  Future<void> save(SavedDraft draft) async {
    if (fail) throw StateError('Нет места');
    this.draft = draft;
  }
}

class FakeChecker implements TextChecker {
  final requests = <({String text, Settings settings})>[];
  Completer<CheckResult>? pending;
  @override
  Future<CheckResult> check(String text, Settings settings) async {
    requests.add((text: text, settings: settings));
    return pending?.future ??
        CheckResult(text, [
          Suggestion(
            WordChoices(4, 'нравиться', ['нравиться', 'нравится']),
            1,
            ['gigachat'],
          ),
        ]);
  }
}

EditorCubit makeCubit(FakeChecker checker, MemoryStore store) => EditorCubit(
  checker: checker,
  store: store,
  draft: (text: 'Мне нравиться читать.', settings: const Settings()),
);

void main() {
  test('Выбранная модель передаётся проверке и сохраняется', () async {
    final checker = FakeChecker();
    final store = MemoryStore();
    final cubit = makeCubit(checker, store);
    await cubit.check();
    cubit.configure(cubit.state.settings.copyWith(model: LocalModel.quality));
    expect(cubit.state.result, isNull);
    await cubit.check();
    expect(checker.requests.map((r) => r.settings.model), [
      LocalModel.balanced,
      LocalModel.quality,
    ]);
    await cubit.close();
    expect(store.draft?.settings.model, LocalModel.quality);
  });

  test('Ответ старого текста и старой модели отбрасывается', () async {
    final checker = FakeChecker()..pending = Completer();
    final cubit = makeCubit(checker, MemoryStore());
    final request = cubit.check();
    cubit.edit('Новый текст');
    cubit.configure(cubit.state.settings.copyWith(model: LocalModel.quality));
    checker.pending!.complete(CheckResult('Мне нравиться читать.', []));
    await request;
    expect(cubit.state.result, isNull);
    expect(cubit.state.text, 'Новый текст');
    expect(cubit.state.checking, isFalse);
    await cubit.close();
  });

  test('Принятие и отмена; ручной ввод снимает подсказки и отмену', () async {
    final cubit = makeCubit(FakeChecker(), MemoryStore());
    await cubit.check();
    cubit.accept(cubit.state.result!.recommended);
    expect(cubit.state.text, 'Мне нравится читать.');
    cubit.undo();
    expect(cubit.state.text, 'Мне нравиться читать.');
    await cubit.check();
    cubit.edit('Мне нравится писать.');
    cubit.accept({0: 1});
    expect(cubit.state.text, 'Мне нравится писать.');
    expect(cubit.state.previous, isNull);
    await cubit.close();
  });

  test(
    'Ошибка сохранения видима, повторная запись восстанавливается',
    () async {
      final store = MemoryStore()..fail = true;
      final cubit = makeCubit(FakeChecker(), store);
      cubit.edit('Не терять');
      await cubit.flush();
      expect(cubit.state.saved, isFalse);
      expect(cubit.state.message, contains('сохранить'));
      store.fail = false;
      await cubit.flush();
      expect(cubit.state.saved, isTrue);
      expect(store.draft?.text, 'Не терять');
      await cubit.close();
    },
  );

  test('Защита имени, оформления и UTF-16 после эмодзи', () {
    const text = '🙂 Норвета: мне нравиться читать.\r\n  `код`';
    final start = text.indexOf('нравиться');
    final result = CheckResult(text, [
      Suggestion(
        WordChoices(start, 'нравиться', ['нравиться', 'нравится']),
        1,
        [],
      ),
    ]);
    expect(
      result.apply(text, {0: 1}, ['Норвета']),
      text.replaceFirst('нравиться', 'нравится'),
    );
    expect(() => result.apply('$text!', {0: 1}, []), throwsStateError);
    final name = CheckResult(text, [
      Suggestion(WordChoices(3, 'Норвета', ['Норвета', 'Норвегия']), 1, []),
    ]);
    expect(() => name.apply(text, {0: 1}, ['Норвета']), throwsStateError);
  });
}
