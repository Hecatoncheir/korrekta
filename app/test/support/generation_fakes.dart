import 'dart:async';

import 'package:korrekta/data/generation_store.dart';
import 'package:korrekta/data/local_generator.dart';
import 'package:korrekta/domain/generation.dart';
import 'package:korrekta/domain/settings.dart';

class MemoryGenerationStore implements GenerationStore {
  GenerationDraft? draft;
  bool fail = false;
  @override
  Future<void> save(GenerationDraft draft) async {
    if (fail) throw StateError('Нет места');
    this.draft = draft;
  }
}

class FakeGenerator implements TextGenerator {
  final requests = <({String prompt, Settings settings})>[];
  Completer<GenerationOutput>? pending;
  @override
  Future<GenerationOutput> generate(String prompt, Settings settings) async {
    requests.add((prompt: prompt, settings: settings));
    return pending?.future ?? (text: 'Готовый текст.', limited: false);
  }

  @override
  void cancel() {}
}
