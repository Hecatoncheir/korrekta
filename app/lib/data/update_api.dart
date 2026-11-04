import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/app_release.dart';

class UpdateApi {
  UpdateApi(this.client);
  final http.Client client;
  static final endpoint = Uri.parse(
    'https://api.github.com/repos/Hecatoncheir/korrekta/releases?per_page=20',
  );

  Future<AppRelease?> latest(String suffix) async {
    final response = await client
        .get(
          endpoint,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const HttpException('Не удалось проверить обновления');
    }
    final body = jsonDecode(response.body);
    if (body is! List<dynamic>) {
      throw const FormatException('Неправильный ответ GitHub');
    }
    final releases =
        body.map((json) => parseRelease(json, suffix)).nonNulls.toList()
          ..sort((left, right) => right.version.compareTo(left.version));
    return releases.firstOrNull;
  }

  Future<String> checksum(AppRelease release) async {
    final installer = release.installer;
    if (installer == null) {
      throw const FormatException('В релизе нет установщика для этой ОС');
    }
    if (installer.digest case final digest?) return digest;
    final checksums = release.checksums;
    if (checksums == null) {
      throw const FormatException('В релизе нет контрольной суммы');
    }
    final response = await client
        .get(checksums.url)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.body.length > 16384) {
      throw const FormatException('Не удалось прочитать SHA256SUMS');
    }
    final pattern = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$');
    final hashes = <String>[];
    for (final line in const LineSplitter().convert(response.body)) {
      final match = pattern.firstMatch(line);
      if (match?.group(2) == installer.name) {
        hashes.add(match!.group(1)!.toLowerCase());
      }
    }
    if (hashes.length != 1) {
      throw const FormatException('Неоднозначная контрольная сумма');
    }
    return hashes.single;
  }
}
