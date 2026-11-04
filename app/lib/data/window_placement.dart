import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

typedef WindowPlacement = ({Rect bounds, bool maximized, bool fullScreen});

class WindowPlacementStore {
  const WindowPlacementStore(this.file);
  final File file;

  Future<WindowPlacement?> load() async {
    if (!await file.exists()) return null;
    try {
      return parsePlacement(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(WindowPlacement placement) async {
    await file.parent.create(recursive: true);
    final (:bounds, :maximized, :fullScreen) = placement;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
        'maximized': maximized,
        'fullScreen': fullScreen,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

WindowPlacement? parsePlacement(Object? json) => switch (json) {
  {
    'x': num x,
    'y': num y,
    'width': num width,
    'height': num height,
    'maximized': bool maximized,
    'fullScreen': bool fullScreen,
  }
      when [x, y, width, height].every((n) => n.isFinite) &&
          width > 0 &&
          height > 0 =>
    (
      bounds: Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
      maximized: maximized,
      fullScreen: fullScreen,
    ),
  _ => null,
};

Rect fitWindow(Rect bounds, List<Rect> screens) {
  if (screens.isEmpty) return bounds;
  final screen = screens.reduce(
    (left, right) =>
        overlapArea(bounds, right) > overlapArea(bounds, left) ? right : left,
  );
  final width = math.min(bounds.width, screen.width);
  final height = math.min(bounds.height, screen.height);
  return Rect.fromLTWH(
    bounds.left.clamp(screen.left, screen.right - width),
    bounds.top.clamp(screen.top, screen.bottom - height),
    width,
    height,
  );
}

double overlapArea(Rect left, Rect right) {
  final overlap = left.intersect(right);
  return overlap.isEmpty ? 0 : overlap.width * overlap.height;
}
