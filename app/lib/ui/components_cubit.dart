import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/local_components.dart';
import '../domain/settings.dart';

typedef ComponentsState = ({
  ComponentStatus? status,
  bool busy,
  DownloadProgress? progress,
  String? message,
});

class ComponentsCubit extends Cubit<ComponentsState> {
  ComponentsCubit(this.components)
    : super((status: null, busy: false, progress: null, message: null));
  final LocalComponents components;

  Future<void> refresh(Settings settings) async {
    if (state.busy) return;
    emit((status: state.status, busy: true, progress: null, message: null));
    final status = await components.status(settings);
    if (!isClosed) {
      emit((status: status, busy: false, progress: null, message: null));
    }
  }

  Future<void> download(Settings settings) async {
    if (state.busy) return;
    emit((status: state.status, busy: true, progress: null, message: null));
    var complete = false;
    try {
      await for (final progress in components.pull(settings)) {
        if (isClosed) return;
        complete = progress.status == 'success';
        emit((
          status: state.status,
          busy: true,
          progress: progress,
          message: null,
        ));
      }
      if (!complete) throw StateError('Загрузка прервалась');
      if (!isClosed) {
        emit((status: null, busy: false, progress: null, message: null));
        await refresh(settings);
      }
    } catch (_) {
      if (!isClosed) {
        emit((
          status: state.status,
          busy: false,
          progress: null,
          message: 'Не удалось скачать модель. Проверьте Ollama и интернет. Повторная попытка продолжит загрузку.',
        ));
      }
    }
  }

  @override
  Future<void> close() {
    components.close();
    return super.close();
  }
}
