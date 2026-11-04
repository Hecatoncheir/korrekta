import 'dart:async';

import 'package:korrekta/data/local_translator.dart';
import 'package:korrekta/data/translation_store.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/domain/translation.dart';

class MemoryTranslationStore implements TranslationStore {
  TranslationDraft? draft;
  bool fail = false;
  @override
  Future<void> save(TranslationDraft draft) async {
    if (fail) throw StateError('Нет места');
    this.draft = draft;
  }
}

class FakeTranslator implements TextTranslator {
  final requests = <({TranslationDraft draft, Settings settings})>[];
  Completer<String>? pending;
  @override
  Future<String> translate(TranslationDraft draft, Settings settings) async {
    requests.add((draft: draft, settings: settings));
    return pending?.future ?? 'Hello!';
  }

  @override
  void cancel() {}
}
