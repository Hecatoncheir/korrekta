import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'navigation_cubit.dart';
import 'settings_page.dart';
import 'suggestions_panel.dart';
import 'text_editor.dart';
import 'translation_page.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NavigationCubit, AppSection>(
        builder: (context, section) => IndexedStack(
          index: section.index,
          children: const [
            WorkspaceColumns(left: TextEditor(), right: SuggestionsPanel()),
            TranslationPage(),
            SettingsPage(),
          ],
        ),
      );
}

class WorkspaceColumns extends StatelessWidget {
  const WorkspaceColumns({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 7,
    this.rightFlex = 4,
    this.verticalFlex = (3, 2),
  });
  final Widget left, right;
  final int leftFlex, rightFlex;
  final (int, int) verticalFlex;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            Expanded(flex: verticalFlex.$1, child: left),
            const SizedBox(height: 12),
            Expanded(flex: verticalFlex.$2, child: right),
          ],
        );
      }
      return Row(
        children: [
          Expanded(flex: leftFlex, child: left),
          const SizedBox(width: 20),
          Expanded(flex: rightFlex, child: right),
        ],
      );
    },
  );
}
