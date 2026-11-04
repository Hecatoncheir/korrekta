import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'vim_cubit.dart';
import 'vim_keyboard.dart';

class VimInput extends StatelessWidget {
  const VimInput({
    super.key,
    required this.controller,
    required this.focus,
    required this.vim,
    required this.fieldKey,
    required this.hint,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final VimCubit vim;
  final Key fieldKey;
  final String hint;

  @override
  Widget build(BuildContext context) => BlocBuilder<VimCubit, VimState>(
    bloc: vim,
    builder: (context, state) => Focus(
      onKeyEvent: (_, event) => vimKey(vim, event),
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focus,
        readOnly: state.enabled && state.mode != VimMode.insert,
        showCursor: true,
        cursorWidth: state.enabled && state.mode != VimMode.insert ? 11 : 2,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 21, height: 1.7),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ),
  );
}
