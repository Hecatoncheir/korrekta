import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'navigation_cubit.dart';
import 'update_cubit.dart';

class UpdateAnnouncer extends StatelessWidget {
  const UpdateAnnouncer({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => BlocListener<UpdateCubit, UpdateState>(
    listenWhen: (before, after) =>
        before.status == UpdateStatus.checking &&
        after.status == UpdateStatus.available,
    listener: (context, state) {
      final navigation = context.read<NavigationCubit>();
      if (navigation.state == AppSection.settings) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Доступна Корректа ${state.release?.version}'),
          action: SnackBarAction(
            label: 'Обновить',
            onPressed: () => navigation.select(AppSection.settings),
          ),
        ),
      );
    },
    child: child,
  );
}
