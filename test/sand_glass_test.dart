import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/models/sand_glass.dart';

void main() {
  late SandGlass g;

  setUp(() {
    g = SandGlass(const Duration(minutes: 1))
      ..setGravity(1)
      ..start();
  });

  void run(Duration d, {int steps = 60}) {
    for (var i = 0; i < steps; i++) {
      g.advance(d ~/ steps);
    }
  }

  test('setup rests all sand in the lower bulb', () {
    g.settle();
    expect(g.upperSand, 0);
    expect(g.running, isFalse);
  });

  test('a full bulb empties in exactly the chosen time', () {
    expect(g.remaining, const Duration(minutes: 1));
    run(const Duration(seconds: 30));
    expect(g.remaining.inMilliseconds, closeTo(30000, 5));
    expect(g.finished, isFalse);
    run(const Duration(seconds: 30));
    expect(g.upperSand, 0);
    expect(g.finished, isTrue);
  });

  test('finishing fires exactly once', () {
    var fired = 0;
    for (var i = 0; i < 200; i++) {
      if (g.advance(const Duration(seconds: 1))) fired++;
    }
    expect(fired, 1);
  });

  test('flipping halfway runs the drained sand back', () {
    run(const Duration(seconds: 20));
    expect(g.topSand, closeTo(2 / 3, 1e-3));
    g.setGravity(-1); // upside down: bottom bulb is now on top
    expect(g.upperSand, closeTo(1 / 3, 1e-3));
    expect(g.remaining.inMilliseconds, closeTo(20000, 5));
    run(const Duration(seconds: 20));
    expect(g.topSand, closeTo(1, 1e-3));
    expect(g.finished, isTrue);
  });

  test('lying flat or sideways pauses the sand', () {
    run(const Duration(seconds: 10));
    g.setGravity(0.05);
    expect(g.tilt, Tilt.level);
    final before = g.topSand;
    run(const Duration(seconds: 30));
    expect(g.topSand, before);
    g.setGravity(0.9);
    run(const Duration(seconds: 10));
    expect(g.remaining.inMilliseconds, closeTo(40000, 5));
  });

  test('held at an angle keeps flowing; dead band has hysteresis', () {
    g.setGravity(0.5); // ~60° back
    expect(g.flowing, isTrue);
    g.setGravity(0.25); // in the band, still flowing
    expect(g.flowing, isTrue);
    g.setGravity(0.1);
    expect(g.flowing, isFalse);
    g.setGravity(0.25); // in the band, stays stopped
    expect(g.flowing, isFalse);
  });

  test('flipping after it runs out starts it again', () {
    run(const Duration(minutes: 1));
    expect(g.finished, isTrue);
    g.setGravity(-1);
    expect(g.finished, isFalse);
    expect(g.remaining, const Duration(minutes: 1));
    expect(g.flowing, isTrue);
  });
}
