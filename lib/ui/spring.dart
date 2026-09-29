import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A [Curve] that follows a real damped spring, for implicit animations.
///
/// The spring is simulated until it settles and that whole run is mapped onto
/// 0 → 1, so the animation's duration is the settle time and nothing jumps at
/// the end. [bounce] is 0 for no overshoot, higher for more wobble.
class SpringCurve extends Curve {
  factory SpringCurve({double bounce = 0.3}) {
    final sim = SpringSimulation(
      SpringDescription.withDurationAndBounce(
        duration: const Duration(seconds: 1),
        bounce: bounce,
      ),
      0,
      1,
      0,
      tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
    );
    var settle = 0.0;
    while (!sim.isDone(settle) && settle < 10) {
      settle += 1 / 240;
    }
    return SpringCurve._(sim, settle);
  }

  const SpringCurve._(this._sim, this._settle);

  final SpringSimulation _sim;
  final double _settle;

  @override
  double transformInternal(double t) => _sim.x(t * _settle);
}

/// Squishes under the finger and tilts toward it, then springs back with a
/// little wobble.
///
/// Driven by spring simulations that start from the current velocity, so a
/// press interrupted mid-bounce keeps its momentum. Uses a raw [Listener], so
/// it never competes with the child's own tap / long-press gestures.
class SpringPress extends StatefulWidget {
  const SpringPress({
    super.key,
    required this.child,
    this.depth = 0.06,
    this.tilt = 0.14,
  });

  final Widget child;

  /// How much it shrinks while held (0.06 = 6%).
  final double depth;

  /// Max tilt toward the finger, in radians.
  final double tilt;

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress>
    with TickerProviderStateMixin {
  // Firm going in, loose coming back out.
  static final _press = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 700,
    ratio: 0.8,
  );
  static final _release = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 320,
    ratio: 0.35,
  );

  late final _down = AnimationController.unbounded(vsync: this);
  late final _tiltX = AnimationController.unbounded(vsync: this);
  late final _tiltY = AnimationController.unbounded(vsync: this);

  void _springTo(AnimationController c, double target, SpringDescription s) =>
      c.animateWith(SpringSimulation(s, c.value, target, c.velocity));

  /// Leans toward the finger: -1…1 on each axis from the centre.
  void _aim(PointerEvent e) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final p = e.localPosition;
    _springTo(_tiltX, (p.dx / size.width * 2 - 1).clamp(-1.0, 1.0), _press);
    _springTo(_tiltY, (p.dy / size.height * 2 - 1).clamp(-1.0, 1.0), _press);
  }

  void _onDown(PointerDownEvent e) {
    _springTo(_down, 1, _press);
    _aim(e);
  }

  void _onUp(PointerEvent _) {
    for (final c in [_down, _tiltX, _tiltY]) {
      _springTo(c, 0, _release);
    }
  }

  @override
  void dispose() {
    _down.dispose();
    _tiltX.dispose();
    _tiltY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _aim,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: AnimatedBuilder(
        animation: Listenable.merge([_down, _tiltX, _tiltY]),
        child: widget.child,
        builder: (context, child) {
          final s = 1 - widget.depth * _down.value;
          // The pressed side sinks away from the viewer.
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(_tiltY.value * widget.tilt)
            ..rotateY(-_tiltX.value * widget.tilt)
            ..scaleByDouble(s, s, 1, 1);
          return Transform(
            transform: m,
            alignment: Alignment.center,
            // Keep the tap target still while it wobbles.
            transformHitTests: false,
            child: child,
          );
        },
      ),
    );
  }
}
