import 'package:flutter/material.dart';

ThemeData gruvbox(bool dark) {
  final background = Color(dark ? 0xff282828 : 0xfffbf1c7);
  final surface = Color(dark ? 0xff32302f : 0xfff9f5d7);
  final ink = Color(dark ? 0xffebdbb2 : 0xff3c3836);
  final green = Color(dark ? 0xffb8bb26 : 0xff79740e);
  final scheme = ColorScheme.fromSeed(
    seedColor: green,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: surface,
    onSurface: ink,
    primary: green,
    onPrimary: dark ? background : Colors.white,
    error: Color(dark ? 0xfffb4934 : 0xff9d0006),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Nunito Sans',
    useMaterial3: true,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.all(16),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
