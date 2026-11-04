import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WindowChrome extends StatefulWidget {
  const WindowChrome({super.key, required this.child});
  final Widget child;
  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(synchronize());
  }

  Future<void> synchronize() async {
    final theme = Theme.of(context);
    try {
      await const MethodChannel('korrekta/window')
          .invokeMethod<void>('colors', [
            theme.scaffoldBackgroundColor.toARGB32() & 0xffffff,
            theme.colorScheme.onSurface.toARGB32() & 0xffffff,
          ]);
    } on MissingPluginException {
      // В тестах виджетов системного окна нет.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
