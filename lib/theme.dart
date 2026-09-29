import 'package:flutter/material.dart';

/// Pomee's colour tokens. Read them with `PomeeColors.of(context)`.
@immutable
class PomeeColors extends ThemeExtension<PomeeColors> {
  const PomeeColors({
    required this.background,
    required this.ink,
    required this.dim,
    required this.track,
    required this.work,
    required this.rest,
    required this.onAccent,
  });

  final Color background;
  final Color ink;
  final Color dim;
  final Color track;
  final Color work;
  final Color rest;

  /// Text and icons on [work] / [rest] (the thumb, the rising water).
  final Color onAccent;

  static const light = PomeeColors(
    background: Color(0xFFF7F5F2),
    ink: Color(0xFF1C1B1A),
    dim: Color(0x591C1B1A),
    track: Color(0x141C1B1A),
    work: Color(0xFFE5484D),
    rest: Color(0xFF3FA37A),
    onAccent: Color(0xFF1C1B1A),
  );

  static const dark = PomeeColors(
    background: Color(0xFF111110),
    ink: Color(0xFFEDEBE8),
    dim: Color(0x59EDEBE8),
    track: Color(0x1AEDEBE8),
    work: Color(0xFFFF6369),
    rest: Color(0xFF4CC38A),
    onAccent: Color(0xFF111110),
  );

  static PomeeColors of(BuildContext context) =>
      Theme.of(context).extension<PomeeColors>()!;

  @override
  PomeeColors copyWith({
    Color? background,
    Color? ink,
    Color? dim,
    Color? track,
    Color? work,
    Color? rest,
    Color? onAccent,
  }) => PomeeColors(
    background: background ?? this.background,
    ink: ink ?? this.ink,
    dim: dim ?? this.dim,
    track: track ?? this.track,
    work: work ?? this.work,
    rest: rest ?? this.rest,
    onAccent: onAccent ?? this.onAccent,
  );

  @override
  PomeeColors lerp(PomeeColors? other, double t) {
    if (other == null) return this;
    return PomeeColors(
      background: Color.lerp(background, other.background, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      track: Color.lerp(track, other.track, t)!,
      work: Color.lerp(work, other.work, t)!,
      rest: Color.lerp(rest, other.rest, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Light, dark, or follow the phone. Starts on system; the top-right toggle
/// switches it.
final themeMode = ValueNotifier(ThemeMode.system);

/// Body text, labels and buttons (Poppins).
const textFont = 'PomeeText';

/// The big numbers and the title (Poppins, heavy weights).
const displayFont = 'PomeeDisplay';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? PomeeColors.dark
      : PomeeColors.light;
  return ThemeData(
    brightness: brightness,
    fontFamily: textFont,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.work,
      brightness: brightness,
      surface: c.background,
    ),
    splashFactory: NoSplash.splashFactory,
    extensions: [c],
  );
}
