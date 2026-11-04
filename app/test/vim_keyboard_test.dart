import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/ui/vim/vim_cubit.dart';
import 'package:korrekta/ui/vim/vim_keyboard.dart';

import 'support/vim_keys.dart';

const letters = [
  (PhysicalKeyboardKey.keyA, 'a', 'ф'),
  (PhysicalKeyboardKey.keyB, 'b', 'и'),
  (PhysicalKeyboardKey.keyC, 'c', 'с'),
  (PhysicalKeyboardKey.keyD, 'd', 'в'),
  (PhysicalKeyboardKey.keyE, 'e', 'у'),
  (PhysicalKeyboardKey.keyG, 'g', 'п'),
  (PhysicalKeyboardKey.keyH, 'h', 'р'),
  (PhysicalKeyboardKey.keyI, 'i', 'ш'),
  (PhysicalKeyboardKey.keyJ, 'j', 'о'),
  (PhysicalKeyboardKey.keyK, 'k', 'л'),
  (PhysicalKeyboardKey.keyL, 'l', 'д'),
  (PhysicalKeyboardKey.keyO, 'o', 'щ'),
  (PhysicalKeyboardKey.keyP, 'p', 'з'),
  (PhysicalKeyboardKey.keyS, 's', 'ы'),
  (PhysicalKeyboardKey.keyU, 'u', 'г'),
  (PhysicalKeyboardKey.keyV, 'v', 'м'),
  (PhysicalKeyboardKey.keyW, 'w', 'ц'),
  (PhysicalKeyboardKey.keyX, 'x', 'ч'),
  (PhysicalKeyboardKey.keyY, 'y', 'н'),
];

void main() {
  testWidgets(
    'Ctrl+к повторяет правку, Ctrl+х завершает Insert, обычный русский ввод свободен',
    (tester) async {
      final controller = TextEditingController(text: 'слово')
        ..selection = const TextSelection.collapsed(offset: 0);
      final vim = VimCubit(controller)..enable(true);
      addTearDown(() async {
        await vim.close();
        controller.dispose();
      });
      vim.key('x');
      vim.undo();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(
        vimKey(vim, russianEvent(PhysicalKeyboardKey.keyR, 'к')),
        KeyEventResult.handled,
      );
      expect(controller.text, 'лово');
      vim.key('i');
      expect(
        vimKey(vim, russianEvent(PhysicalKeyboardKey.bracketLeft, 'х')),
        KeyEventResult.handled,
      );
      expect(vim.state.mode, VimMode.normal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      vim.key('i');
      expect(
        vimKey(vim, russianEvent(PhysicalKeyboardKey.keyJ, 'о')),
        KeyEventResult.ignored,
      );
      vim.enable(false);
      expect(
        vimKey(vim, russianEvent(PhysicalKeyboardKey.keyS, 'ы')),
        KeyEventResult.ignored,
      );
    },
  );

  testWidgets(
    'Все командные буквы используют физические клавиши в русской раскладке',
    (tester) async {
      for (final (physical, command, russian) in letters) {
        expect(commandCharacter(russianEvent(physical, russian)), command);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (final (physical, command, russian) in letters) {
        expect(
          commandCharacter(russianEvent(physical, russian.toUpperCase())),
          command.toUpperCase(),
        );
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    },
  );

  testWidgets(
    'Shift+4 и Shift+6 дают команды конца и начала строки в русской раскладке',
    (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        commandCharacter(russianEvent(PhysicalKeyboardKey.digit4, ';')),
        r'$',
      );
      expect(
        commandCharacter(russianEvent(PhysicalKeyboardKey.digit6, ':')),
        '^',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    },
  );
}
