import 'dart:convert';
import 'dart:io';

import '../domain/settings.dart';

typedef SavedDraft = ({String text, Settings settings});

abstract interface class DraftStore {
  Future<void> save(SavedDraft draft);
}

class FileDraftStore implements DraftStore {
  FileDraftStore(this.file);
  final File file;

  Future<SavedDraft> load(Settings defaults) async {
    for (final source in [file, File('${file.path}.backup')]) {
      final draft = await _read(source);
      if (draft != null) return draft;
    }
    if (await file.exists() || await File('${file.path}.backup').exists()) {
      throw const FormatException(
        'Черновик повреждён. Файлы сохранены для восстановления.',
      );
    }
    return (text: '', settings: defaults);
  }

  Future<SavedDraft?> _read(File source) async {
    if (!await source.exists()) return null;
    try {
      return switch (jsonDecode(await source.readAsString())) {
        {
          'version': 1,
          'text': String text,
          'settings': Map<String, dynamic> json,
        } =>
          (text: text, settings: Settings.fromJson(json)),
        _ => null,
      };
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<void> save(SavedDraft draft) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'text': draft.text,
        'settings': draft.settings.toJson(),
      }),
      flush: true,
    );
    // Повреждённый основной файл не затирает последнюю читаемую копию.
    if (await _read(file) != null) await file.copy('${file.path}.backup');
    await temporary.rename(file.path);
  }
}
