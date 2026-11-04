import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../data/window_placement.dart';

class WindowSession with WindowListener {
  WindowSession(this.store);
  final WindowPlacementStore store;
  WindowPlacement placement = (
    bounds: const Rect.fromLTWH(80, 80, 1180, 780),
    maximized: false,
    fullScreen: false,
  );
  Timer? _timer;
  Future<void> _pending = Future.value();
  Future<bool> Function()? beforeClose;
  bool _closing = false;

  static Future<WindowSession> restore(String directory) async {
    await windowManager.ensureInitialized();
    final session = WindowSession(
      WindowPlacementStore(File(p.join(directory, 'window.json'))),
    );
    final saved = await session.store.load();
    final displays = await screenRetriever.getAllDisplays();
    final screens = displays
        .map(
          (display) =>
              (display.visiblePosition ?? Offset.zero) &
              (display.visibleSize ?? display.size),
        )
        .toList();
    session.placement = saved ?? session.placement;
    session.placement = (
      bounds: fitWindow(session.placement.bounds, screens),
      maximized: session.placement.maximized,
      fullScreen: session.placement.fullScreen,
    );
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'Корректа'),
    );
    await windowManager.setBounds(session.placement.bounds);
    if (session.placement.maximized) await windowManager.maximize();
    if (session.placement.fullScreen) await windowManager.setFullScreen(true);
    await windowManager.setPreventClose(true);
    windowManager.addListener(session);
    return session;
  }

  @override
  void onWindowEvent(String eventName) {
    if (!const {
      'resize',
      'resized',
      'move',
      'moved',
      'maximize',
      'unmaximize',
      'enter-full-screen',
      'leave-full-screen',
    }.contains(eventName)) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      unawaited(flush().catchError((Object _) {}));
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _pending = _pending.catchError((Object _) {}).then((_) => _save());
    return _pending;
  }

  Future<void> _save() async {
    if (await windowManager.isMinimized()) return;
    final maximized = await windowManager.isMaximized();
    final fullScreen = await windowManager.isFullScreen();
    final bounds = maximized || fullScreen
        ? placement.bounds
        : await windowManager.getBounds();
    placement = (bounds: bounds, maximized: maximized, fullScreen: fullScreen);
    await store.save(placement);
  }

  @override
  void onWindowClose() {
    unawaited(closeWindow());
  }

  Future<void> closeWindow() async {
    if (_closing) return;
    _closing = true;
    try {
      if (await beforeClose?.call() != true) return;
      await flush();
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }
}
