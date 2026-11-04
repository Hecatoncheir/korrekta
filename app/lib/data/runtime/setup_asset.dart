import 'dart:ffi';
import 'dart:io';

import '../../domain/setup.dart';

class SetupAsset {
  const SetupAsset({
    required this.id,
    required this.label,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.expandedBytes,
    required this.markers,
  });
  final String id, label, sha256;
  final Uri url;
  final int bytes, expandedBytes;
  final List<String> markers;

  factory SetupAsset.fromJson(Map<String, dynamic> json) => switch (json) {
    {
      'id': String id,
      'label': String label,
      'url': String url,
      'bytes': int bytes,
      'sha256': String sha,
      'expandedBytes': int expanded,
      'markers': List<dynamic> markers,
    }
        when bytes > 0 &&
            expanded > 0 &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) =>
      SetupAsset(
        id: id,
        label: label,
        url: Uri.parse(url),
        bytes: bytes,
        sha256: sha,
        expandedBytes: expanded,
        markers: List.unmodifiable(markers.cast<String>()),
      ),
    _ => throw const FormatException('Неверный каталог компонентов'),
  };
}

class SetupCatalog {
  SetupCatalog(this.assets, this.platform);
  final Map<String, dynamic> assets;
  final String platform;

  static String currentPlatform() =>
      switch ((Platform.operatingSystem, Abi.current())) {
        ('windows', Abi.windowsX64) => 'windows-x64',
        ('linux', Abi.linuxX64) => 'linux-x64',
        ('macos', Abi.macosX64) => 'macos-x64',
        ('macos', Abi.macosArm64) => 'macos-arm64',
        _ => throw const SetupFailure(
          'Автоматическая подготовка доступна для Windows x64, Linux x64 и macOS Intel / Apple Silicon.',
        ),
      };

  SetupAsset asset(String name) {
    final variants = assets[name] as Map<String, dynamic>;
    return SetupAsset.fromJson(
      (variants[platform] ?? variants['all']) as Map<String, dynamic>,
    );
  }
}
