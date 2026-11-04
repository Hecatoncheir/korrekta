import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'vim_motions.dart';
import 'vim_edits.dart';

enum VimMode { normal, insert, visual, visualLine }

typedef VimState = ({bool enabled, VimMode mode, String pending});

class VimCubit extends Cubit<VimState> {
  VimCubit(this.controller)
    : _last = controller.value,
      super((enabled: false, mode: VimMode.insert, pending: '')) {
    controller.addListener(_changed);
  }
  final TextEditingController controller;
  final _undo = <TextEditingValue>[];
  final _redo = <TextEditingValue>[];
  TextEditingValue _last;
  TextEditingValue? _insertStart;
  int _cursor = 0, _anchor = 0, _count = 0, _operatorCount = 1;
  String _operator = '', _prefix = '', _register = '';
  bool _linewise = false, _selecting = false, _replaying = false;
  String get text => controller.text;
  bool get visual =>
      state.mode == VimMode.visual || state.mode == VimMode.visualLine;
  int get count => math.max(1, _count);

  void enable(bool enabled) {
    if (enabled == state.enabled) return;
    _commitInsert();
    _reset();
    emit((
      enabled: enabled,
      mode: enabled ? VimMode.normal : VimMode.insert,
      pending: '',
    ));
    if (!enabled) return;
    _cursor = normalPosition(text, controller.selection.extentOffset);
    _select();
  }

  void _changed() {
    final value = controller.value;
    if (value.text != _last.text &&
        !_replaying &&
        state.mode != VimMode.insert) {
      _remember(_last);
    }
    if (!_selecting) {
      _cursor = value.selection.extentOffset.clamp(0, text.length);
    }
    _last = value;
  }

  void _remember(TextEditingValue value) {
    _undo.add(value);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _commitInsert() {
    final start = _insertStart;
    if (start != null && start.text != text) _remember(start);
    _insertStart = null;
  }

  void escape() {
    if (state.mode == VimMode.insert && _insertStart != null) {
      final position = controller.selection.extentOffset.clamp(0, text.length);
      _cursor = math.max(
        lineAt(text, position).start,
        previousCharacter(text, position),
      );
    }
    _commitInsert();
    _reset();
    _mode(VimMode.normal);
    _cursor = normalPosition(text, _cursor);
    _select();
  }

  void _mode(VimMode mode) => emit((
    enabled: state.enabled,
    mode: mode,
    pending: '$_operator$_prefix${_count == 0 ? '' : _count}',
  ));
  void _reset() {
    _operator = '';
    _prefix = '';
    _count = 0;
    _operatorCount = 1;
  }

  bool key(String key) {
    if (!state.enabled || state.mode == VimMode.insert) return false;
    if (_digit(key)) return true;
    if (key == 'g') {
      _goPrefix();
      return true;
    }
    if (const {
      'h',
      'j',
      'k',
      'l',
      'w',
      'b',
      'e',
      '0',
      '^',
      r'$',
      'G',
    }.contains(key)) {
      _motion(key);
      return true;
    }
    if (const {'d', 'c', 'y'}.contains(key)) {
      _operatorKey(key);
      return true;
    }
    final actions = <String, void Function()>{
      'i': () => _insert(_cursor),
      'a': () => _insert(nextCharacter(text, _cursor)),
      'I': () => _insert(motionTarget(text, _cursor, '^', 1)),
      'A': () => _insert(lineAt(text, _cursor).end),
      'o': () => _openLine(false),
      'O': () => _openLine(true),
      'v': () => _visual(VimMode.visual),
      'V': () => _visual(VimMode.visualLine),
      'x': () => _changeCharacters('d'),
      's': () => _changeCharacters('c'),
      'D': () => _operate('d', _cursor, lineAt(text, _cursor).end),
      'C': () => _operate('c', _cursor, lineAt(text, _cursor).end),
      'p': () => unawaited(paste(false)),
      'P': () => unawaited(paste(true)),
      'u': undo,
    };
    actions[key]?.call();
    _reset();
    _mode(state.mode);
    return true;
  }

  bool _digit(String key) {
    if (!RegExp(r'^[0-9]$').hasMatch(key)) return false;
    if (key == '0' && _count == 0) return false;
    _count = math.min(999, _count * 10 + int.parse(key));
    _mode(state.mode);
    return true;
  }

  void _goPrefix() {
    if (_prefix == 'g') {
      _motion('gg');
      return;
    }
    _prefix = 'g';
    _mode(state.mode);
  }

  void _motion(String key) {
    var target = motionTarget(text, _cursor, key, count * _operatorCount);
    if (_operator == 'c' && key == 'w') {
      target = changeWordEnd(text, _cursor, target);
    }
    if (_operator.isNotEmpty) {
      final end = const {'e', r'$', 'G'}.contains(key)
          ? nextCharacter(text, target)
          : target;
      _operate(_operator, math.min(_cursor, target), math.max(_cursor, end));
    } else {
      _cursor = normalPosition(text, target);
      _select();
    }
    _reset();
    _mode(state.mode);
  }

  void _operatorKey(String key) {
    if (visual || !controller.selection.isCollapsed) {
      final selection = controller.selection;
      _operate(
        key,
        selection.start,
        selection.end,
        linewise: state.mode == VimMode.visualLine,
      );
      return;
    }
    if (_operator == key) {
      _lineOperation(key);
      return;
    }
    _operator = key;
    _operatorCount = count;
    _count = 0;
    _mode(state.mode);
  }

  void _lineOperation(String operation) {
    final start = lineAt(text, _cursor).start;
    var end = start;
    for (var i = 0; i < count * _operatorCount; i++) {
      end = lineAt(text, end).next;
    }
    _operate(operation, start, end, linewise: true);
    _reset();
    _mode(state.mode);
  }

  void _operate(String operation, int start, int end, {bool linewise = false}) {
    _linewise = linewise;
    _register = text.substring(start, end);
    unawaited(Clipboard.setData(ClipboardData(text: _register)));
    if (operation == 'y') {
      _cursor = start;
      escape();
      return;
    }
    if (operation == 'c') _insert(start);
    final keepLine = operation == 'c' && linewise && _register.endsWith('\n');
    final replacement = keepLine
        ? (_register.endsWith('\r\n') ? '\r\n' : '\n')
        : '';
    _replace(start, end, replacement, start);
    if (operation != 'c') escape();
  }

  void _replace(int start, int end, String replacement, int cursor) {
    _cursor = cursor;
    _selecting = true;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: cursor),
    );
    _selecting = false;
  }

  void _insert(int position) {
    _insertStart ??= controller.value;
    _mode(VimMode.insert);
    _cursor = position.clamp(0, text.length);
    _select();
  }

  void _openLine(bool above) {
    final line = lineAt(text, _cursor);
    final newline = text.contains('\r\n') ? '\r\n' : '\n';
    final position = above ? line.start : line.end;
    _insert(position);
    _replace(
      position,
      position,
      newline,
      above ? position : position + newline.length,
    );
  }

  void _visual(VimMode mode) {
    if (visual) {
      escape();
      return;
    }
    _anchor = _cursor;
    _mode(mode);
    _select();
  }

  void _select() {
    var selection = TextSelection.collapsed(offset: _cursor);
    if (visual) {
      selection = TextSelection(
        baseOffset: math.min(_anchor, _cursor),
        extentOffset: nextCharacter(text, math.max(_anchor, _cursor)),
      );
    }
    if (state.mode == VimMode.visualLine) {
      selection = TextSelection(
        baseOffset: lineAt(text, math.min(_anchor, _cursor)).start,
        extentOffset: lineAt(text, math.max(_anchor, _cursor)).next,
      );
    }
    _selecting = true;
    controller.selection = selection;
    _selecting = false;
  }

  void _changeCharacters(String operation) {
    if (visual) {
      final selection = controller.selection;
      _operate(
        operation,
        selection.start,
        selection.end,
        linewise: state.mode == VimMode.visualLine,
      );
      return;
    }
    final target = motionTarget(text, _cursor, 'l', count);
    _linewise = false;
    _operate(
      operation,
      _cursor,
      target.clamp(_cursor, lineAt(text, _cursor).end),
    );
  }

  Future<void> paste(bool before) async {
    final repeats = count;
    final snapshot = controller.value;
    final mode = state.mode;
    final value = await _pasteText();
    if (value == null ||
        value.isEmpty ||
        controller.value != snapshot ||
        state.mode != mode ||
        !state.enabled) {
      return;
    }
    if (!snapshot.selection.isCollapsed) {
      _pasteSelection(snapshot.selection, value * repeats);
      return;
    }
    final placement = pastePlacement(
      text,
      _cursor,
      value,
      before: before,
      linewise: value == _register ? _linewise : value.endsWith('\n'),
      count: repeats,
    );
    _replace(
      placement.start,
      placement.start,
      placement.insert,
      placement.cursor,
    );
    _cursor = normalPosition(text, _cursor);
    _select();
  }

  Future<String?> _pasteText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? _register;
    } on PlatformException {
      return _register;
    }
  }

  void _pasteSelection(TextSelection selection, String insert) {
    final changed = text.replaceRange(selection.start, selection.end, insert);
    _replace(
      selection.start,
      selection.end,
      insert,
      previousCharacter(changed, selection.start + insert.length),
    );
    _cursor = normalPosition(text, _cursor);
    _reset();
    _mode(VimMode.normal);
    _select();
  }

  void undo() => _replay(_undo, _redo);
  void redo() => _replay(_redo, _undo);
  void _replay(List<TextEditingValue> source, List<TextEditingValue> target) {
    if (source.isEmpty) return;
    target.add(controller.value);
    _replaying = true;
    controller.value = source.removeLast();
    _replaying = false;
    _cursor = normalPosition(text, controller.selection.extentOffset);
    _select();
  }

  @override
  Future<void> close() {
    controller.removeListener(_changed);
    return super.close();
  }
}
