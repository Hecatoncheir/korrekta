import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:korrekta/data/window_placement.dart';

void main() {
  test('Размер, положение и развёрнутое состояние сохраняются', () async {
    final directory = await Directory.systemTemp.createTemp('korrekta-window-');
    try {
      final store = WindowPlacementStore(File('${directory.path}/window.json'));
      const placement = (
        bounds: Rect.fromLTWH(-1100, 120, 1000, 700),
        maximized: true,
        fullScreen: false,
      );
      await store.save(placement);
      expect(await store.load(), placement);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'Видимое окно не меняется, отключённый монитор возвращается на экран',
    () {
      const screens = [Rect.fromLTWH(0, 0, 1920, 1040)];
      const visible = Rect.fromLTWH(100, 120, 1100, 700);
      expect(fitWindow(visible, screens), visible);
      expect(
        fitWindow(const Rect.fromLTWH(-1600, -100, 2400, 1200), screens),
        screens.single,
      );
      const left = Rect.fromLTWH(-1920, 0, 1920, 1040);
      expect(
        fitWindow(const Rect.fromLTWH(-1800, 50, 1000, 700), [
          left,
          ...screens,
        ]),
        const Rect.fromLTWH(-1800, 50, 1000, 700),
      );
    },
  );

  test('Повреждённое сохранение не создаёт невидимое окно', () {
    expect(
      parsePlacement({
        'x': 1,
        'y': 1,
        'width': -1,
        'height': 0,
        'maximized': true,
        'fullScreen': false,
      }),
      isNull,
    );
    expect(parsePlacement({'invalid': true}), isNull);
  });
}
