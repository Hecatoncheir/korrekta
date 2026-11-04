import 'dart:convert';
import 'dart:io';

import '../domain/translation.dart';

abstract interface class TranslationStore {
  Future<void> save(TranslationDraft draft);
}

class FileTranslationStore implements TranslationStore {
  const FileTranslationStore(this.file);
  final File file;

  Future<TranslationDraft> load() async {
    for (final source in [file, File('${file.path}.backup')]) {
      final draft = await _read(source);
      if (draft != null) return draft;
    }
    if (await file.exists() || await File('${file.path}.backup').exists()) {
      throw const FormatException(
        'Черновик перевода повреждён. Файлы сохранены для восстановления.',
      );
    }
    return const TranslationDraft();
  }

  Future<TranslationDraft?> _read(File source) async {
    if (!await source.exists()) return null;
    try {
      return TranslationDraft.fromJson(jsonDecode(await source.readAsString()));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<void> save(TranslationDraft draft) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(draft.toJson()), flush: true);
    if (await _read(file) != null) await file.copy('${file.path}.backup');
    await temporary.rename(file.path);
  }
}
