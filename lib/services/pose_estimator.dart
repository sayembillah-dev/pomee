import 'dart:math' as math;

import '../models/preset.dart';

enum Pose { flat, tilted }

class PoseState {
  const PoseState({
    required this.side,
    required this.settledSide,
    required this.pickedUp,
  });

  /// Edge facing the user right now — reacts instantly.
  final Side side;

  /// [side] once it has held for a moment with the phone resting. Used while
  /// a session runs, so lifting the phone doesn't restart the timer.
  final Side settledSide;

  final bool pickedUp;

  @override
  bool operator ==(Object other) =>
      other is PoseState &&
      other.side == side &&
      other.settledSide == settledSide &&
      other.pickedUp == pickedUp;

  @override
  int get hashCode => Object.hash(side, settledSide, pickedUp);

  @override
  String toString() =>
      'PoseState($side, settled: $settledSide, pickedUp: $pickedUp)';
}

/// Turns raw accelerometer + gyroscope samples into "which edge faces the
/// user" and "is the phone being held". Pure Dart so it can be unit tested.
///
/// Whenever the phone is tilted even slightly (held, propped, standing), the
/// edge gravity pulls toward is the one facing the user — exact, like system
/// auto-rotate. Lying flat, gravity can't tell, so the side is carried over
/// from the moment it was laid down and then follows spins via the gyroscope.
///
/// Android sensor frame: +x → right edge, +y → top edge, +z out of the screen.
/// At rest the accelerometer reports the "up" direction.
class PoseEstimator {
  // Tuning knobs.
  static const tiltEnter = 14 * math.pi / 180; // tilt above → gravity decides
  static const tiltExit = 8 * math.pi / 180; // tilt below → flat, gyro decides
  static const hysteresis = 20 * math.pi / 180; // past the 45° sector border
  static const gyroDeadband = 0.02; // rad/s, ignored when integrating yaw
  static const rotationLimit = 0.15; // rad/s — above means being handled
  static const linearLimit = 0.6; // m/s² of non-gravity acceleration
  static const disturbHold = Duration(milliseconds: 300);
  static const pickupAfter = Duration(milliseconds: 1200);
  static const putDownAfter = Duration(milliseconds: 500);
  static const settleAfter = Duration(milliseconds: 800);

  /// Any rotation faster than this (rad/s, any axis — including spinning
  /// flat on a desk) means the phone isn't still, so no side is committed.
  static const stillRate = 0.25;

  /// Above this rotation rate, or while the phone is being jolted, gravity
  /// readings are too noisy to pick a side from.
  static const steadyRate = 0.6; // rad/s
  static const jolt = 1.5; // m/s² away from 1 g

  /// Gravity is low-passed, so it stays skewed for a moment after a jolt;
  /// wait this long after the last one before trusting it again.
  static const calmAfter = Duration(milliseconds: 150);

  /// A gravity-read side must hold this long before it's taken — a landing
  /// wobble never points the same way for that long.
  static const snapHold = Duration(milliseconds: 120);

  static const _alpha = 0.6; // gravity low-pass (~40 ms at 50 Hz)
  static const _quarter = math.pi / 2;

  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasGravity = false;
  Pose _pose = Pose.flat;

  // Unbounded quarter-turn index of the current side (mod 4 → Side), and the
  // flat heading in radians, counter-clockwise seen from above.
  int _quarter4 = 0;
  double _heading = 0;
  Duration? _lastGyroAt;

  Side _settled = Side.bottom;
  Duration _sideSince = Duration.zero;

  Duration _lastDisturbAt = Duration.zero;
  Duration _lastMoveAt = Duration.zero;
  double _rotation = 0; // latest gyro magnitude
  Duration _lastShakeAt = Duration.zero;
  int? _pending; // gravity's candidate quarter, not yet held long enough
  Duration _pendingSince = Duration.zero;
  Duration _lastUnrestAt = Duration.zero;
  Duration _lastRestAt = Duration.zero;
  bool _pickedUp = false;

  Side get _side => Side.fromQuarterTurns(_quarter4 % 4);

  PoseState get state =>
      PoseState(side: _side, settledSide: _settled, pickedUp: _pickedUp);

  // Diagnostics for the debug HUD.
  Pose get pose => _pose;
  List<double> get gravity => [_gx, _gy, _gz];
  double get tiltDegrees => _tilt() * 180 / math.pi;
  double get headingDegrees => _heading * 180 / math.pi;
  bool get resting => _lastRestAt >= _lastUnrestAt;

  /// Where the user is, as a continuous angle in the quarter-turn frame
  /// (0 = bottom, π/2 = left, π = top, 3π/2 = right). Drives the "you" marker.
  double get facingAngle => _pose == Pose.tilted ? _gravityAngle() : _heading;

  /// Carries the last known side over (e.g. after the app was backgrounded).
  void restoreSide(Side side) {
    _quarter4 = side.quarterTurns;
    _heading = _quarter4 * _quarter;
    _settled = side;
  }

  /// The user says "this edge faces me" (tapped its label). Re-anchors the
  /// flat heading there. While tilted, gravity stays the source of truth.
  void anchor(Side side) {
    final delta = _wrap((side.quarterTurns - _quarter4) * _quarter);
    _quarter4 += _nearestQuarter(delta);
    _heading = _quarter4 * _quarter;
    _settled = side;
  }

  void addAccel(double x, double y, double z, Duration t) {
    if (!_hasGravity) {
      _gx = x;
      _gy = y;
      _gz = z;
      _hasGravity = true;
      _lastRestAt = _lastUnrestAt = _sideSince = t;
      _pose = _tilt() > tiltEnter ? Pose.tilted : Pose.flat;
      if (_pose == Pose.tilted) {
        _quarter4 = _nearestQuarter(_gravityAngle());
        _settled = _side;
      }
      _heading = _quarter4 * _quarter;
      return;
    }
    _gx = _alpha * _gx + (1 - _alpha) * x;
    _gy = _alpha * _gy + (1 - _alpha) * y;
    _gz = _alpha * _gz + (1 - _alpha) * z;

    final tilt = _tilt();
    if (_pose == Pose.flat && tilt > tiltEnter) {
      _pose = Pose.tilted;
    } else if (_pose == Pose.tilted && tilt < tiltExit) {
      _pose = Pose.flat;
      // Laid down: the edge that faced the user on the way down still does.
      _heading = _quarter4 * _quarter;
    }

    // A hard set-down or a fast turn makes gravity read in random
    // directions; only trust it while the phone is steady.
    final jolted = (math.sqrt(x * x + y * y + z * z) - 9.81).abs() > jolt;
    if (jolted || _rotation > steadyRate) _lastShakeAt = t;
    if (_pose == Pose.tilted) _snapToGravity(t);

    // Non-gravity acceleration. Flat on a desk, only vertical motion counts,
    // so spinning the phone in-plane doesn't read as "picked up".
    final lx = x - _gx, ly = y - _gy, lz = z - _gz;
    final linear = _pose == Pose.flat
        ? lz.abs()
        : math.sqrt(lx * lx + ly * ly + lz * lz);
    if (linear > linearLimit) _lastDisturbAt = t;
    final any = math.sqrt(lx * lx + ly * ly + lz * lz);
    if (any > linearLimit || jolted) _lastMoveAt = t;

    _update(t);
  }

  void addGyro(double x, double y, double z, Duration t) {
    final last = _lastGyroAt;
    _lastGyroAt = t;

    // Spinning flat on the desk only turns around z; any other rotation (or
    // any rotation at all while tilted) means the phone is being moved.
    final rate = _pose == Pose.flat
        ? math.max(x.abs(), y.abs())
        : math.sqrt(x * x + y * y + z * z);
    if (rate > rotationLimit) _lastDisturbAt = t;
    // Stillness for committing a side counts every axis, spins included.
    _rotation = math.sqrt(x * x + y * y + z * z);
    if (_rotation > stillRate) _lastMoveAt = t;

    if (last != null && _pose == Pose.flat && _hasGravity) {
      final dt = (t - last).inMicroseconds / 1e6;
      if (dt > 0 && dt < 0.1 && z.abs() > gyroDeadband) {
        // Face down, screen z points at the floor — flip so heading stays
        // "counter-clockwise from above".
        _heading += (_gz >= 0 ? z : -z) * dt;
        _snapTo(_heading, t);
      }
    }
    _update(t);
  }

  /// Angle of the edge gravity pulls toward, in the same frame as quarter
  /// turns: 0 = bottom, π/2 = left, π = top, 3π/2 = right.
  double _gravityAngle() => math.atan2(_gx, _gy);

  double _tilt() => math.atan2(math.sqrt(_gx * _gx + _gy * _gy), _gz.abs());

  static int _nearestQuarter(double angle) => (angle / _quarter).round();

  /// Like [_snapTo], but only once gravity has been calm and pointing at the
  /// same new sector for [snapHold].
  void _snapToGravity(Duration t) {
    final angle = _gravityAngle();
    final offset = _wrap(angle - _quarter4 * _quarter);
    if (t - _lastShakeAt < calmAfter ||
        offset.abs() <= math.pi / 4 + hysteresis) {
      _pending = null;
      return;
    }
    final target = _quarter4 + _nearestQuarter(offset);
    if (_pending != target) {
      _pending = target;
      _pendingSince = t;
    } else if (t - _pendingSince >= snapHold) {
      _pending = null;
      _snapTo(angle, t);
    }
  }

  /// Moves to the sector containing [angle] once it is clearly past the
  /// current sector's border.
  void _snapTo(double angle, Duration t) {
    final current = _quarter4 * _quarter;
    final offset = _wrap(angle - current);
    if (offset.abs() <= math.pi / 4 + hysteresis) return;
    _quarter4 += _nearestQuarter(offset);
    _sideSince = t;
    if (_pose == Pose.flat) {
      // Keep heading and quarter in the same unwrapped range.
      _heading = current + offset;
    }
  }

  static double _wrap(double a) {
    a = (a + math.pi) % (2 * math.pi);
    return a - math.pi;
  }

  void _update(Duration t) {
    final resting = t - _lastDisturbAt > disturbHold;
    if (resting) {
      _lastRestAt = t;
    } else {
      _lastUnrestAt = t;
    }
    if (!_pickedUp && t - _lastRestAt >= pickupAfter) {
      _pickedUp = true;
    } else if (_pickedUp && t - _lastUnrestAt >= putDownAfter) {
      _pickedUp = false;
    }
    // Commit a new side only once the phone has been completely still —
    // not spinning, not being set down — and facing it for a moment. A
    // fast spin or a clumsy landing passes through other sides without
    // ever holding still on them.
    if (_settled != _side &&
        !_pickedUp &&
        resting &&
        t - _sideSince >= settleAfter &&
        t - _lastMoveAt >= settleAfter &&
        t - _lastUnrestAt >= disturbHold) {
      _settled = _side;
    }
  }
}
