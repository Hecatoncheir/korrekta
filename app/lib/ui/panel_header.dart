import 'package:flutter/material.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: child,
    ),
  );
}
