import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pose_service.dart';

/// Debug-only readout of the pose estimator (double-tap the background).
class DebugHud extends StatefulWidget {
  const DebugHud({super.key, required this.pose});
  final PoseService pose;

  @override
  State<DebugHud> createState() => _DebugHudState();
}

class _DebugHudState extends State<DebugHud> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.pose.estimator;
    final s = e.state;
    final g = e.gravity.map((v) => v.toStringAsFixed(1)).join(', ');
    final text = [
      'gravity  $g',
      'tilt     ${e.tiltDegrees.toStringAsFixed(0)}°  (${e.pose.name})',
      'heading  ${e.headingDegrees.toStringAsFixed(0)}°',
      'side     ${s.side.name}   settled ${s.settledSide.name}',
      'resting  ${e.resting}   pickedUp ${s.pickedUp}',
    ].join('\n');
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            color: const Color(0xCC000000),
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF7CFC9A),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
