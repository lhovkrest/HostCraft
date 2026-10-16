import 'package:flutter/material.dart';

extension HostCraftColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}

class Appearance extends InheritedWidget {
  const Appearance({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static Appearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Appearance>()!;

  @override
  bool updateShouldNotify(Appearance oldWidget) => oldWidget.mode != mode;
}

ThemeData hostCraftTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xff101615) : const Color(0xfff4f6f5);
  final surface = dark ? const Color(0xff1a2320) : Colors.white;
  final primary = dark ? const Color(0xff8fe0b6) : const Color(0xff166745);
  final ink = dark ? const Color(0xffe7eee9) : const Color(0xff172d23);
  final secondaryInk = dark ? const Color(0xffa1afa7) : const Color(0xff5b6b62);
  final line = dark ? const Color(0xff304039) : const Color(0xffdce4df);
  final subtle = dark ? const Color(0xff202e26) : const Color(0xffe8f1eb);
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  ).copyWith(
    primary: primary,
    onPrimary: dark ? const Color(0xff103e28) : Colors.white,
    primaryContainer: subtle,
    onPrimaryContainer: ink,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: secondaryInk,
    surfaceContainerLowest: background,
    surfaceContainerLow: dark ? const Color(0xff131d18) : const Color(0xfff7f9f7),
    surfaceContainer: subtle,
    surfaceContainerHigh: dark ? const Color(0xff26382d) : const Color(0xffeaf0ec),
    outlineVariant: line,
    outline: dark ? const Color(0xff6d8174) : const Color(0xff7f9285),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    dividerColor: line,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 76,
      titleSpacing: 22,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      labelStyle: TextStyle(color: secondaryInk, fontSize: 13),
      hintStyle: TextStyle(color: secondaryInk, fontSize: 13),
      helperStyle: TextStyle(color: secondaryInk, fontSize: 11),
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: line),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        shape: shape,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: subtle,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: background,
      indicatorColor: subtle,
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(color: secondaryInk),
      selectedLabelTextStyle: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: secondaryInk, fontSize: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: shape,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: shape,
    ),
  );
}
