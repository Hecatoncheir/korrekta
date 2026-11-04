import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/local_translator.dart';
import 'package:korrekta/data/translation_store.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/translation.dart';
import 'package:korrekta/ui/translation_cubit.dart';

import 'support/translation_fakes.dart';

void main() {
  test('Перевод отправляется выбранной модели локально, языки и оформление сохраняются в запросе', () async {
    for (final model in LocalModel.values) {
      final translator = LocalTranslator(
        createClient: () => MockClient((request) async {
          expect(request.url.toString(), 'http://127.0.0.1:11434/api/chat');
          expect(request.followRedirects, isFalse);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], model.id);
          expect(body['stream'], isFalse);
          final messages = body['messages'] as List<dynamic>;
          final message = messages.last['content'] as String;
          expect(message, contains('Русский'));
          expect(message, contains('Английский'));
          expect(message, contains(jsonEncode('Привет!\r\n  Flutter 🙂')));
          return http.Response(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {
                'content': jsonEncode({
                  'translation': 'Hello!\r\n  Flutter 🙂',
                }),
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(
        await translator.translate(
          const TranslationDraft(text: 'Привет!\r\n  Flutter 🙂'),
          Settings(model: model),
        ),
        'Hello!\r\n  Flutter 🙂',
      );
    }
  });

  test(
    'Внешний адрес, пустой, повреждённый и обрезанный ответ не принимаются',
    () async {
      final translator = LocalTranslator(
        createClient: () =>
            MockClient((_) async => throw StateError('Не должен быть вызван')),
      );
      await expectLater(
        translator.translate(
          const TranslationDraft(text: 'Текст'),
          const Settings(ollama: 'https://example.org'),
        ),
        throwsFormatException,
      );
      for (final response in [
        {'done_reason': 'length'},
        {
          'done': false,
          'message': {'content': '{"translation":"partial"}'},
        },
        {
          'done': true,
          'message': {'content': '{"translation":"   "}'},
        },
        {
          'done': true,
          'message': {'content': 'not-json'},
        },
      ]) {
        expect(() => readTranslation(response), throwsFormatException);
      }
    },
  );

  test(
    'Смена текста, языка, модели и отмена отклоняют запоздавший перевод',
    () async {
      final translator = FakeTranslator();
      final cubit = TranslationCubit(
        translator: translator,
        store: MemoryTranslationStore(),
      );
      for (final change in <void Function()>[
        () => cubit.edit('Другой текст'),
        () => cubit.languages(to: TranslationLanguage.german),
        cubit.modelChanged,
        cubit.cancel,
      ]) {
        cubit.edit('Начальный текст');
        translator.pending = Completer();
        final request = cubit.translate(
          const Settings(model: LocalModel.balanced),
        );
        expect(cubit.state.translating, isTrue);
        change();
        translator.pending!.complete('Устаревший перевод');
        await request;
        expect(cubit.state.draft.output, isEmpty);
        expect(cubit.state.translating, isFalse);
      }
      await cubit.close();
    },
  );

  test(
    'Перевод, обмен языков и текст сохраняются; сбой записи можно исправить',
    () async {
      final translator = FakeTranslator();
      final store = MemoryTranslationStore();
      final cubit = TranslationCubit(translator: translator, store: store);
      cubit.edit('Привет!');
      await cubit.translate(const Settings(model: LocalModel.balanced));
      expect(translator.requests.single.settings.model, LocalModel.balanced);
      expect(cubit.state.draft.output, 'Hello!');
      cubit.swap();
      expect(cubit.state.draft.from, TranslationLanguage.english);
      expect(cubit.state.draft.to, TranslationLanguage.russian);
      expect(cubit.state.draft.text, 'Hello!');
      expect(cubit.state.draft.output, 'Привет!');
      store.fail = true;
      await cubit.flush();
      expect(cubit.state.saveFailed, isTrue);
      expect(cubit.state.saved, isFalse);
      store.fail = false;
      await cubit.flush();
      expect(cubit.state.saved, isTrue);
      expect(cubit.state.saveFailed, isFalse);
      expect(store.draft!.output, 'Привет!');
      await cubit.close();
    },
  );

  test(
    'Пустой текст, одинаковые языки и превышение лимита не отправляются модели',
    () async {
      final translator = FakeTranslator();
      final cubit = TranslationCubit(
        translator: translator,
        store: MemoryTranslationStore(),
      );
      await cubit.translate(const Settings());
      cubit.edit('🙂' * (translationLimit + 1));
      await cubit.translate(const Settings());
      cubit.edit('Текст');
      cubit.languages(to: TranslationLanguage.russian);
      await cubit.translate(const Settings());
      expect(translator.requests, isEmpty);
      await cubit.close();
    },
  );

  test('Повтор после ошибки перевода возможен', () async {
    final translator = FakeTranslator()..pending = Completer();
    final cubit = TranslationCubit(
      translator: translator,
      store: MemoryTranslationStore(),
    )..edit('Привет');
    final request = cubit.translate(const Settings());
    translator.pending!.completeError(const SocketException('Нет связи'));
    await request;
    expect(cubit.state.translating, isFalse);
    expect(cubit.state.message, contains('Ollama'));
    translator.pending = null;
    await cubit.translate(const Settings());
    expect(cubit.state.draft.output, 'Hello!');
    expect(cubit.state.message, isNull);
    await cubit.close();
  });

  test('Файл перевода восстанавливается из резервной копии без потери имён и оформления', () async {
    final directory = await Directory.systemTemp.createTemp(
      'korrekta-translation-',
    );
    try {
      final store = FileTranslationStore(
        File('${directory.path}/translation.json'),
      );
      expect((await store.load()).from, TranslationLanguage.russian);
      const draft = TranslationDraft(
        text: 'Норвета\r\n  `код` 🙂',
        output: 'Норвета\r\n  `код` 🙂',
        to: TranslationLanguage.german,
      );
      await store.save(draft);
      await store.save(draft.copyWith(text: 'Второй текст'));
      await store.file.writeAsString('{broken');
      final restored = await store.load();
      expect(restored.toJson(), draft.toJson());
      await store.save(restored.copyWith(text: 'Третий текст'));
      expect(
        await File('${store.file.path}.backup').readAsString(),
        contains('Норвета'),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
