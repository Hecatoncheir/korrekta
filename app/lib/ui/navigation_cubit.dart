import 'package:flutter_bloc/flutter_bloc.dart';

enum AppSection { editor, settings }

class NavigationCubit extends Cubit<AppSection> {
  NavigationCubit() : super(AppSection.editor);
  void select(AppSection section) => emit(section);
}
