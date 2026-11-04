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
    PhysicalKeyboardKey.keyU: 'u',
    PhysicalKeyboardKey.keyV: 'v',
    PhysicalKeyboardKey.keyW: 'w',
    PhysicalKeyboardKey.keyX: 'x',
    PhysicalKeyboardKey.keyY: 'y',
  };
  final letter = letters[event.physicalKey];
  if (letter == null) return event.character;
  return HardwareKeyboard.instance.isShiftPressed
      ? letter.toUpperCase()
      : letter;
}
