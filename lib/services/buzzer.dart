import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Thin wrapper over the vibration plugin so the rest of the app never
/// touches platform details.
class Buzzer {
  bool _chaos = false;

  /// Heavy, relentless buzzing until [stopChaos].
  Future<void> startChaos() async {
    if (_chaos) return;
    _chaos = true;
    await Vibration.vibrate(
      pattern: const [0, 400, 80, 250, 60],
      intensities: const [0, 255, 0, 255, 0],
      repeat: 0,
    );
  }

  Future<void> stopChaos() async {
    if (!_chaos) return;
    _chaos = false;
    await Vibration.cancel();
  }

  /// A session finished: three firm pulses.
  Future<void> chime() => Vibration.vibrate(
    pattern: const [0, 220, 140, 220, 140, 420],
    intensities: const [0, 200, 0, 200, 0, 255],
  );

  /// Subtle confirmation for taps and preset changes.
  void tick() => HapticFeedback.selectionClick();
}
