import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/sand_glass.dart';
import '../services/buzzer.dart';
import '../theme.dart';
import 'hourglass_painter.dart';
import 'rolling_text.dart';
import 'spring.dart';

final _turnOver = SpringCurve(bounce: 0.18);
final _faceUser = SpringCurve(bounce: 0.25);

/// Quick picks, in seconds.
const _choices = [30, 60, 180, 300, 600, 900, 1500, 1800, 2700, 3600];
const _maxSeconds = 3 * 3600;

/// A sand timer that behaves like the real thing: sand falls toward the
/// ground, flipping the phone runs the rest back, lying it down pauses it.
///
/// Shown in place on the home screen, under its header; [padding] keeps the
/// controls clear of the header and the system bars.
class HourglassView extends StatefulWidget {
  const HourglassView({
    super.key,
    this.gravity,
    this.buzzer,
    this.now,
    this.padding = EdgeInsets.zero,
  });

  /// Accelerometer y ÷ 9.81 (+1 upright, -1 upside down). Defaults to the
  /// phone's sensor; injectable for tests and desktop.
  final Stream<double>? gravity;
  final Buzzer? buzzer;
  final DateTime Function()? now;
  final EdgeInsets padding;

  @override
  State<HourglassView> createState() => _HourglassViewState();
}

class _HourglassViewState extends State<HourglassView>
    with TickerProviderStateMixin {
  final _glass = SandGlass(const Duration(minutes: 5));
  final _scene = SandScene();
  final _secondsLeft = ValueNotifier(300);
  late final Buzzer _buzzer = widget.buzzer ?? Buzzer();
  late final Ticker _ticker;
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  StreamSubscription<double>? _sub;

  var _seconds = 300;
  var _setup = true;
  double _g = 1;
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  late DateTime _last = _now();

  @override
  void initState() {
    super.initState();
    _glass
      ..setGravity(1)
      ..settle();
    _sync();
    final gravity =
        widget.gravity ??
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .map((e) => e.y / 9.81);
    _sub = gravity.listen(_onGravity, onError: (_) {});
    _ticker = createTicker(_tick)..start();
    _flip.addStatusListener((s) {
      if (s == AnimationStatus.completed) _begin();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _flip.dispose();
    _scene.dispose();
    _secondsLeft.dispose();
    super.dispose();
  }

  void _onGravity(double raw) {
    _g += (raw - _g) * 0.35; // light low-pass against jitter
    final vertical = _glass.vertical, tilt = _glass.tilt;
    _glass.setGravity(_g);
    if (_glass.vertical != vertical) {
      HapticFeedback.lightImpact();
      // The old stream belonged to the other bulb.
      _scene
        ..streamStart = -1e9
        ..streamStop = -1e9
        ..flowing = false;
      if (_setup) _glass.settle();
    }
    if (_glass.vertical != vertical || _glass.tilt != tilt) {
      _sync();
      setState(() {});
    }
  }

  void _tick(Duration _) {
    // Sand moves on the wall clock, so time spent in the background counts;
    // the visuals take at most a frame's worth of it.
    final now = _now();
    final dt = now.difference(_last);
    _last = now;
    _scene.clock += math.min(dt.inMicroseconds, 50000) / 1e6;

    if (_glass.advance(dt)) {
      _buzzer.chime();
      setState(() {});
    }
    if (_glass.flowing && !_scene.flowing) _scene.streamStart = _scene.clock;
    if (!_glass.flowing && _scene.flowing) _scene.streamStop = _scene.clock;
    _sync();
    if (_glass.flowing || _scene.clock - _scene.streamStop < 2) {
      _scene.changed();
    }
  }

  void _sync() {
    _scene
      ..topSand = _glass.topSand
      ..vertical = _glass.vertical
      ..drained = _glass.drainedSinceFlip
      ..rate = _glass.rate
      ..flowing = _glass.flowing;
    _secondsLeft.value = _setup
        ? _seconds
        : (_glass.remaining.inMilliseconds / 1000).ceil();
  }

  void _choose(int seconds) {
    HapticFeedback.selectionClick();
    setState(() {
      _seconds = seconds.clamp(30, _maxSeconds);
      _glass.duration = Duration(seconds: _seconds);
    });
    _sync();
    _scene.changed();
  }

  void _step(int dir) {
    final next = dir > 0
        ? (_seconds < 60 ? 60 : _seconds + 60)
        : (_seconds <= 60 ? 30 : _seconds - 60);
    _choose(next);
  }

  /// Turn the glass over on screen, then let the sand go.
  void _start() {
    HapticFeedback.mediumImpact();
    setState(() => _setup = false);
    _flip.forward(from: 0);
  }

  void _begin() {
    _flip.value = 0;
    _glass.start();
    _sync();
    _scene.changed();
    setState(() {});
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _flip.stop();
    _flip.value = 0;
    _glass.settle();
    _scene
      ..streamStart = -1e9
      ..streamStop = -1e9;
    setState(() => _setup = true);
    _sync();
    _scene.changed();
  }

  String get _caption {
    if (_setup) return 'Set the time, then flip';
    if (!_glass.running) return '';
    if (_glass.finished) return "Time's up · flip to run again";
    if (_glass.tilt == Tilt.level) return 'Paused · stand it up to continue';
    return 'Lay it down to pause · flip to reverse';
  }

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.7,
              colors: [
                sandMid.withValues(alpha: dark ? .10 : .16),
                sandMid.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        Padding(
          padding: widget.padding,
          child: LayoutBuilder(
            builder: (context, box) {
              final band = box.maxHeight * 0.22;
              final glassH = box.maxHeight - 2 * band - 24;
              final glassW = math.min(box.maxWidth - 64, glassH * 0.58);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AnimatedBuilder(
                      animation: _flip,
                      builder: (context, child) {
                        final v = _flip.value;
                        return Transform.scale(
                          // Lifted slightly while it's being turned over.
                          scale: 1 - 0.07 * math.sin(math.pi * v.clamp(0, 1)),
                          child: Transform.rotate(
                            angle: math.pi * _turnOver.transform(v),
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        width: glassW,
                        height: glassW / 0.58,
                        child: _Hourglass(scene: _scene, dark: dark),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _glass.vertical == Tilt.up ? 0.5 : 0,
                    duration: const Duration(milliseconds: 650),
                    curve: _faceUser,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          SizedBox(height: band, child: _topBand(c)),
                          const Spacer(),
                          SizedBox(height: band, child: _bottomBand(c)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _topBand(PomeeColors c) {
    return Column(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_setup)
                  _IconButton(
                    icon: Icons.remove_rounded,
                    label: 'Less time',
                    color: c.ink,
                    onTap: _seconds > 30 ? () => _step(-1) : null,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ValueListenableBuilder(
                    valueListenable: _secondsLeft,
                    builder: (context, secs, _) => RollingText(
                      _format(secs),
                      style: TextStyle(
                        fontFamily: displayFont,
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        color: _glass.finished && !_setup ? sandMid : c.ink,
                        height: 1,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                if (_setup)
                  _IconButton(
                    icon: Icons.add_rounded,
                    label: 'More time',
                    color: c.ink,
                    onTap: _seconds < _maxSeconds ? () => _step(1) : null,
                  ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          // One line, shrinking rather than overflowing with large text.
          child: FittedBox(
            key: ValueKey(_caption),
            fit: BoxFit.scaleDown,
            child: Text(
              _caption,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.dim,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomBand(PomeeColors c) {
    if (!_setup) {
      return Center(
        child: _Pill(
          label: _glass.finished ? 'New timer' : 'Reset',
          icon: Icons.refresh_rounded,
          filled: _glass.finished,
          onTap: _reset,
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _choices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Chip(
              label: _short(_choices[i]),
              selected: _choices[i] == _seconds,
              onTap: () => _choose(_choices[i]),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Pill(
          label: 'Flip to start',
          icon: Icons.hourglass_top_rounded,
          filled: true,
          onTap: _start,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static String _format(int secs) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = secs ~/ 3600, m = secs % 3600 ~/ 60, s = secs % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  static String _short(int secs) {
    if (secs < 60) return '${secs}s';
    if (secs < 3600) return '${secs ~/ 60}m';
    return '${secs ~/ 3600}h';
  }
}

/// The three layers: wood + glass body, sand (the only one that animates),
/// then glass edges and reflections on top.
class _Hourglass extends StatelessWidget {
  const _Hourglass({required this.scene, required this.dark});
  final SandScene scene;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: GlassBackPainter(dark: dark)),
        ),
        RepaintBoundary(child: CustomPaint(painter: SandPainter(scene))),
        RepaintBoundary(
          child: CustomPaint(painter: GlassFrontPainter(dark: dark)),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SpringPress(
          depth: 0.2,
          tilt: 0.3,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(
              icon,
              size: 26,
              color: onTap == null ? color.withValues(alpha: 0.25) : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SpringPress(
        depth: 0.1,
        tilt: 0.2,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? sandMid : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? sandMid : c.track, width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF2A1A08) : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final fg = filled ? c.background : c.ink;
    return GestureDetector(
      onTap: onTap,
      child: SpringPress(
        depth: 0.08,
        tilt: 0.15,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: filled ? c.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            border: filled ? null : Border.all(color: c.track, width: 1.5),
          ),
          // Shrinks rather than overflows with large system text.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
