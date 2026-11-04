import 'dart:io';

import 'package:path/path.dart' as p;

enum LocalModel {
  quality(
    '20В — Лучшее качество',
    'hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M',
  ),
  balanced(
    '10В — Лучшее соотношение скорость - качество',
    'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
  );

  const LocalModel(this.label, this.id);
  final String label;
  final String id;
  String get shortName => this == quality ? 'GigaChat 20В' : 'GigaChat 10В';
}

class Settings {
  const Settings({
    this.model = LocalModel.quality,
    this.dark = true,
    this.store = '',
    this.hunspell = '',
    this.ollama = 'http://127.0.0.1:11434',
    this.languageTool = 'http://127.0.0.1:8081',
    this.names = const [],
  });

  final LocalModel model;
  final bool dark;
  final String store, hunspell, ollama, languageTool;
  final List<String> names;

  static Settings defaults(String supportDirectory) {
    final existing = Directory('E:/korrekta/dictionaries-v1');
    final store = Platform.isWindows && existing.existsSync()
        ? existing.path
        : p.join(supportDirectory, 'dictionaries-v1');
    return Settings(
      store: store,
      hunspell: Platform.isWindows
          ? p.join(store, 'native', 'ucrt64', 'bin', 'hunspell.exe')
          : 'hunspell',
    );
  }

  Settings copyWith({LocalModel? model, bool? dark, List<String>? names}) =>
      Settings(
        model: model ?? this.model,
        dark: dark ?? this.dark,
        store: store,
        hunspell: hunspell,
        ollama: ollama,
        languageTool: languageTool,
        names: List.unmodifiable(names ?? this.names),
      );

  Map<String, Object> toJson() => {
    'model': model.name,
    'dark': dark,
    'store': store,
    'hunspell': hunspell,
    'ollama': ollama,
    'languageTool': languageTool,
    'names': names,
  };

  factory Settings.fromJson(Map<String, dynamic> json) => switch (json) {
    {
      'model': String model,
      'dark': bool dark,
      'store': String store,
      'hunspell': String hunspell,
      'ollama': String ollama,
      'languageTool': String languageTool,
      'names': List<dynamic> names,
    } =>
      Settings(
        model: LocalModel.values.byName(model),
        dark: dark,
        store: store,
        hunspell: hunspell,
        ollama: ollama,
        languageTool: languageTool,
        names: List.unmodifiable(names.cast<String>()),
      ),
    _ => throw const FormatException('Не удалось прочитать настройки'),
  };
}

Uri localEndpoint(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'http' ||
      !const ['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !const ['', '/'].contains(uri.path)) {
    throw const FormatException('Укажите локальный HTTP-адрес с портом');
  }
  return uri;
}
