import 'package:pub_semver/pub_semver.dart';

typedef ReleaseAsset = ({String name, Uri url, int size, String? digest});

class AppRelease {
  const AppRelease(this.version, this.page, this.installer, this.checksums);
  final Version version;
  final Uri page;
  final ReleaseAsset? installer, checksums;
}

Version? releaseVersion(String value) {
  try {
    return Version.parse(value.replaceFirst(RegExp('^v'), ''));
  } on FormatException {
    return null;
  }
}

bool newerVersion(Version candidate, String current) {
  final running = releaseVersion(current);
  if (running == null) return false;
  return Version.parse(candidate.toString().split('+').first) >
      Version.parse(running.toString().split('+').first);
}

Uri trustedReleaseUrl(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      !uri.path.toLowerCase().startsWith('/hecatoncheir/korrekta/releases/') ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Неправильный адрес релиза');
  }
  return uri;
}

ReleaseAsset? parseAsset(Object? json) => switch (json) {
  {'name': String name, 'browser_download_url': String url, 'size': int size}
      when RegExp(r'^[A-Za-z0-9.+_-]+$').hasMatch(name) &&
          size > 0 &&
          size <= 1024 * 1024 * 1024 =>
    (
      name: name,
      url: trustedReleaseUrl(url),
      size: size,
      digest: assetDigest(json),
    ),
  _ => null,
};

String? assetDigest(Map<dynamic, dynamic> json) => switch (json['digest']) {
  String digest when RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) =>
    digest.substring(7).toLowerCase(),
  _ => null,
};

AppRelease? parseRelease(Object? json, String suffix) {
  if (json case {
    'draft': false,
    'tag_name': String tag,
    'html_url': String page,
    'assets': List<dynamic> files,
  }) {
    final version = releaseVersion(tag);
    if (version == null) return null;
    final assets = files.map(parseAsset).nonNulls.toList();
    return AppRelease(
      version,
      trustedReleaseUrl(page),
      assets.where((a) => a.name == 'Korrekta-$version-$suffix').firstOrNull,
      assets.where((a) => a.name == 'SHA256SUMS').firstOrNull,
    );
  }
  return null;
}
