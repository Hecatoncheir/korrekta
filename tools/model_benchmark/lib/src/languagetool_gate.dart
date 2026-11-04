import 'dart:convert';

import 'text_diff.dart';
import 'text_guard.dart';

const languageToolGateVersion = 'lt-agreement-v1';

class ConfirmedEdit {
  const ConfirmedEdit(this.edit, this.ruleId);
  final Edit edit;
  final String ruleId;
}

class ConfirmationResult {
  const ConfirmationResult(this.guard, this.confirmed, this.unconfirmed);
  final GuardResult guard;
  final List<ConfirmedEdit> confirmed;
  final List<Edit> unconfirmed;

  String applyTo(String current) {
    if (current != guard.original) {
      throw StateError('Подтверждения относятся к другой версии текста');
    }
    return applyEdits(current, confirmed.map((item) => item.edit).toList());
  }

  String get output => applyTo(guard.original);
}

/// Подтверждение требует той же правки среди вариантов LT на исходнике.
/// Отсутствие замечаний не считается разрешением менять текст.
ConfirmationResult confirmText(
  String text,
  String proposed,
  List<dynamic> matches, {
  List<String> names = const [],
}) {
  final guarded = guardText(text, proposed, names: names);
  final supported = _supportedEffects(text, matches);
  final confirmed = <ConfirmedEdit>[];
  final unconfirmed = <Edit>[];
  for (final edit in guarded.accepted) {
    final rule = supported[_effect(edit)];
    if (rule == null) {
      unconfirmed.add(edit);
    } else {
      confirmed.add(ConfirmedEdit(edit, rule));
    }
  }
  return ConfirmationResult(
    guarded,
    List.unmodifiable(confirmed),
    List.unmodifiable(unconfirmed),
  );
}

Map<String, String> _supportedEffects(String text, List<dynamic> matches) {
  final effects = <String, String>{};
  for (final value in matches) {
    if (value is! Map<String, dynamic> ||
        value['offset'] is! int ||
        value['length'] is! int ||
        value['replacements'] is! List<dynamic> ||
        value['rule'] is! Map<String, dynamic>) {
      throw const FormatException('Неправильное замечание LanguageTool');
    }
    final start = value['offset'] as int;
    final end = start + (value['length'] as int);
    final rule = (value['rule'] as Map<String, dynamic>)['id'];
    if (start < 0 || end < start || end > text.length || rule is! String) {
      throw const FormatException('Неправильный диапазон или правило LT');
    }
    if (!_boundary(text, start) || !_boundary(text, end)) {
      throw const FormatException('Диапазон LT разрывает Unicode-символ');
    }
    final original = text.substring(start, end);
    for (final replacement in value['replacements'] as List<dynamic>) {
      if (replacement is! Map<String, dynamic> ||
          replacement['value'] is! String) {
        throw const FormatException('Неправильный вариант LanguageTool');
      }
      final target = replacement['value'] as String;
      if (!_bounded(original, target) || original == target) continue;
      effects.putIfAbsent(_effect(Edit(start, original, target)), () => rule);
    }
  }
  return effects;
}

bool _bounded(String original, String target) =>
    original.runes.length <= 4000 &&
    target.runes.length <= 4000 &&
    (original.runes.length + 1) * (target.runes.length + 1) <= 4000000;

bool _boundary(String text, int position) {
  if (position == text.length) return true;
  final unit = text.codeUnitAt(position);
  return unit < 0xdc00 || unit > 0xdfff;
}

String _effect(Edit edit) => jsonEncode([
  for (final part in diffEdits(edit.original, edit.replacement))
    [edit.start + part.start, edit.start + part.end, part.replacement],
]);
