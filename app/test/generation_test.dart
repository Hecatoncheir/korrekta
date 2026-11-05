import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korrekta/data/generation_store.dart';
import 'package:korrekta/data/local_generator.dart';
import 'package:korrekta/domain/generation.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/generation_cubit.dart';

import 'support/generation_fakes.dart';

void main() {
  test('Обе модели получают запрос локально без формата корректуры', () async {
    for (final model in LocalModel.values) {
      final generator = LocalGenerator(
        createClient: () => MockClient((request) async {
          final api = model == LocalModel.quality ? 'generate' : 'chat';
          expect(request.url.toString(), 'http://127.0.0.1:11434/api/$api');
          expect(request.followRedirects, isFalse);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], model.id);
          expect(body['stream'], isFalse);
          expect(body.containsKey('format'), isFalse);
          if (model == LocalModel.balanced) {
            expect(body['messages'].last['content'], 'Верни {\n🙂');
            expect(body.containsKey('raw'), isFalse);
          } else {
            expect(body['raw'], isTrue);
            expect(body['prompt'], contains('<|role_sep|>Верни {\n🙂'));
            expect(body['prompt'], endsWith('assistant<|role_sep|>'));
            expect(body.containsKey('messages'), isFalse);
          }
          return http.Response(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              if (model == LocalModel.balanced)
                'message': {'role': 'assistant', 'content': '{\n🙂'}
              else
                'response': '{\n🙂',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(await generator.generate('Верни {\n🙂', Settings(model: model)), (
        text: '{\n🙂',
        limited: false,
      ));
    }
  });

  test(
    'Частичный ответ сохраняется с предупреждением, неверный отклоняется',
    () {
      expect(
        readGeneration({
          'done': true,
          'done_reason': 'length',
          'message': {'role': 'assistant', 'content': 'Начало'},
        }),
        (text: 'Начало', limited: true),
      );
      for (final value in [
        null,
        <String, Object>{},
        {
          'done': false,
          'message': {'role': 'assistant', 'content': 'Начало'},
        },
        {
          'done': true,
          'message': {'role': 'assistant', 'content': '   '},
        },
        {
          'done': true,
          'message': {'role': 'user', 'content': 'Запрос'},
        },
      ]) {
        expect(() => readGeneration(value), throwsFormatException);
      }
    },
  );

  test(
    'Внешний адрес и отсутствие модели показывают понятную ошибку',
    () async {
      final generator = LocalGenerator(
        createClient: () => MockClient((_) async => http.Response('{}', 404)),
      );
      await expectLater(
        generator.generate(
          'Запрос',
          const Settings(ollama: 'https://example.org'),
        ),
        throwsFormatException,
      );
      await expectLater(
        generator.generate('Запрос', const Settings()),
        throwsA(
          isA<FormatException>().having(
            (e) => generationError(e),
            'сообщение',
            contains('модель не найдена'),
          ),
        ),
      );
    },
  );

  test(
    'Изменение запроса, модели, очистка и отмена отклоняют старый ответ',
    () async {
      final service = FakeGenerator();
      final cubit = GenerationCubit(
        generator: service,
        store: MemoryGenerationStore(),
      );
      for (final change in [
        () => cubit.edit('Другой запрос'),
        cubit.modelChanged,
        cubit.cancel,
        cubit.clear,
      ]) {
        cubit.edit('Сочини рассказ');
        service.pending = Completer();
        final run = cubit.generate(const Settings());
        expect(cubit.state.generating, isTrue);
        change();
        service.pending!.complete((text: 'Старый результат', limited: false));
        await run;
        expect(cubit.state.generating, isFalse);
        expect(cubit.state.draft.output, isEmpty);
      }
      await cubit.close();
    },
  );

  test('Лимит, ошибки, сохранение и повторная генерация', () async {
    final service = FakeGenerator();
    final store = MemoryGenerationStore();
    final cubit = GenerationCubit(generator: service, store: store);
    expect(cubit.state.ready, isFalse);
    cubit.edit('🙂' * generationLimit);
    expect(cubit.state.ready, isTrue);
    cubit.edit('я' * (generationLimit + 1));
    await cubit.generate(const Settings());
    expect(service.requests, isEmpty);
    expect(generationMessage(cubit.state), contains('$generationLimit'));
    cubit.edit('Напиши приветствие');
    await cubit.generate(const Settings(model: LocalModel.quality));
    expect(service.requests.single.settings.model, LocalModel.quality);
    expect(cubit.state.draft.output, 'Готовый текст.');
    service.pending = Completer();
    final run = cubit.generate(const Settings());
    service.pending!.completeError(const SocketException('Нет соединения'));
    await run;
    expect(cubit.state.message, contains('Ollama не отвечает'));
    expect(cubit.state.draft.output, 'Готовый текст.');
    store.fail = true;
    await cubit.flush();
    expect(generationMessage(cubit.state), contains('Скопируйте'));
    store.fail = false;
    await cubit.flush();
    expect(cubit.state.saved, isTrue);
    expect(store.draft!.prompt, 'Напиши приветствие');
    await cubit.close();
  });

  test('Черновик генерации восстанавливается из резервной копии', () async {
    final directory = await Directory.systemTemp.createTemp(
      'korrekta-generation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/generation.json');
    final store = FileGenerationStore(file);
    expect((await store.load()).prompt, isEmpty);
    const first = GenerationDraft(
      prompt: 'Запрос\n🙂',
      output: 'Ответ\r\n',
      limited: true,
    );
    await store.save(first);
    await store.save(const GenerationDraft(prompt: 'Новый'));
    await file.writeAsString('broken');
    final restored = await store.load();
    expect(restored.toJson(), first.toJson());
    await File('${file.path}.backup').writeAsString('{}');
    await expectLater(store.load(), throwsFormatException);
    expect(await file.readAsString(), 'broken');
  });
}
