import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// State of the water that fills the home screen as a session runs.
///
/// [level] chases [target] on an underdamped spring, so a reset drains with a
/// slosh instead of snapping. Call [step] once per frame; the painter and the
/// clippers repaint from it.
class Water extends ChangeNotifier {
  Water({Color color = Colors.transparent})
    : _color = color,
      targetColor = color;

  /// Seconds of animation time, drives the waves and bubbles.
  double time = 0;

  /// 0 → empty (hidden below the screen), 1 → the screen is full.
  double level = 0;
  double velocity = 0;
  double target = 0;

  /// How lively the surface is: 1 while running, lower when paused.
  double calm = 1;
  double targetCalm = 1;

  Color _color;
  Color targetColor;
  Color get color => _color;

  static const _stiffness = 26.0;
  static const _damping = 2 * 0.42 * 5.1; // ≈ 2ζ√k, ζ = 0.42

  /// Nothing is moving and no water shows, so frames can stop.
  bool get settled =>
      target == 0 &&
      level.abs() < 0.0005 &&
      velocity.abs() < 0.0005 &&
      _color == targetColor;

  void step(double dt) {
    dt = dt.clamp(0, 1 / 30); // a dropped frame shouldn't explode the spring
    time += dt;
    final force = _stiffness * (target - level) - _damping * velocity;
    velocity += force * dt;
    level += velocity * dt;
    calm += (targetCalm - calm) * (1 - math.exp(-dt * 2));
    final t = 1 - math.exp(-dt * 3);
    _color = Color.lerp(_color, targetColor, t)!;
    if ((_color.r - targetColor.r).abs() < 0.002 &&
        (_color.g - targetColor.g).abs() < 0.002 &&
        (_color.b - targetColor.b).abs() < 0.002) {
      _color = targetColor;
    }
    notifyListeners();
  }

  /// Tallest a crest can get, in logical pixels.
  static const maxAmplitude = 26.0;

  /// Height of the front surface at [x] for a screen of [size].
  double surfaceAt(double x, Size size) {
    const a = maxAmplitude;
    final base = size.height + a - level * (size.height + 2 * a);
    // Sloshing: moving water piles up on one side.
    final tilt = (velocity * 18).clamp(-40.0, 40.0);
    final amp = (7 + 5 * calm + velocity.abs() * 20).clamp(0.0, a - 2);
    final u = x / size.width;
    return base +
        tilt * (u - 0.5) +
        amp *
            (0.6 * math.sin(u * 2 * math.pi * 1.1 + time * 1.3) +
                0.4 * math.sin(u * 2 * math.pi * 2.3 - time * 0.9 + 1.3));
  }

  double _backSurfaceAt(double x, Size size) {
    final u = x / size.width;
    final amp = 6 + 4 * calm;
    return surfaceAt(x, size) -
        8 -
        amp * math.sin(u * 2 * math.pi * 1.6 - time * 1.1 + 2.1);
  }

  /// Area under the front surface.
  Path path(Size size) => _fill(size, surfaceAt);

  Path _fill(Size size, double Function(double, Size) surface) {
    final path = Path()..moveTo(0, size.height);
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      path.lineTo(x, surface(x, size));
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }
}

class WaterPainter extends CustomPainter {
  WaterPainter(this.water) : super(repaint: water);

  final Water water;

  static final _bubbles = List.generate(16, (i) {
    final r = math.Random(i * 7919 + 3);
    return (
      x: r.nextDouble(),
      speed: 0.035 + r.nextDouble() * 0.05,
      radius: 1.5 + r.nextDouble() * 3.5,
      phase: r.nextDouble(),
      wobble: r.nextDouble() * 2 * math.pi,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = water;
    // Entirely below the screen: nothing to draw.
    final top =
        size.height +
        Water.maxAmplitude -
        w.level * (size.height + 2 * Water.maxAmplitude);
    if (top - Water.maxAmplitude - 40 > size.height) return;

    final color = w.color;
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0))
        .toColor();
    final deep = hsl
        .withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0))
        .toColor();

    // A paler wave behind, moving the other way, gives depth.
    canvas.drawPath(
      w._fill(size, w._backSurfaceAt),
      Paint()..color = light.withValues(alpha: 0.45),
    );

    final front = w.path(size);
    final bounds = Rect.fromLTRB(
      0,
      math.max(0, top - Water.maxAmplitude),
      size.width,
      size.height,
    );
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, deep],
        ).createShader(bounds),
    );

    // Bubbles rise from the bottom and fade just before the surface.
    canvas.save();
    canvas.clipPath(front);
    final bubble = Paint();
    for (final b in _bubbles) {
      final p = (w.time * b.speed + b.phase) % 1;
      final y = size.height + 10 - p * (size.height + 20);
      final x = b.x * size.width + math.sin(w.time * 1.7 + b.wobble) * 6;
      final depth = y - w.surfaceAt(x, size);
      if (depth < 0) continue;
      final fade = (depth / 60).clamp(0.0, 1.0);
      bubble.color = light.withValues(alpha: 0.5 * fade);
      canvas.drawCircle(Offset(x, y), b.radius, bubble);
    }
    canvas.restore();

    // A thin bright line where the light catches the crest.
    final crest = Path();
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final y = w.surfaceAt(x, size);
      i == 0 ? crest.moveTo(x, y) : crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = light.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(WaterPainter old) => old.water != water;
}

/// Clips to the water ([inside]) or to the air above it, in the coordinates
/// of a box whose top-left is the screen's top-left and [screen] is the
/// screen's size.
class WaterClipper extends CustomClipper<Path> {
  WaterClipper(this.water, {required this.screen, required this.inside})
    : super(reclip: water);

  final Water water;
  final Size screen;
  final bool inside;

  @override
  Path getClip(Size size) {
    final wet = water.path(screen);
    if (inside) return wet;
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      wet,
    );
  }

  @override
  bool shouldReclip(WaterClipper old) =>
      old.water != water || old.screen != screen || old.inside != inside;
}

/// Paints its child only above the water, but still takes taps everywhere.
///
/// Unlike [ClipPath], the clip applies to painting alone, so buttons stay
/// usable after the water has risen over them.
class AboveWater extends SingleChildRenderObjectWidget {
  const AboveWater({
    super.key,
    required this.water,
    required this.screen,
    super.child,
  });

  final Water water;

  /// The screen's size; this box's top-left must be the screen's.
  final Size screen;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAboveWater(water, screen);

  @override
  void updateRenderObject(BuildContext context, RenderAboveWater renderObject) {
    renderObject
      ..water = water
      ..screen = screen;
  }
}

class RenderAboveWater extends RenderProxyBox {
  RenderAboveWater(this._water, this._screen);

  Water _water;
  set water(Water w) {
    if (w == _water) return;
    if (attached) {
      _water.removeListener(markNeedsPaint);
      w.addListener(markNeedsPaint);
    }
    _water = w;
    markNeedsPaint();
  }

  Size _screen;
  set screen(Size s) {
    if (s == _screen) return;
    _screen = s;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _water.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _water.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final dry = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      _water.path(_screen),
    );
    layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      dry,
      super.paint,
      oldLayer: layer as ClipPathLayer?,
    );
  }
}
