import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update_api.dart';
import '../data/update_download.dart';
import '../data/update_installer.dart';
import '../domain/app_release.dart';

enum UpdateStatus {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  failed,
}

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.version = '',
    this.release,
    this.progress,
    this.file,
    this.digest,
    this.message,
  });
  final UpdateStatus status;
  final String version;
  final AppRelease? release;
  final double? progress;
  final File? file;
  final String? digest, message;
  bool get busy =>
      status == UpdateStatus.checking || status == UpdateStatus.downloading;
}

class UpdateCubit extends Cubit<UpdateState> {
  UpdateCubit({
    required this.api,
    required this.downloads,
    required this.installer,
    required this.version,
    this.beforeRestart,
    this.onExit = exit,
  }) : super(const UpdateState());
  final UpdateApi api;
  final UpdateDownload downloads;
  final UpdateInstaller installer;
  final Future<String> version;
  final Future<void> Function()? beforeRestart;
  final void Function(int) onExit;

  factory UpdateCubit.live(
    Directory directory,
    Future<void> Function() beforeRestart,
  ) {
    final client = http.Client();
    final downloads = UpdateDownload(client, directory);
    return UpdateCubit(
      api: UpdateApi(client),
      downloads: downloads,
      installer: UpdateInstaller(downloads),
      version: PackageInfo.fromPlatform().then((info) => info.version),
      beforeRestart: beforeRestart,
    );
  }

  Future<void> check() async {
    if (state.busy || state.status == UpdateStatus.ready) return;
    emit(UpdateState(status: UpdateStatus.checking, version: state.version));
    try {
      final current = await version;
      final release = await api.latest(
        installerSuffix(Platform.operatingSystem),
      );
      if (isClosed) return;
      if (release == null || !newerVersion(release.version, current)) {
        emit(UpdateState(status: UpdateStatus.current, version: current));
        return;
      }
      emit(
        UpdateState(
          status: UpdateStatus.available,
          version: current,
          release: release,
        ),
      );
      await restoreDownload(release);
    } catch (_) {
      if (!isClosed) {
        emit(
          UpdateState(
            status: UpdateStatus.failed,
            version: state.version,
            message: 'Не удалось проверить обновления. Попробуйте позже.',
          ),
        );
      }
    }
  }

  Future<void> restoreDownload(AppRelease release) async {
    final asset = release.installer;
    if (!installer.installed || asset == null) return;
    final digest = await api.checksum(release);
    final cached = await downloads.cached(asset, digest);
    if (cached != null && !isClosed) {
      emit(
        UpdateState(
          status: UpdateStatus.ready,
          version: state.version,
          release: release,
          file: cached,
          digest: digest,
        ),
      );
    }
  }

  Future<void> download() async {
    final release = state.release;
    final asset = release?.installer;
    if (state.busy || release == null || asset == null) return;
    emit(
      UpdateState(
        status: UpdateStatus.downloading,
        version: state.version,
        release: release,
        progress: 0,
      ),
    );
    var percent = -1;
    try {
      final digest = await api.checksum(release);
      final file = await downloads.download(asset, digest, (progress) {
        final next = (progress * 100).floor();
        if (isClosed || percent == next) return;
        percent = next;
        emit(
          UpdateState(
            status: UpdateStatus.downloading,
            version: state.version,
            release: release,
            progress: progress,
          ),
        );
      });
      if (!isClosed) {
        emit(
          UpdateState(
            status: UpdateStatus.ready,
            version: state.version,
            release: release,
            file: file,
            digest: digest,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          UpdateState(
            status: UpdateStatus.available,
            version: state.version,
            release: release,
            message: 'Не удалось скачать или проверить обновление. Повторите попытку.',
          ),
        );
      }
    }
  }

  Future<void> restart() async {
    final UpdateState(:file, :digest, :release) = state;
    final asset = release?.installer;
    if (file == null || digest == null || asset == null) return;
    try {
      await beforeRestart?.call();
      await installer.launch(file, asset, digest);
      onExit(0);
    } catch (_) {
      if (!isClosed) {
        emit(
          UpdateState(
            status: UpdateStatus.ready,
            version: state.version,
            release: release,
            file: file,
            digest: digest,
            message: 'Не удалось начать обновление. Дождитесь проверки текста и повторите попытку; черновик должен быть сохранён.',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    api.client.close();
    return super.close();
  }
}
