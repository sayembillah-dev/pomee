import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/pomodoro_controller.dart';
import '../services/pose_service.dart';
import '../theme.dart';
import 'about_sheet.dart';
import 'chaos_overlay.dart';
import 'debug_hud.dart';
import 'hourglass_view.dart';
import 'preset_slider.dart';
import 'rolling_text.dart';
import 'spring.dart';
import 'water.dart';

final _labelPop = SpringCurve(bounce: 0.45);

/// The hourglass icon turning over, a little past and back.
final _turnOver = SpringCurve(bounce: 0.3);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.now});

  /// Wall clock for the focus timer; tests pass a fake one.
  final DateTime Function()? now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _pose = PoseService();
  late final _timer = PomodoroController(
    now: widget.now,
    keepAwake: (on) => WakelockPlus.toggle(enable: on || _hourglass),
  );

  /// Showing the sand hourglass in place of the focus timer.
  var _hourglass = false;

  /// 0 is the focus timer, 1 the hourglass; drives the cross-fade.
  late final _mode = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// The timer's parts are gone in the first half and the hourglass comes in
  /// over the second, so the two never overlap.
  late final _timerOut = CurvedAnimation(
    parent: _mode,
    curve: const Interval(0, 0.45),
  );
  late final _hourglassIn = CurvedAnimation(
    parent: _mode,
    curve: const Interval(0.4, 1, curve: Curves.easeOutCubic),
  );
  late final _timerShown = ReverseAnimation(_timerOut);
  late final AppLifecycleListener _lifecycle;
  bool _hud = false;

  /// Rises with focus time, drains during the break.
  final _water = Water();
  late final Ticker _frames = createTicker(_onFrame);
  Duration _lastFrame = Duration.zero;
  PomeeColors? _colors;

  /// Briefly true after the slider is touched mid-session.
  final _lockedHint = ValueNotifier(false);
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _pose.addListener(_onPose);
    _timer.addListener(_wake);
    _pose.start();
    _lifecycle = AppLifecycleListener(onShow: _pose.start, onHide: _pose.stop);
  }

  /// Only pickups matter now: lifting the phone mid-focus sounds the alarm.
  void _onPose() => _timer.setPickedUp(_pose.value.pickedUp);

  void _wake() {
    if (_frames.isActive) return;
    _lastFrame = Duration.zero;
    _frames.start();
  }

  void _onFrame(Duration elapsed) {
    final dt = (elapsed - _lastFrame).inMicroseconds / 1e6;
    _lastFrame = elapsed;
    final t = _timer;
    // The water drains away while the hourglass is out and comes back up
    // to where the session is when the timer returns.
    _water.target = switch (t.phase) {
      _ when _hourglass => 0,
      Phase.idle => 0,
      Phase.work => t.progress,
      Phase.rest => 1 - t.progress,
    };
    _water.targetCalm = t.running ? 1 : 0.3;
    final c = _colors;
    if (c != null) _water.targetColor = t.phase == Phase.rest ? c.rest : c.work;
    _water.step(dt);
    if ((t.phase == Phase.idle || _hourglass) && _water.settled) {
      _frames.stop();
    }
  }

  void _showLockedHint() {
    _lockedHint.value = true;
    _hintTimer?.cancel();
    _hintTimer = Timer(
      const Duration(milliseconds: 2200),
      () => _lockedHint.value = false,
    );
  }

  /// Swaps the focus timer for the hourglass and back, on the same screen.
  /// The hourglass is all about picking the phone up and flipping it, so the
  /// focus timer ignores pickups meanwhile. It keeps counting.
  void _toggleHourglass() {
    setState(() => _hourglass = !_hourglass);
    if (_hourglass) {
      _pose.removeListener(_onPose);
      _timer.setPickedUp(false);
      _mode.forward();
    } else {
      _timer.setPickedUp(_pose.value.pickedUp);
      _pose.addListener(_onPose);
      _mode.reverse();
    }
    WakelockPlus.toggle(enable: _hourglass || _timer.running);
    _wake();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _lockedHint.dispose();
    _frames.dispose();
    _timerOut.dispose();
    _hourglassIn.dispose();
    _mode.dispose();
    _water.dispose();
    _lifecycle.dispose();
    _pose.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    if (_colors == null) _water.targetColor = c.work;
    if (_colors != c) {
      _colors = c;
      _wake(); // let the water fade to the new theme's colour
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);

    final top = _TopPanel(
      timer: _timer,
      lockedHint: _lockedHint,
      fade: _timerShown,
      hourglass: _hourglass,
      onHourglass: _toggleHourglass,
      padding: EdgeInsets.fromLTRB(12, pad.top + 12, 12, 0),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      child: PopScope(
        // Back from the hourglass goes to the timer, not out of the app.
        canPop: !_hourglass,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleHourglass();
        },
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (kDebugMode)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => setState(() => _hud = !_hud),
                ),
              RepaintBoundary(
                child: CustomPaint(painter: WaterPainter(_water)),
              ),
              Column(
                children: [
                  Expanded(
                    // The top panel twice: as is above the water, and in the
                    // on-water colours below it, so the text stays readable
                    // as the tide goes past.
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AboveWater(
                          water: _water,
                          screen: screen,
                          child: RepaintBoundary(child: top),
                        ),
                        ClipPath(
                          clipper: WaterClipper(
                            _water,
                            screen: screen,
                            inside: true,
                          ),
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: _OnWater(
                                child: RepaintBoundary(child: top),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Fading(
                    opacity: _timerShown,
                    hourglass: _hourglass,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 16),
                      child: ListenableBuilder(
                        listenable: _timer,
                        builder: (context, _) {
                          final accent = _timer.phase == Phase.rest
                              ? c.rest
                              : c.work;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Controls(timer: _timer),
                              const SizedBox(height: 24),
                              PresetSlider(
                                value: _timer.presetIndex,
                                accent: accent,
                                enabled: !_timer.running,
                                onChanged: _timer.selectPreset,
                                onLocked: _showLockedHint,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              // Below the header, which stays put in both modes.
              Positioned.fill(
                top: pad.top + 12 + _headerHeight,
                child: AnimatedBuilder(
                  animation: _mode,
                  builder: (context, child) => _mode.isDismissed
                      ? const SizedBox.shrink()
                      : FadeTransition(
                          opacity: _hourglassIn,
                          child: ScaleTransition(
                            scale: Tween(
                              begin: 0.96,
                              end: 1.0,
                            ).animate(_hourglassIn),
                            child: IgnorePointer(
                              ignoring: !_hourglass,
                              child: child,
                            ),
                          ),
                        ),
                  child: HourglassView(
                    padding: EdgeInsets.only(bottom: pad.bottom + 8),
                  ),
                ),
              ),
              if (_hud) DebugHud(pose: _pose),
              ListenableBuilder(
                listenable: _timer,
                builder: (context, _) => _timer.chaos
                    ? const ChaosOverlay()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _headerHeight = 44.0;

/// Fades the timer's own parts out while the hourglass is showing, and takes
/// them out of reach and out of the accessibility tree.
class _Fading extends StatelessWidget {
  const _Fading({
    required this.opacity,
    required this.hourglass,
    required this.child,
  });

  final Animation<double> opacity;
  final bool hourglass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: IgnorePointer(
        ignoring: hourglass,
        child: ExcludeSemantics(excluding: hourglass, child: child),
      ),
    );
  }
}

/// Recolours its subtree for sitting on the water.
class _OnWater extends StatelessWidget {
  const _OnWater({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = PomeeColors.of(context);
    final on = c.onAccent;
    return Theme(
      data: theme.copyWith(
        extensions: [
          c.copyWith(
            ink: on,
            dim: on.withValues(alpha: 0.8),
            work: on,
            rest: on,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Title and corner buttons, then the big countdown.
class _TopPanel extends StatelessWidget {
  const _TopPanel({
    required this.timer,
    required this.lockedHint,
    required this.fade,
    required this.hourglass,
    required this.onHourglass,
    required this.padding,
  });

  final PomodoroController timer;
  final ValueListenable<bool> lockedHint;
  final Animation<double> fade;
  final bool hourglass;
  final VoidCallback onHourglass;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // Same height as the icon buttons, so they line up.
                child: SizedBox(
                  height: _headerHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Pomee',
                            style: TextStyle(
                              fontFamily: displayFont,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _CornerButton(
                icon: Icons.hourglass_bottom_rounded,
                label: hourglass ? 'Show focus timer' : 'Show hourglass',
                // Turned over like the real thing, one way and back again.
                turns: hourglass ? 0.5 : 0,
                onTap: onHourglass,
              ),
              const _ThemeToggle(),
              _CornerButton(
                icon: Icons.info_outline_rounded,
                label: 'About Pomee',
                onTap: () => showAboutSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _Fading(
            opacity: fade,
            hourglass: hourglass,
            child: ListenableBuilder(
              listenable: Listenable.merge([timer, lockedHint]),
              builder: (context, _) => _Countdown(
                timer: timer,
                hint: lockedHint.value && timer.running,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.timer, required this.hint});

  final PomodoroController timer;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final resting = timer.phase == Phase.rest;
    final accent = resting ? c.rest : c.work;
    // Round up so "25:00" shows for the whole first second.
    final secs = (timer.remaining.inMilliseconds / 1000).ceil();
    final time =
        '${(secs ~/ 60).toString().padLeft(2, '0')}:'
        '${(secs % 60).toString().padLeft(2, '0')}';
    final p = timer.preset;

    final status = hint
        ? 'Pause to change the time'
        : switch (timer.phase) {
            Phase.idle => 'Ready when you are',
            _ when timer.paused => 'Paused',
            Phase.work => 'Focus',
            Phase.rest => 'Break',
          };
    final caption = switch (timer.phase) {
      Phase.idle =>
        '${p.workMinutes} min focus, then a ${p.breakMinutes} min break',
      Phase.work => 'Then a ${p.breakMinutes} min break',
      Phase.rest => 'Stand up, stretch, breathe',
    };

    Widget label(
      String text,
      Color color, {
      double size = 15,
      FontWeight weight = FontWeight.w500,
    }) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: FittedBox(
        key: ValueKey(text),
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color),
        ),
      ),
    );

    return Semantics(
      label: resting ? 'Break timer' : 'Focus timer',
      value: '${secs ~/ 60} minutes ${secs % 60} seconds left',
      child: ExcludeSemantics(
        child: Column(
          children: [
            label(
              status,
              hint ? c.ink : accent,
              size: 18,
              weight: FontWeight.w600,
            ),
            const SizedBox(height: 4),
            Padding(
              // Keep the digits off the screen edges.
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RollingText(
                  time,
                  style: TextStyle(
                    fontFamily: displayFont,
                    fontSize: 136,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                    height: 1.05,
                    letterSpacing: -2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            label(caption, c.ink.withValues(alpha: c.ink.a * 0.6)),
          ],
        ),
      ),
    );
  }
}

/// Play / pause in the middle, reset beside it once a session has started.
class _Controls extends StatelessWidget {
  const _Controls({required this.timer});

  final PomodoroController timer;

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final idle = timer.phase == Phase.idle;
    final playing = timer.running;
    const side = 56.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: side,
          child: AnimatedScale(
            scale: idle ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            curve: idle ? Curves.easeIn : _labelPop,
            child: _RoundButton(
              size: side,
              label: 'Reset',
              fill: Color.alphaBlend(c.track, c.background),
              onTap: idle ? null : timer.reset,
              child: Icon(Icons.replay_rounded, size: 26, color: c.ink),
            ),
          ),
        ),
        const SizedBox(width: 28),
        _RoundButton(
          size: 84,
          label: idle
              ? 'Start focus'
              : playing
              ? 'Pause'
              : 'Resume',
          fill: c.ink,
          onTap: timer.toggle,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: _labelPop,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: 44,
              color: c.background,
            ),
          ),
        ),
        const SizedBox(width: 28),
        const SizedBox.square(dimension: side),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.size,
    required this.label,
    required this.fill,
    required this.onTap,
    required this.child,
  });

  final double size;
  final String label;
  final Color fill;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onTap!();
              },
        child: SpringPress(
          depth: 0.12,
          tilt: 0.25,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.turns = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double turns;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SpringPress(
          depth: 0.2,
          tilt: 0.3,
          child: SizedBox.square(
            dimension: 44,
            child: AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 700),
              curve: _turnOver,
              child: Icon(icon, size: 22, color: PomeeColors.of(context).dim),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sun in dark mode, moon in light mode. The new icon spins in with a spring.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: dark ? 'Switch to light mode' : 'Switch to dark mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          themeMode.value = dark ? ThemeMode.light : ThemeMode.dark;
        },
        child: SpringPress(
          depth: 0.2,
          tilt: 0.3,
          child: SizedBox.square(
            dimension: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: _labelPop,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween(begin: -0.35, end: 0.0).animate(anim),
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: Icon(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                key: ValueKey(dark),
                size: 22,
                color: c.dim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
