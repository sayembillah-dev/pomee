import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/services/buzzer.dart';
import 'package:pomee/theme.dart';
import 'package:pomee/ui/hourglass_view.dart';
import 'package:pomee/ui/rolling_text.dart';

class _FakeBuzzer extends Buzzer {
  int chimes = 0;
  @override
  Future<void> startChaos() async {}
  @override
  Future<void> stopChaos() async {}
  @override
  Future<void> chime() async => chimes++;
  @override
  void tick() {}
}

void main() {
  late StreamController<double> gravity;
  late _FakeBuzzer buzzer;
  late DateTime now;

  setUp(() {
    gravity = StreamController<double>.broadcast();
    buzzer = _FakeBuzzer();
    now = DateTime(2026);
  });

  tearDown(() => gravity.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: HourglassView(
            gravity: gravity.stream,
            buzzer: buzzer,
            now: () => now,
          ),
        ),
      ),
    );
  }

  /// Advances both the wall clock the sand uses and the frame clock.
  Future<void> wait(WidgetTester tester, Duration d) async {
    const frame = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d; t += frame) {
      now = now.add(frame);
      await tester.pump(frame);
    }
  }

  String shown(WidgetTester tester) =>
      tester.widget<RollingText>(find.byType(RollingText)).text;

  /// Gravity is low-passed, so feed a few samples like the real sensor.
  Future<void> tilt(WidgetTester tester, double g) async {
    for (var i = 0; i < 20; i++) {
      gravity.add(g);
    }
    await tester.pump();
  }

  testWidgets('set a time, flip to start, flip mid-way, lie flat, finish', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Flip to start'), findsOneWidget);

    // Pick 1 minute, then one more with +.
    await tester.tap(find.text('1m'));
    await tester.tap(find.bySemanticsLabel('More time'));
    await tester.pump();
    expect(shown(tester), '02:00');

    await tester.tap(find.text('Flip to start'));
    await wait(tester, const Duration(milliseconds: 1500)); // turn-over
    expect(find.text('Reset'), findsOneWidget);
    expect(find.textContaining('flip to reverse'), findsOneWidget);

    // The sand starts once the turn-over ends (~0.4 s ago).
    await wait(tester, const Duration(seconds: 30));
    expect(shown(tester), '01:30');

    // Upside down: the ~30 s that fell now runs back.
    await tilt(tester, -1);
    await wait(tester, const Duration(seconds: 2));
    expect(shown(tester), '00:29');

    // Lying flat pauses.
    await tilt(tester, 0);
    expect(find.textContaining('Paused'), findsOneWidget);
    await wait(tester, const Duration(seconds: 10));
    expect(shown(tester), '00:29');

    // Stand it back up (still upside down) and let it run out.
    await tilt(tester, -1);
    await wait(tester, const Duration(seconds: 31));
    expect(buzzer.chimes, 1);
    expect(shown(tester), '00:00');
    expect(find.textContaining("Time's up"), findsOneWidget);
    expect(find.text('New timer'), findsOneWidget);

    await tester.tap(find.text('New timer'));
    await tester.pump();
    expect(find.text('Flip to start'), findsOneWidget);
    expect(shown(tester), '02:00');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
