/// Which way gravity pulls, in screen terms.
enum Tilt {
  /// Toward the screen's bottom edge (phone upright).
  down,

  /// Toward the screen's top edge (phone upside down).
  up,

  /// Lying flat or on its side: like a real hourglass, the sand stops.
  level,
}

/// The sand in an hourglass, as pure state so it can be unit tested.
///
/// Sand only ever moves from the upper bulb to the lower one at a constant
/// rate (real hourglasses flow at a near-constant rate regardless of how
/// full they are), so a full bulb empties in exactly [duration]. Flipping the
/// phone swaps which bulb is upper, and whatever is left runs back.
class SandGlass {
  SandGlass(this.duration);

  /// How long a full bulb takes to empty.
  Duration duration;

  /// Fraction of all the sand in the bulb at the screen's top edge (0…1).
  double topSand = 0;

  /// Last vertical direction; kept while [Tilt.level] so the glass
  /// remembers which bulb was upper.
  Tilt _vertical = Tilt.down;
  Tilt _tilt = Tilt.down;
  bool _running = false;
  bool _finished = false;

  /// Sand drained since the last flip — the top surface caves in as it grows.
  double drainedSinceFlip = 0;

  Tilt get tilt => _tilt;
  Tilt get vertical => _vertical;
  bool get running => _running;
  bool get finished => _finished;

  double get bottomSand => 1 - topSand;

  /// Sand in whichever bulb is on top right now (or was, before lying down).
  double get upperSand => _vertical == Tilt.up ? bottomSand : topSand;

  bool get flowing => _running && _tilt != Tilt.level && upperSand > 0;

  /// Sand per second — also how thick the stream looks.
  double get rate => 1 / (duration.inMicroseconds / 1e6);

  Duration get remaining => duration * upperSand;

  // Hysteresis: a held phone (~45–60° back) keeps flowing; only near
  // horizontal does it stop.
  static const _flowAbove = 0.3;
  static const _stopBelow = 0.2;

  /// [g] is the accelerometer's y reading divided by 9.81: +1 upright,
  /// -1 upside down, 0 flat or sideways.
  void setGravity(double g) {
    final Tilt next;
    if (g.abs() >= _flowAbove) {
      next = g > 0 ? Tilt.down : Tilt.up;
    } else if (g.abs() < _stopBelow) {
      next = Tilt.level;
    } else {
      // In the dead band: keep flowing the current way, if flowing at all.
      next = _tilt == Tilt.level ? Tilt.level : (g > 0 ? Tilt.down : Tilt.up);
    }
    if (next != Tilt.level && next != _vertical) {
      _vertical = next;
      drainedSinceFlip = 0;
      if (upperSand > 0) _finished = false;
    }
    _tilt = next;
  }

  /// Setup: all the sand rests in the lower bulb, not running.
  void settle() {
    _running = false;
    _finished = false;
    topSand = _vertical == Tilt.up ? 1 : 0;
    drainedSinceFlip = 0;
  }

  /// Start: all the sand in the upper bulb, flowing.
  void start() {
    topSand = _vertical == Tilt.up ? 0 : 1;
    drainedSinceFlip = 0;
    _finished = false;
    _running = true;
  }

  /// Moves sand for [dt] of wall-clock time. Returns true on the frame the
  /// upper bulb runs out.
  bool advance(Duration dt) {
    if (!flowing) return false;
    final amount = rate * dt.inMicroseconds / 1e6;
    final moved = amount < upperSand ? amount : upperSand;
    topSand += _vertical == Tilt.up ? moved : -moved;
    topSand = topSand.clamp(0.0, 1.0);
    drainedSinceFlip += moved;
    if (upperSand <= 1e-9) {
      topSand = _vertical == Tilt.up ? 1 : 0;
      if (!_finished) {
        _finished = true;
        return true;
      }
    }
    return false;
  }
}
