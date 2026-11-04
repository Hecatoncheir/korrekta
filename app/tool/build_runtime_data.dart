import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Использование: dart run tool/build_runtime_data.dart <папка компонентов> <архив.zip>',
    );
    exitCode = 64;
    return;
  }
  await buildData(Directory(args[0]), File(args[1]));
}

Future<void> buildData(Directory source, File output) async {
  final dictionary = Directory(p.join(source.path, 'dictionaries-v1'));
  final frozen = jsonDecode(
    await File('../benchmarks/dictionaries/data-manifest.json').readAsString(),
  ) as Map<String, dynamic>;
  final artifacts = frozen['artifacts'] as Map<String, dynamic>;
  final libraries = Directory(
    p.join(source.path, 'languagetool', '6.8', 'lib'),
  );
  final ltManifest = File(
    p.join(libraries.parent.path, 'installation-manifest.json'),
  );
  final lt =
      jsonDecode(await ltManifest.readAsString()) as Map<String, dynamic>;
  await output.parent.create(recursive: true);
  final zip = ZipFileEncoder()..create(output.path, level: 6);
  try {
    for (final name in [
      'known-ru.txt',
      'frequency-ru.tsv',
      'frequency-en.tsv',
      'hunspell/ru_RU.aff',
      'hunspell/ru_RU.dic',
      'hunspell/en_US.aff',
      'hunspell/en_US.dic',
      'hunspell/README_ru_RU.txt',
      'hunspell/license.txt',
    ]) {
      final file = File(p.joinAll([dictionary.path, ...p.posix.split(name)]));
      await verify(
        file,
        (artifacts[name] as Map<String, dynamic>)['sha256'] as String,
      );
      await zip.addFile(file, p.posix.join('dictionaries-v1', name));
    }
    await zip.addFile(
      File(p.join(dictionary.path, 'manifest.json')),
      'dictionaries-v1/manifest.json',
    );
    await addFolder(
      zip,
      Directory(
        p.join(dictionary.path, 'native', 'ucrt64', 'share', 'licenses'),
      ),
      'SOURCES/msys2-licenses',
    );
    final native = Directory(
      p.join(dictionary.path, 'native', 'ucrt64', 'bin'),
    );
    await for (final file
        in native.list().where((f) => f is File).cast<File>()) {
      if (p.extension(file.path) == '.dll' ||
          p.basename(file.path) == 'hunspell.exe') {
        await zip.addFile(
          file,
          p.posix.join(
            'dictionaries-v1/native/ucrt64/bin',
            p.basename(file.path),
          ),
        );
      }
    }
    for (final entry
        in (lt['files'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final file = File(p.join(libraries.path, entry['name'] as String));
      await verify(file, entry['sha256'] as String);
      await zip.addFile(
        file,
        p.posix.join('languagetool/6.8/lib', p.basename(file.path)),
        0,
      );
    }
    await zip.addFile(
      ltManifest,
      'languagetool/6.8/installation-manifest.json',
    );
    await zip.addFile(
      File(p.join(source.path, 'languagetool', '6.8', 'server.properties')),
      'languagetool/6.8/server.properties',
    );
    await zip.addFile(
      File('../benchmarks/languagetool/runtime/pom.xml'),
      'SOURCES/languagetool-pom.xml',
    );
    await zip.addFile(
      File(
        p.join(
          dictionary.path,
          'pymorphy3_dicts_ru-2.4.417150.4580142-py2.py3-none-any.whl',
        ),
      ),
      'SOURCES/opencorpora-source.whl',
      0,
    );
    await zip.addFile(
      File('../packaging/components/NOTICE.md'),
      'SOURCES/NOTICE.md',
    );
  } finally {
    await zip.close();
  }
  final metadata = {
    'file': p.basename(output.path),
    'bytes': await output.length(),
    'sha256': await digest(output),
    'languageTool': '6.8',
    'hunspell': '1.7.5',
  };
  await File(
    '${output.path}.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(metadata)}\n');
  stdout.writeln(jsonEncode(metadata));
}

Future<void> addFolder(
  ZipFileEncoder zip,
  Directory folder,
  String prefix,
) async {
  await for (final file
      in folder
          .list(recursive: true, followLinks: false)
          .where((f) => f is File)
          .cast<File>()) {
    final relative = p.posix.joinAll(
      p.split(p.relative(file.path, from: folder.path)),
    );
    await zip.addFile(file, p.posix.join(prefix, relative));
  }
}

Future<String> digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> verify(File file, String expected) async {
  if (await digest(file) != expected) {
    throw StateError('Не совпал проверенный файл: ${p.basename(file.path)}');
  }
}
