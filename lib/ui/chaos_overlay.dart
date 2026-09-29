import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Full-screen flashing shown while the phone is picked up during focus.
///
/// Toggles every 170 ms (just under 3 flashes per second), which stays within
/// the WCAG photosensitive-seizure threshold. Do not make it faster.
class ChaosOverlay extends StatefulWidget {
  const ChaosOverlay({super.key});

  @override
  State<ChaosOverlay> createState() => _ChaosOverlayState();
}

class _ChaosOverlayState extends State<ChaosOverlay> {
  final _rng = math.Random();
  Timer? _timer;
  bool _flip = false;
  Offset _jitter = Offset.zero;
  double _tilt = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 170), (_) {
      setState(() {
        _flip = !_flip;
        _jitter = Offset(
          _rng.nextDouble() * 24 - 12,
          _rng.nextDouble() * 24 - 12,
        );
        _tilt = (_rng.nextDouble() - 0.5) * 0.12;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final bg = _flip ? c.work : c.ink;
    final fg = _flip ? c.ink : c.work;
    return ColoredBox(
      color: bg,
      child: Center(
        child: Transform.translate(
          offset: _jitter,
          child: Transform.rotate(
            angle: _tilt,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PUT ME\nDOWN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: displayFont,
                    fontSize: 64,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'you are supposed to be focusing',
                  style: TextStyle(fontSize: 16, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
