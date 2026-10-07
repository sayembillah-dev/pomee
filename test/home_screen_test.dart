import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/theme.dart';
import 'package:pomee/ui/home_screen.dart';
import 'package:pomee/ui/preset_slider.dart';
import 'package:pomee/ui/rolling_text.dart';

void main() {
  setUp(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'dev.fluttercommunity.plus/sensors/accelerometer',
      'dev.fluttercommunity.plus/sensors/gyroscope',
      'dev.fluttercommunity.plus/sensors/method',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    m.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  String shown(WidgetTester tester) =>
      tester.widget<RollingText>(find.byType(RollingText).first).text;

  Offset slot(WidgetTester tester, int i) {
    final r = tester.getRect(find.byType(PresetSlider));
    final w = (r.width - 12) / 4;
    return Offset(r.left + 6 + w * (i + 0.5), r.center.dy);
  }

  testWidgets('pick a time by tap or drag, start, locked, pause to change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const HomeScreen(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '25:00');

    // A slide can start away from the thumb (on 25): 10 → 20 picks 20.
    await tester.dragFrom(slot(tester, 0), slot(tester, 1) - slot(tester, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '20:00');

    await tester.tapAt(slot(tester, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '10:00');

    // Drag from the 10 thumb across to 30.
    await tester.dragFrom(slot(tester, 0), slot(tester, 3) - slot(tester, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '30:00');

    await tester.tap(find.bySemanticsLabel('Start focus'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    // Locked while running: the time stays, a hint shows.
    await tester.tapAt(slot(tester, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pause to change the time'), findsWidgets);
    expect(shown(tester), isNot('10:00'));

    // Paused: picking a time works and readies it.
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(slot(tester, 0));
    await tester.pump(const Duration(seconds: 3));
    expect(shown(tester), '10:00');
    expect(find.bySemanticsLabel('Start focus'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('corner buttons still work under the water', (tester) async {
    addTearDown(() => themeMode.value = ThemeMode.system);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var now = DateTime(2026);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: HomeScreen(now: () => now),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Start focus'));
    now = now.add(const Duration(minutes: 24));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.bySemanticsLabel('Switch to dark mode'));
    expect(themeMode.value, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the hourglass shows in place, the focus timer keeps going', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var clock = DateTime(2026);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: HomeScreen(now: () => clock),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Start focus'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.bySemanticsLabel('Show hourglass'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Same screen, same header; the hourglass under it.
    expect(find.text('Pomee'), findsWidgets);
    expect(find.text('Flip to start'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause').hitTestable(), findsNothing);
    final icon = find.ancestor(
      of: find.byIcon(Icons.hourglass_bottom_rounded).first,
      matching: find.byType(AnimatedRotation),
    );
    expect(tester.widget<AnimatedRotation>(icon.first).turns, 0.5);

    clock = clock.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.bySemanticsLabel('Show focus timer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Flip to start'), findsNothing);
    expect(shown(tester), '22:00');
    expect(tester.widget<AnimatedRotation>(icon.first).turns, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the About sheet links to the privacy policy', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const HomeScreen(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.bySemanticsLabel('About Pomee'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Made by Twodesk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
