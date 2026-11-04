import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components_cubit.dart';
import 'editor_cubit.dart';

class SetupBanner extends StatelessWidget {
  const SetupBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ComponentsCubit, ComponentsState>(
        builder: (context, state) {
          if (state.ready) return const SizedBox.shrink();
          final progress = state.progress;
          final done = progress?.completed;
          final total = progress?.total;
          final fraction = done == null || total == null ? null : done / total;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.busy
                              ? Icons.downloading_rounded
                              : Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            progress?.label ??
                                state.message ??
                                'Готовим локальную проверку',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (state.busy)
                          TextButton(
                            onPressed: context.read<ComponentsCubit>().cancel,
                            child: const Text('Остановить'),
                          )
                        else
                          TextButton(
                            onPressed: () =>
                                context.read<ComponentsCubit>().prepare(
                                  context.read<EditorCubit>().state.settings,
                                ),
                            child: Text(
                              state.stopped ? 'Продолжить' : 'Повторить',
                            ),
                          ),
                      ],
                    ),
                    if (state.busy) LinearProgressIndicator(value: fraction),
                    if (fraction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          progressLabel(done!, total!),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

String progressLabel(int done, int total) {
  final percent = (done / total * 100).round();
  if (total <= 1000) return '$percent%';
  const mb = 1024 * 1024;
  return '${(done / mb).toStringAsFixed(1)} / ${(total / mb).toStringAsFixed(1)} МБ · $percent%';
}
