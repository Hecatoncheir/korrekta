const generationLimit = 3000;

typedef GenerationOutput = ({String text, bool limited});

class GenerationDraft {
  const GenerationDraft({
    this.prompt = '',
    this.output = '',
    this.limited = false,
  });
  final String prompt, output;
  final bool limited;

  GenerationDraft copyWith({String? prompt, String? output, bool? limited}) =>
      GenerationDraft(
        prompt: prompt ?? this.prompt,
        output: output ?? this.output,
        limited: limited ?? this.limited,
      );

  Map<String, Object> toJson() => {
    'version': 1,
    'prompt': prompt,
    'output': output,
    'limited': limited,
  };

  factory GenerationDraft.fromJson(Object? value) => switch (value) {
    {
      'version': 1,
      'prompt': String prompt,
      'output': String output,
      'limited': bool limited,
    } =>
      GenerationDraft(prompt: prompt, output: output, limited: limited),
    _ => throw const FormatException('Неверный формат черновика генерации'),
  };
}
