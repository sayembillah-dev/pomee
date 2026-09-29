import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/preset.dart';
import 'pose_estimator.dart';

/// Streams sensor data into a [PoseEstimator] and exposes its [PoseState].
class PoseService extends ValueNotifier<PoseState> {
  PoseService()
    : super(
        const PoseState(
          side: Side.bottom,
          settledSide: Side.bottom,
          pickedUp: false,
        ),
      );

  PoseEstimator _estimator = PoseEstimator();

  /// Raw internals, for the debug HUD only.
  PoseEstimator get estimator => _estimator;
  final _subs = <StreamSubscription<Object>>[];

  /// Continuous facing angle (see [PoseEstimator.facingAngle]) for the
  /// "you" marker. Only notifies on changes worth repainting.
  final facing = ValueNotifier<double>(0);

  /// The user tapped the label of the edge nearest them.
  void anchor(Side side) {
    _estimator.anchor(side);
    _publish();
  }

  bool get running => _subs.isNotEmpty;

  void start() {
    if (running) return;
    // Fresh estimator after a pause: whatever edge faces the user now wins.
    _estimator = PoseEstimator()..restoreSide(value.settledSide);
    _subs
      ..add(
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) {
              _estimator.addAccel(e.x, e.y, e.z, _at(e.timestamp));
              _publish();
            }, onError: (_) {}),
      )
      ..add(
        gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) {
              _estimator.addGyro(e.x, e.y, e.z, _at(e.timestamp));
              _publish();
            }, onError: (_) {}),
      );
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    // Never leave the app "picked up" while sensors are off.
    value = PoseState(
      side: value.side,
      settledSide: value.settledSide,
      pickedUp: false,
    );
  }

  static Duration _at(DateTime t) =>
      Duration(microseconds: t.microsecondsSinceEpoch);

  void _publish() {
    value = _estimator.state;
    final a = _estimator.facingAngle;
    if ((a - facing.value).abs() > 0.005) facing.value = a;
  }

  @override
  void dispose() {
    stop();
    facing.dispose();
    super.dispose();
  }
}
