import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const dictionaryHashes = {
  'known-ru.txt':
      '3a6c36697585f53e5685914b1de64f4199f45563d0e17ab98fe8feb6cb1e9901',
  'frequency-ru.tsv':
      '0899dd5ed4899b7b56d80babf1be8636fd92a371b98ed12fc2755c293257aa4b',
  'frequency-en.tsv':
      'bbc3ffab0a8dbe3485523fbbc906f3dcad4a76fafe61022d3633ef00f5a61c12',
  'hunspell/ru_RU.aff':
      '38ce7d4af78e211e9bafe4bf7e3d6a2c420591136cb738ec6648f8fdf6524cd7',
  'hunspell/ru_RU.dic':
      'f6047416a0204adbecf3a451b874ec8a97ee37e2cbc714466ef04d8dbcc0d6fc',
  'hunspell/en_US.aff':
      'e746c882dd6f303c2c46e7452804b9201115a6942cfeb15f18f8edf774d2e24e',
  'hunspell/en_US.dic':
      'f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647',
};

Future<bool> validDictionaries(String path) =>
    Isolate.run(() => _checkFiles(path, dictionaryHashes));

Future<bool> _checkFiles(String root, Map<String, String> hashes) async {
  try {
    for (final entry in hashes.entries) {
      final file = File(p.joinAll([root, ...p.posix.split(entry.key)]));
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (hash != entry.value) return false;
    }
    return true;
  } on Exception {
    return false;
  }
}

Future<bool> validLanguageTool(String path) => Isolate.run(() async {
  try {
    final manifest = jsonDecode(
      await File(p.join(path, 'installation-manifest.json')).readAsString(),
    ) as Map<String, dynamic>;
    final files = (manifest['files'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final hashes = {
      for (final entry in files)
        p.posix.join('lib', entry['name'] as String): entry['sha256'] as String,
    };
    if (!hashes.containsKey('lib/languagetool-server-6.8.jar')) return false;
    return await _checkFiles(path, hashes);
  } on Exception {
    return false;
  }
});
