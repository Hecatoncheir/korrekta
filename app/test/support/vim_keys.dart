import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent russianEvent(PhysicalKeyboardKey physical, String character) =>
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: LogicalKeyboardKey(character.toLowerCase().runes.single),
      character: character,
      timeStamp: Duration.zero,
    );

Future<bool> russianKey(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  String character,
) => tester.sendKeyEvent(
  LogicalKeyboardKey(character.toLowerCase().runes.single),
  physicalKey: physical,
  character: character,
  // Эта таблица симулятора допускает кириллицу в logicalKey.
  platform: 'macos',
);
