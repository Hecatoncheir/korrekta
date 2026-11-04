import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockVimClipboard() {
  String? text;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      text = (call.arguments as Map)['text'] as String;
    }
    if (call.method == 'Clipboard.getData') return {'text': text};
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

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
