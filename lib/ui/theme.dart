import 'package:flutter/material.dart';

/// Colours that Material's [ColorScheme] has no slot for. Every screen reads
/// them through `context.hc`, so one place defines both light and dark mode.
@immutable
class HostColors extends ThemeExtension<HostColors> {
  const HostColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.warning,
    required this.danger,
    required this.info,
    required this.consoleBackground,
    required this.consoleText,
    required this.consoleLineNumber,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color warning;
  final Color danger;
  final Color info;
  final Color consoleBackground;
  final Color consoleText;
  final Color consoleLineNumber;

  static const dark = HostColors(
    background: Color(0xff0e1311),
    surface: Color(0xff161d1a),
    surfaceAlt: Color(0xff1e2824),
    border: Color(0xff26332d),
    text: Color(0xffe8efeb),
    muted: Color(0xff8e9d96),
    accent: Color(0xff5bdb9b),
    onAccent: Color(0xff06130c),
    accentSoft: Color(0xff1f3a2d),
    warning: Color(0xffe9c46a),
    danger: Color(0xffff8a80),
    info: Color(0xff8ec5ff),
    consoleBackground: Color(0xff0a0f0d),
    consoleText: Color(0xffc3dccb),
    consoleLineNumber: Color(0xff56685e),
  );

  static const light = HostColors(
    background: Color(0xfff3f6f4),
    surface: Color(0xffffffff),
    surfaceAlt: Color(0xffebf1ed),
    border: Color(0xffd9e2dd),
    text: Color(0xff14201a),
    muted: Color(0xff5d6d65),
    accent: Color(0xff12804e),
    onAccent: Color(0xffffffff),
    accentSoft: Color(0xffd5ecdf),
    warning: Color(0xff8a5a00),
    danger: Color(0xffb3261e),
    info: Color(0xff1b5e99),
    consoleBackground: Color(0xfff7faf8),
    consoleText: Color(0xff22362b),
    consoleLineNumber: Color(0xff9aaba1),
  );

  @override
  HostColors copyWith() => this;

  @override
  HostColors lerp(ThemeExtension<HostColors>? other, double t) {
    if (other is! HostColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return HostColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      consoleBackground: mix(consoleBackground, other.consoleBackground),
      consoleText: mix(consoleText, other.consoleText),
      consoleLineNumber: mix(consoleLineNumber, other.consoleLineNumber),
    );
  }
}

extension HostColorsContext on BuildContext {
  HostColors get hc => Theme.of(this).extension<HostColors>() ?? HostColors.dark;
}

/// Flat design: solid tonal surfaces, hairline borders, no elevation,
/// gradients or shadows anywhere.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? HostColors.dark : HostColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    secondaryContainer: c.accentSoft,
    onSecondaryContainer: c.text,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerHighest: c.surfaceAlt,
    outline: c.border,
    outlineVariant: c.border,
    error: c.danger,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  OutlineInputBorder field(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: width == 0
        ? BorderSide.none
        : BorderSide(color: color, width: width),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    splashFactory: InkRipple.splashFactory,
    extensions: [c],
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      border: field(c.border, 0),
      enabledBorder: field(c.border, 0),
      disabledBorder: field(c.border, 0),
      focusedBorder: field(c.accent, 2),
      errorBorder: field(c.danger, 1),
      focusedErrorBorder: field(c.danger, 2),
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        elevation: 0,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: c.border),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.background,
      indicatorColor: c.accentSoft,
      elevation: 0,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.surfaceAlt,
      thumbColor: c.accent,
      overlayColor: c.accent.withValues(alpha: .12),
      trackHeight: 4,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.background),
      shape: shape,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        elevation: 0,
        side: BorderSide(color: c.border),
      ),
    ),
  );
}
