import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'navigation_cubit.dart';
import 'settings_page.dart';
import 'suggestions_panel.dart';
import 'text_editor.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NavigationCubit, AppSection>(
        builder: (context, section) => IndexedStack(
          index: section.index,
          children: const [
            WorkspaceColumns(left: TextEditor(), right: SuggestionsPanel()),
            SettingsPage(),
          ],
        ),
      );
}

class WorkspaceColumns extends StatelessWidget {
  const WorkspaceColumns({super.key, required this.left, required this.right});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(height: 12),
            Expanded(flex: 2, child: right),
          ],
        );
      }
      return Row(
        children: [
          Expanded(flex: 7, child: left),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: right),
        ],
      );
    },
  );
}
