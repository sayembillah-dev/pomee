import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/models/preset.dart';
import 'package:pomee/services/pose_estimator.dart';

const _step = Duration(milliseconds: 20); // 50 Hz
const _flat = [0.0, 0.0, 9.81];

/// Gravity for a phone tilted [deg] degrees with [side] as the lowest edge.
List<double> _tilted(Side side, double deg) {
  final a = side.quarterTurns * math.pi / 2; // same frame as the estimator
  final r = deg * math.pi / 180;
  final inPlane = 9.81 * math.sin(r);
  return [inPlane * math.sin(a), inPlane * math.cos(a), 9.81 * math.cos(r)];
}

/// Drives an estimator with synthetic samples on a shared clock.
class _Sim {
  final est = PoseEstimator();
  Duration t = const Duration(seconds: 1);

  void run(
    Duration length, {
    List<double> accel = _flat,
    List<double> gyro = const [0, 0, 0],
  }) {
    final end = t + length;
    while (t < end) {
      est.addAccel(accel[0], accel[1], accel[2], t);
      est.addGyro(gyro[0], gyro[1], gyro[2], t);
      t += _step;
    }
  }
}

void main() {
  test('flat and still: bottom edge, not picked up', () {
    final sim = _Sim()..run(const Duration(seconds: 2));
    expect(
      sim.est.state,
      const PoseState(
        side: Side.bottom,
        settledSide: Side.bottom,
        pickedUp: false,
      ),
    );
  });

  test('a 25° tilt toward any edge selects it within 200 ms', () {
    for (final side in Side.values) {
      final sim = _Sim()
        ..run(const Duration(seconds: 1))
        ..run(const Duration(milliseconds: 200), accel: _tilted(side, 25));
      expect(sim.est.state.side, side, reason: '$side');
    }
  });

  test('standing on each edge selects that edge and settles', () {
    for (final side in Side.values) {
      final sim = _Sim()
        ..run(const Duration(seconds: 1))
        ..run(const Duration(seconds: 2), accel: _tilted(side, 90));
      expect(
        sim.est.state,
        PoseState(side: side, settledSide: side, pickedUp: false),
        reason: '$side',
      );
    }
  });

  test('tilt near a sector border does not flicker', () {
    // 50° between bottom (0°) and left (90°): within hysteresis of bottom.
    final r = 9.81 * math.sin(30 * math.pi / 180);
    final a = 50 * math.pi / 180;
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(
        const Duration(seconds: 1),
        accel: [r * math.sin(a), r * math.cos(a), 8.5],
      );
    expect(sim.est.state.side, Side.bottom);
  });

  test('tilted toward top, then laid flat, keeps top', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(const Duration(milliseconds: 500), accel: _tilted(Side.top, 30))
      ..run(const Duration(seconds: 2));
    expect(sim.est.state.side, Side.top);
  });

  test('spinning flat 90° counter-clockwise selects left without pickup', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(const Duration(seconds: 1), gyro: [0.01, 0.01, math.pi / 2]);
    expect(sim.est.state.side, Side.left);
    expect(sim.est.state.pickedUp, isFalse);
  });

  test('spinning flat 90° clockwise selects right', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(const Duration(seconds: 1), gyro: [0, 0, -math.pi / 2]);
    expect(sim.est.state.side, Side.right);
  });

  test('small spin inside hysteresis keeps the side', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(const Duration(milliseconds: 500), gyro: [0, 0, 1.0]) // ~57°
      ..run(const Duration(seconds: 1));
    expect(sim.est.state.side, Side.bottom);
  });

  test('held in the hand triggers pickup, putting down clears it', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(
        const Duration(seconds: 2),
        accel: _tilted(Side.bottom, 35),
        gyro: [0.4, -0.3, 0.2],
      );
    expect(sim.est.state.pickedUp, isTrue);
    sim.run(const Duration(seconds: 1));
    expect(sim.est.state.pickedUp, isFalse);
  });

  test('lifting and tilting in hand does not change the settled side', () {
    final sim = _Sim()
      ..run(
        const Duration(seconds: 1),
        accel: _tilted(Side.left, 90),
      ) // standing on its left edge
      ..run(
        const Duration(seconds: 2),
        accel: _tilted(Side.bottom, 35),
        gyro: [0.4, -0.3, 0.2],
      );
    expect(sim.est.state.side, Side.bottom);
    expect(sim.est.state.settledSide, Side.left);
    sim.run(const Duration(seconds: 2), accel: _tilted(Side.left, 90));
    expect(sim.est.state.settledSide, Side.left);
  });

  test('brief bump does not count as pickup', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1))
      ..run(const Duration(milliseconds: 400), gyro: [0.5, 0.5, 0])
      ..run(const Duration(seconds: 1));
    expect(sim.est.state.pickedUp, isFalse);
  });

  test('restored side survives startup while flat', () {
    final sim = _Sim();
    sim.est.restoreSide(Side.right);
    sim.run(const Duration(seconds: 2));
    expect(sim.est.state.side, Side.right);
  });

  test('tapping a label re-anchors the side while flat', () {
    final sim = _Sim()..run(const Duration(seconds: 1));
    sim.est.anchor(Side.top);
    expect(sim.est.state.side, Side.top);
    expect(sim.est.state.settledSide, Side.top);
    // A 90° counter-clockwise spin from there moves the user to the right.
    sim.run(const Duration(seconds: 1), gyro: [0, 0, math.pi / 2]);
    expect(sim.est.state.side, Side.right);
  });

  test('gravity overrides a wrong tap while tilted', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1), accel: _tilted(Side.left, 40));
    sim.est.anchor(Side.top);
    sim.run(const Duration(milliseconds: 300), accel: _tilted(Side.left, 40));
    expect(sim.est.state.side, Side.left);
  });

  test('facing angle follows tilt and spin continuously', () {
    final sim = _Sim()
      ..run(const Duration(seconds: 1), accel: _tilted(Side.left, 40));
    expect(sim.est.facingAngle, closeTo(math.pi / 2, 0.05));
    sim
      ..run(const Duration(seconds: 1)) // laid flat: heading starts at left
      ..run(const Duration(milliseconds: 500), gyro: [0, 0, 0.5]);
    expect(sim.est.facingAngle, closeTo(math.pi / 2 + 0.25, 0.05));
  });

  group('switching is strict', () {
    test('a fast spin only commits once the phone is still', () {
      final sim = _Sim()
        ..run(const Duration(seconds: 1))
        // Flicked a quarter turn in 0.25 s.
        ..run(const Duration(milliseconds: 250), gyro: [0, 0, 2 * math.pi]);
      expect(sim.est.state.side, Side.left);
      expect(sim.est.state.settledSide, Side.bottom);
      sim.run(const Duration(milliseconds: 500)); // still, but not long enough
      expect(sim.est.state.settledSide, Side.bottom);
      sim.run(const Duration(milliseconds: 500));
      expect(sim.est.state.settledSide, Side.left);
    });

    test('a spin out and back never switches', () {
      final sim = _Sim()
        ..run(const Duration(seconds: 1))
        ..run(const Duration(milliseconds: 300), gyro: [0, 0, 2 * math.pi])
        ..run(const Duration(milliseconds: 300), gyro: [0, 0, -2 * math.pi])
        ..run(const Duration(seconds: 2));
      expect(sim.est.state.side, Side.bottom);
      expect(sim.est.state.settledSide, Side.bottom);
    });

    test('a slow continuous spin never commits mid-way', () {
      final sim = _Sim()..run(const Duration(seconds: 1));
      final seen = <Side>{};
      // 0.6 rad/s: a full turn in ~10 s, passing every side.
      for (var i = 0; i < 50; i++) {
        sim.run(const Duration(milliseconds: 200), gyro: [0, 0, 0.6]);
        seen.add(sim.est.state.settledSide);
      }
      expect(seen, {Side.bottom});
    });

    test('a hard set-down does not switch sides', () {
      final r = math.Random(3);
      final sim = _Sim()..run(const Duration(seconds: 1));
      // 300 ms of landing: big random jolts and wobble in every direction.
      for (var i = 0; i < 15; i++) {
        sim.run(
          _step,
          accel: [
            (r.nextDouble() - 0.5) * 16,
            (r.nextDouble() - 0.5) * 16,
            9.81 + (r.nextDouble() - 0.5) * 12,
          ],
          gyro: [
            (r.nextDouble() - 0.5) * 3,
            (r.nextDouble() - 0.5) * 3,
            (r.nextDouble() - 0.5) * 0.4,
          ],
        );
      }
      sim.run(const Duration(seconds: 2));
      expect(sim.est.state.side, Side.bottom);
      expect(sim.est.state.settledSide, Side.bottom);
    });

    test('a deliberate turn and rest switches within a second', () {
      final sim = _Sim()
        ..run(const Duration(seconds: 1))
        ..run(const Duration(seconds: 1), gyro: [0, 0, math.pi / 2])
        ..run(const Duration(milliseconds: 900));
      expect(sim.est.state.settledSide, Side.left);
    });
  });
}
