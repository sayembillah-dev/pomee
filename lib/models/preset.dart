/// A screen edge of the phone (in portrait coordinates). The pose sensor
/// reports which one is nearest the user.
///
/// [quarterTurns] is how many clockwise quarter turns content would need to
/// read upright from that edge.
enum Side {
  bottom(0),
  left(1),
  top(2),
  right(3);

  const Side(this.quarterTurns);
  final int quarterTurns;

  static Side fromQuarterTurns(int q) => Side.values[q % 4];
}

class Preset {
  const Preset(this.workMinutes, this.breakMinutes);
  final int workMinutes;
  final int breakMinutes;

  Duration get work => Duration(minutes: workMinutes);
  Duration get rest => Duration(minutes: breakMinutes);
}

/// The four sessions on the home screen's slider, shortest first.
const presets = <Preset>[
  Preset(10, 2),
  Preset(20, 4),
  Preset(25, 5),
  Preset(30, 7),
];

/// 25/5, the classic Pomodoro.
const defaultPreset = 2;
