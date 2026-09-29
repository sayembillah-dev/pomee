import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/preset.dart';
import '../services/buzzer.dart';

enum Phase { idle, work, rest }

/// `flutter run --dart-define=POMEE_FAST=true` turns minutes into seconds
/// for trying out a full cycle quickly.
const _fast = bool.fromEnvironment('POMEE_FAST');

class PomodoroController extends ChangeNotifier {
  PomodoroController({
    Buzzer? buzzer,
    DateTime Function()? now,
    void Function(bool awake)? keepAwake,
    this.autoTick = true,
  }) : _buzzer = buzzer ?? Buzzer(),
       _now = now ?? DateTime.now,
       _keepAwake = keepAwake ?? ((_) {});

  final Buzzer _buzzer;
  final DateTime Function() _now;
  final void Function(bool awake) _keepAwake;
  final bool autoTick;

  int _index = defaultPreset;
  Phase _phase = Phase.idle;
  bool _paused = false;
  bool _pickedUp = false;
  bool _chaos = false;
  bool _awake = false;
  DateTime? _endsAt;
  Duration _remaining = _scaled(presets[defaultPreset].work);
  Timer? _ticker;

  int get presetIndex => _index;
  Preset get preset => presets[_index];
  Phase get phase => _phase;
  bool get paused => _paused;
  bool get running => _phase != Phase.idle && !_paused;
  bool get chaos => _chaos;

  Duration get remaining {
    final end = _endsAt;
    if (end == null) return _remaining;
    final left = end.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  Duration get total =>
      _scaled(_phase == Phase.rest ? preset.rest : preset.work);

  /// 0 → just started, 1 → done.
  double get progress {
    final t = total.inMilliseconds;
    return t == 0 ? 0 : 1 - remaining.inMilliseconds / t;
  }

  static Duration _scaled(Duration d) =>
      _fast ? Duration(seconds: d.inMinutes) : d;

  /// The play / pause button.
  void toggle() {
    _buzzer.tick();
    if (_phase == Phase.idle) {
      _begin(Phase.work);
    } else if (_paused) {
      _paused = false;
      _endsAt = _now().add(_remaining);
      _startTicker();
    } else {
      _remaining = remaining;
      _paused = true;
      _endsAt = null;
      _stopTicker();
    }
    _sync();
  }

  /// The reset button.
  void reset() {
    _buzzer.tick();
    _toIdle();
    _sync();
  }

  /// Picks one of [presets]. Not while the timer runs, so a stray swipe on
  /// the slider never throws away a session; pause first. Picking a new time
  /// while paused ends that session and readies the new length. Returns
  /// whether it was taken.
  bool selectPreset(int index) {
    if (running) return false;
    if (index == _index) return true;
    _index = index;
    _toIdle();
    _sync();
    return true;
  }

  void setPickedUp(bool pickedUp) {
    if (pickedUp == _pickedUp) return;
    _pickedUp = pickedUp;
    _sync();
  }

  /// Advances phases when time runs out. Called every second while running.
  @visibleForTesting
  void tick() {
    if (!running || remaining > Duration.zero) {
      notifyListeners();
      return;
    }
    _buzzer.chime();
    if (_phase == Phase.work) {
      _begin(Phase.rest);
    } else {
      _toIdle();
    }
    _sync();
  }

  void _begin(Phase phase) {
    _phase = phase;
    _paused = false;
    _endsAt = _now().add(total);
    _startTicker();
  }

  void _toIdle() {
    _phase = Phase.idle;
    _paused = false;
    _endsAt = null;
    _remaining = _scaled(preset.work);
    _stopTicker();
  }

  void _startTicker() {
    if (!autoTick) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _sync() {
    final chaos = _pickedUp && _phase == Phase.work && !_paused;
    if (chaos != _chaos) {
      _chaos = chaos;
      chaos ? _buzzer.startChaos() : _buzzer.stopChaos();
    }
    if (running != _awake) {
      _awake = running;
      _keepAwake(running);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTicker();
    _buzzer.stopChaos();
    _keepAwake(false);
    super.dispose();
  }
}
