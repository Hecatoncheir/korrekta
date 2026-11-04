import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_cubit.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<UpdateCubit, UpdateState>(
    builder: (context, state) {
      final updates = context.read<UpdateCubit>();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Обновления', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(updateLabel(state)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: state.busy ? null : updates.check,
                child: const Text('Проверить обновления'),
              ),
              if (state.release case final release?)
                TextButton(
                  onPressed: () => launchUrl(
                    release.page,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Что нового'),
                ),
              if (state.status == UpdateStatus.available &&
                  updates.installer.installed &&
                  state.release?.installer != null)
                FilledButton(
                  onPressed: updates.download,
                  child: const Text('Скачать обновление'),
                ),
              if (state.status == UpdateStatus.ready)
                FilledButton(
                  onPressed: updates.restart,
                  child: const Text('Перезапустить и обновить'),
                ),
            ],
          ),
          if (state.status == UpdateStatus.available &&
              !updates.installer.installed)
            const Text(
              'Эта копия запущена из папки разработки. Установщик доступен на странице релиза.',
            ),
          if (state.status == UpdateStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(value: state.progress),
            ),
          if (state.message case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message),
            ),
        ],
      );
    },
  );
}

String updateLabel(UpdateState state) => switch (state.status) {
  UpdateStatus.idle => 'Версия приложения',
  UpdateStatus.checking => 'Проверяем наличие новой версии…',
  UpdateStatus.current => 'Версия ${state.version} · обновлений нет',
  UpdateStatus.available => 'Доступна версия ${state.release?.version}',
  UpdateStatus.downloading =>
    'Загружаем обновление: ${((state.progress ?? 0) * 100).round()}%',
  UpdateStatus.ready => 'Обновление проверено и готово к установке',
  UpdateStatus.failed => 'Проверка обновлений недоступна',
};
