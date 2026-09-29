import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/services/buzzer.dart';
import 'package:pomee/theme.dart';
import 'package:pomee/ui/home_screen.dart';
import 'package:pomee/ui/hourglass_view.dart';

class _SilentBuzzer extends Buzzer {
  @override
  Future<void> startChaos() async {}
  @override
  Future<void> stopChaos() async {}
  @override
  Future<void> chime() async {}
  @override
  void tick() {}
}

/// Small phone, system text size doubled: nothing may overflow.
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

  Future<void> pumpSmall(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(720, 1280); // 360×640 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('home fits with large text', (tester) async {
    await pumpSmall(tester, const HomeScreen());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hourglass setup and running fit with large text', (
    tester,
  ) async {
    final gravity = StreamController<double>.broadcast();
    addTearDown(gravity.close);
    await pumpSmall(
      tester,
      // Under the home screen's header, as it is shown in the app.
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: HourglassView(
            gravity: gravity.stream,
            buzzer: _SilentBuzzer(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Flip to start'));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
