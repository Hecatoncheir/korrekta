import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vim_cubit.dart';

KeyEventResult vimKey(VimCubit vim, KeyEvent event) {
  if (!vim.state.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
  if (event.logicalKey == LogicalKeyboardKey.escape) {
    vim.escape();
    return KeyEventResult.handled;
  }
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed) return controlKey(vim, event);
  if (keyboard.isAltPressed || keyboard.isMetaPressed) {
    return KeyEventResult.ignored;
  }
  final character = commandCharacter(event);
  if (character == null) return KeyEventResult.ignored;
  return vim.key(character) ? KeyEventResult.handled : KeyEventResult.ignored;
}

KeyEventResult controlKey(VimCubit vim, KeyEvent event) {
  if (event.physicalKey == PhysicalKeyboardKey.bracketLeft) {
    vim.escape();
    return KeyEventResult.handled;
  }
  if (event.physicalKey == PhysicalKeyboardKey.keyR &&
      vim.state.mode != VimMode.insert) {
    vim.redo();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

String? commandCharacter(KeyEvent event) {
  final letters = {
    PhysicalKeyboardKey.keyA: 'a',
    PhysicalKeyboardKey.keyB: 'b',
    PhysicalKeyboardKey.keyC: 'c',
    PhysicalKeyboardKey.keyD: 'd',
    PhysicalKeyboardKey.keyE: 'e',
    PhysicalKeyboardKey.keyG: 'g',
    PhysicalKeyboardKey.keyH: 'h',
    PhysicalKeyboardKey.keyI: 'i',
    PhysicalKeyboardKey.keyJ: 'j',
    PhysicalKeyboardKey.keyK: 'k',
    PhysicalKeyboardKey.keyL: 'l',
    PhysicalKeyboardKey.keyO: 'o',
    PhysicalKeyboardKey.keyP: 'p',
    PhysicalKeyboardKey.keyS: 's',
    PhysicalKeyboardKey.keyU: 'u',
    PhysicalKeyboardKey.keyV: 'v',
    PhysicalKeyboardKey.keyW: 'w',
    PhysicalKeyboardKey.keyX: 'x',
    PhysicalKeyboardKey.keyY: 'y',
  };
  final digits = {
    PhysicalKeyboardKey.digit0: ('0', ')'),
    PhysicalKeyboardKey.digit1: ('1', '!'),
    PhysicalKeyboardKey.digit2: ('2', '@'),
    PhysicalKeyboardKey.digit3: ('3', '#'),
    PhysicalKeyboardKey.digit4: ('4', r'$'),
    PhysicalKeyboardKey.digit5: ('5', '%'),
    PhysicalKeyboardKey.digit6: ('6', '^'),
    PhysicalKeyboardKey.digit7: ('7', '&'),
    PhysicalKeyboardKey.digit8: ('8', '*'),
    PhysicalKeyboardKey.digit9: ('9', '('),
  };
  final shift = HardwareKeyboard.instance.isShiftPressed;
  if (digits[event.physicalKey] case (final plain, final shifted)) {
    return shift ? shifted : plain;
  }
  final letter = letters[event.physicalKey];
  if (letter == null) return event.character;
  return shift ? letter.toUpperCase() : letter;
}
