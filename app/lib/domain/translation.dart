enum TranslationLanguage {
  russian('Русский', 'ru'),
  english('Английский', 'en'),
  german('Немецкий', 'de'),
  french('Французский', 'fr'),
  spanish('Испанский', 'es'),
  italian('Итальянский', 'it'),
  portuguese('Португальский', 'pt'),
  turkish('Турецкий', 'tr'),
  chinese('Китайский', 'zh'),
  japanese('Японский', 'ja'),
  korean('Корейский', 'ko'),
  ukrainian('Украинский', 'uk');

  const TranslationLanguage(this.label, this.code);
  final String label, code;
}

const translationLimit = 3000;

class TranslationDraft {
  const TranslationDraft({
    this.text = '',
    this.output = '',
    this.from = TranslationLanguage.russian,
    this.to = TranslationLanguage.english,
  });
  final String text, output;
  final TranslationLanguage from, to;

  TranslationDraft copyWith({
    String? text,
    String? output,
    TranslationLanguage? from,
    TranslationLanguage? to,
  }) => TranslationDraft(
    text: text ?? this.text,
    output: output ?? this.output,
    from: from ?? this.from,
    to: to ?? this.to,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'text': text,
    'output': output,
    'from': from.name,
    'to': to.name,
  };

  factory TranslationDraft.fromJson(Object? json) => switch (json) {
    {
      'version': 1,
      'text': String text,
      'output': String output,
      'from': String from,
      'to': String to,
    } =>
      TranslationDraft(
        text: text,
        output: output,
        from: TranslationLanguage.values.byName(from),
        to: TranslationLanguage.values.byName(to),
      ),
    _ => throw const FormatException('Не удалось прочитать перевод'),
  };
}
