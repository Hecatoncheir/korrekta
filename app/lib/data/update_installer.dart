import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../domain/app_release.dart';
import 'update_download.dart';

String installerSuffix(String os) => switch (os) {
  'windows' => 'windows-x64-setup.exe',
  'linux' => 'linux-x64.run',
  'macos' => 'macos-universal.dmg',
  _ => throw UnsupportedError(os),
};

class UpdateInstaller {
  UpdateInstaller(this.downloads, {String? executable})
    : executable = executable ?? Platform.resolvedExecutable;
  final UpdateDownload downloads;
  final String executable;

  String get appBundle => p.dirname(p.dirname(p.dirname(executable)));

  bool get installed => switch (Platform.operatingSystem) {
    'windows' => File(
      p.join(p.dirname(executable), 'unins000.exe'),
    ).existsSync(),
    'linux' => File(
      p.join(p.dirname(executable), 'korrekta.desktop'),
    ).existsSync(),
    'macos' =>
      p.basename(appBundle) == 'Корректа.app' &&
          !appBundle.startsWith('/Volumes/'),
    _ => false,
  };

  Future<void> launch(File setup, ReleaseAsset asset, String digest) async {
    if (!installed) {
      throw StateError('Обновлять можно только установленную копию');
    }
    if (!await downloads.verified(setup, asset, digest)) {
      throw StateError('Обновление изменилось после загрузки');
    }
    final log = p.join(setup.parent.path, 'update.log');
    await checkBundleAccess();
    final (program, arguments) = await command(setup.path, log);
    await Process.start(program, arguments, mode: ProcessStartMode.detached);
  }

  Future<(String, List<String>)> command(String setup, String log) async =>
      switch (Platform.operatingSystem) {
        'windows' => (
          setup,
          [
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/SP-',
            '/CLOSEAPPLICATIONS',
            '/RELAUNCH',
            '/DIR=${p.dirname(executable)}',
            '/LOG=$log',
          ],
        ),
        'linux' => (
          '/bin/bash',
          [
            setup,
            '--wait-pid',
            '$pid',
            '--relaunch',
            '--target',
            p.dirname(executable),
            '--log',
            log,
          ],
        ),
        'macos' => (
          '/bin/bash',
          [await macHelper(), setup, appBundle, '$pid', log],
        ),
        _ => throw UnsupportedError(Platform.operatingSystem),
      };

  Future<String> macHelper() async {
    final helper = File(p.join(downloads.directory.path, 'update-macos.sh'));
    await helper.writeAsString(
      await rootBundle.loadString('assets/update-macos.sh'),
      flush: true,
    );
    return helper.path;
  }

  Future<void> checkBundleAccess() async {
    if (!Platform.isMacOS) return;
    final result = await Process.run('/usr/bin/test', [
      '-w',
      p.dirname(appBundle),
    ]);
    if (result.exitCode != 0) {
      throw StateError('Папка приложения недоступна для обновления');
    }
  }
}
