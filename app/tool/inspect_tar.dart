import 'dart:io';
import 'dart:convert';

import 'package:tar/tar.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Использование: dart run tool/inspect_tar.dart <архив.tar.gz>',
    );
    exitCode = 64;
    return;
  }
  final file = File(args.single);
  final reader = TarReader(
    file.openRead().transform(gzip.decoder),
    maxSpecialFileSize: 1024 * 1024,
  );
  var size = 0;
  final names = <String>{};
  final repeated = <String>[];
  final links = <String>[];
  try {
    while (await reader.moveNext()) {
      final entry = reader.current;
      size += entry.size;
      if (!names.add(entry.name)) repeated.add(entry.name);
      if (entry.type == TypeFlag.symlink) {
        links.add('${entry.name} -> ${entry.header.linkName}');
      }
    }
  } finally {
    await reader.cancel();
  }
  stdout.writeln(
    jsonEncode({
      'bytes': size,
      'entries': names.length,
      'duplicates': repeated,
      'links': links,
    }),
  );
}
