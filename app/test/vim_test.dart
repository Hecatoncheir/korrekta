import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/domain/settings.dart';
import 'package:korrekta/ui/vim/vim_cubit.dart';

import 'editor_cubit_test.dart' show FakeChecker, MemoryStore, makeCubit;

void keys(VimCubit vim, String command) {
  for (final key in command.split('')) {
    vim.key(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TextEditingController controller;
  late VimCubit vim;
  setUp(() {
    controller = TextEditingController(text: 'А🙂Б\r\nВГ')
      ..selection = const TextSelection.collapsed(offset: 0);
    vim = VimCubit(controller)..enable(true);
  });
  tearDown(() async {
    await vim.close();
    controller.dispose();
  });

  test(
    'Normal: движение и удаление не разрывают эмодзи, u и redo восстанавливают',
    () {
      keys(vim, 'l');
      expect(controller.selection.extentOffset, 1);
      keys(vim, 'l');
      expect(controller.selection.extentOffset, 3);
      keys(vim, 'hx');
      expect(controller.text, 'АБ\r\nВГ');
      vim.undo();
      expect(controller.text, 'А🙂Б\r\nВГ');
      vim.redo();
      expect(controller.text, 'АБ\r\nВГ');
    },
  );

  test('Insert: Escape группирует ввод, переключение не меняет текст', () {
    keys(vim, 'i');
    expect(vim.state.mode, VimMode.insert);
    controller.value = const TextEditingValue(
      text: 'Ёлка А🙂Б\r\nВГ',
      selection: TextSelection.collapsed(offset: 5),
    );
    vim.escape();
    expect(vim.state.mode, VimMode.normal);
    vim.undo();
    expect(controller.text, 'А🙂Б\r\nВГ');
    vim.redo();
    expect(controller.text, 'Ёлка А🙂Б\r\nВГ');
    vim.enable(false);
    expect(vim.key('x'), isFalse);
    expect(controller.text, 'Ёлка А🙂Б\r\nВГ');
  });

  test('Visual: диапазон включает целые символы, d удаляет выделенное', () {
    keys(vim, 'vl');
    expect(vim.state.mode, VimMode.visual);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    keys(vim, 'd');
    expect(controller.text, 'Б\r\nВГ');
    vim.undo();
    expect(controller.text, 'А🙂Б\r\nВГ');
  });

  test('dd, yy и p сохраняют CRLF; cc сохраняет следующую строку', () async {
    keys(vim, 'yy');
    await vim.paste(false);
    expect(controller.text, 'А🙂Б\r\nА🙂Б\r\nВГ');
    keys(vim, 'ggdd');
    expect(controller.text, 'А🙂Б\r\nВГ');
    keys(vim, 'cc');
    expect(controller.text, '\r\nВГ');
    expect(vim.state.mode, VimMode.insert);
  });

  test('Счётчики и оператор движения работают со словами на кириллице', () {
    controller.value = const TextEditingValue(
      text: 'раз два три',
      selection: TextSelection.collapsed(offset: 0),
    );
    keys(vim, '2dw');
    expect(controller.text, 'три');
  });

  test(
    'cw сохраняет разделительный пробел, Escape не перескакивает пустую строку',
    () {
      controller.value = const TextEditingValue(
        text: 'раз два',
        selection: TextSelection.collapsed(offset: 0),
      );
      keys(vim, 'cw');
      expect(controller.text, ' два');
      vim.escape();
      vim.undo();
      keys(vim, 'o');
      vim.escape();
      expect(controller.text, 'раз два\n');
      expect(controller.selection.extentOffset, controller.text.length);
    },
  );

  test('Переход между строками и начало/конец документа', () {
    keys(vim, 'j');
    expect(controller.selection.extentOffset, 6);
    keys(vim, 'G');
    expect(controller.selection.extentOffset, 7);
    keys(vim, 'gg');
    expect(controller.selection.extentOffset, 0);
  });

  test('Старые настройки читаются, Vim mode сохраняется', () {
    final json = const Settings().toJson()..remove('vimMode');
    expect(Settings.fromJson(json).vimMode, isFalse);
    final settings = const Settings().copyWith(vimMode: true);
    expect(Settings.fromJson(settings.toJson()).vimMode, isTrue);
  });

  test('Смена Vim и темы сохраняет уже полученные подсказки', () async {
    final editor = makeCubit(FakeChecker(), MemoryStore());
    await editor.check();
    final result = editor.state.result;
    editor.configure(
      editor.state.settings.copyWith(vimMode: true, dark: false),
    );
    expect(editor.state.result, same(result));
    await editor.close();
  });
}
