import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/sand_glass.dart';

// Sand and wood palettes, shared by both themes.
const sandLight = Color(0xFFEBCB8B);
const sandMid = Color(0xFFD4A35A);
const sandDark = Color(0xFFA9743A);
const _woodLight = Color(0xFFB07A4C);
const _woodMid = Color(0xFF8A5A34);
const _woodDark = Color(0xFF4E2E18);

/// Slope of the sand heaps (visual angle of repose).
const _repose = 0.5;

/// Live state the sand layer draws from. The screen mutates it every frame
/// and calls [changed]; only the sand layer repaints.
class SandScene extends ChangeNotifier {
  /// Fraction of the sand in the screen-top bulb.
  double topSand = 0;
  Tilt vertical = Tilt.down;

  /// Fraction drained since the last flip; shapes the crater on top.
  double drained = 0;

  /// Sand per second (1 / duration).
  double rate = 1 / 300;

  bool flowing = false;

  /// Visual clock in seconds, for the stream and splashes.
  double clock = 0;

  /// [clock] when the stream last started / stopped leaving the neck.
  double streamStart = -1e9;
  double streamStop = -1e9;

  void changed() => notifyListeners();
}

/// Glass shape and sand volumes for one canvas size, computed once.
///
/// The bulb profile is a smooth spline; sand levels come from real 3D
/// volumes (∫πr²), so the top level falls slowly through the wide part and
/// quickly near the neck, as in a real hourglass.
class GlassGeometry {
  GlassGeometry._(this.size) {
    w = size.width;
    h = size.height;
    cx = w / 2;
    cy = h / 2;
    capH = h * 0.055;
    top = capH;
    halfH = cy - capH;
    maxR = w * 0.39;
    thick = math.max(1.5, w * 0.008);

    outer = Float64List(n + 1);
    inner = Float64List(n + 1);
    for (var i = 0; i <= n; i++) {
      outer[i] = maxR * _profile(i / n);
      inner[i] = math.max(0.5, outer[i] - thick);
    }

    cum = Float64List(n + 1);
    final dy = halfH / n;
    for (var i = n - 1; i >= 0; i--) {
      final r = (inner[i] + inner[i + 1]) / 2;
      cum[i] = cum[i + 1] + math.pi * r * r * dy;
    }
    capacity = cum[0];
    sandVolume = capacity * 0.7;

    glass = _outline(outer);
    clip = _outline(inner);
  }

  static GlassGeometry? _last;
  static GlassGeometry of(Size size) =>
      _last?.size == size ? _last! : (_last = GlassGeometry._(size));

  static const n = 160;

  final Size size;
  late final double w, h, cx, cy, capH, top, halfH, maxR, thick;

  /// Outer / inner radius at u = i/n, where u = 0 is the rim, 1 the neck.
  late final Float64List outer, inner;

  /// Volume between the neck and u = i/n.
  late final Float64List cum;
  late final double capacity, sandVolume;
  late final Path glass, clip;

  double get floor => h - capH;

  /// Inner radius at distance [d] from the neck.
  double rAt(double d) {
    final x = (1 - (d / halfH).clamp(0.0, 1.0)) * n;
    final i = x.floor().clamp(0, n - 1);
    final f = x - i;
    return inner[i] * (1 - f) + inner[i + 1] * f;
  }

  /// Distance from the neck of the level that holds [v], filled from the neck.
  double levelFromNeck(double v) {
    if (v <= 0) return 0;
    if (v >= capacity) return halfH;
    var i = n - 1;
    while (i > 0 && cum[i] < v) {
      i--;
    }
    final f = (v - cum[i + 1]) / (cum[i] - cum[i + 1]);
    return (1 - (i + 1 - f) / n) * halfH;
  }

  /// Same, but filled from the rim (a bulb resting on its cap).
  double levelFromRim(double v) => levelFromNeck(capacity - v);

  Path _outline(Float64List r) {
    final pts = <Offset>[];
    for (var i = 0; i <= n; i++) {
      pts.add(Offset(cx - r[i], top + i / n * halfH));
    }
    for (var i = n - 1; i >= 0; i--) {
      pts.add(Offset(cx - r[i], cy + (1 - i / n) * halfH));
    }
    for (var i = 0; i <= n; i++) {
      pts.add(Offset(cx + r[i], h - capH - i / n * halfH));
    }
    for (var i = n - 1; i >= 0; i--) {
      pts.add(Offset(cx + r[i], cy - (1 - i / n) * halfH));
    }
    return Path()..addPolygon(pts, true);
  }

  // Bulb half-profile (u from rim to neck → radius / maxR), interpolated
  // with a monotone cubic so it never wobbles between knots.
  static const _ku = [0.0, .04, .14, .28, .45, .62, .78, .90, .97, 1.0];
  static const _kr = [.80, .90, .99, 1.0, .90, .66, .36, .14, .065, .055];
  static final _kt = _tangents();

  static List<double> _tangents() {
    final k = _ku.length;
    final d = [
      for (var i = 0; i < k - 1; i++)
        (_kr[i + 1] - _kr[i]) / (_ku[i + 1] - _ku[i]),
    ];
    final m = List<double>.filled(k, 0);
    m[0] = d[0];
    m[k - 1] = d[k - 2];
    for (var i = 1; i < k - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < k - 1; i++) {
      if (d[i] == 0) {
        m[i] = m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i], b = m[i + 1] / d[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
    return m;
  }

  static double _profile(double u) {
    var i = 0;
    while (i < _ku.length - 2 && u > _ku[i + 1]) {
      i++;
    }
    final hh = _ku[i + 1] - _ku[i];
    final t = (u - _ku[i]) / hh;
    final t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * _kr[i] +
        (t3 - 2 * t2 + t) * hh * _kt[i] +
        (-2 * t3 + 3 * t2) * _kr[i + 1] +
        (t3 - t2) * hh * _kt[i + 1];
  }
}

/// A rounded "V": 1 at the centre, falling at slope 1, soft at the tip.
double _peak(double q) {
  const e = 0.18;
  return math.max(0, 1 + e - math.sqrt(q * q + e * e));
}

/// A heap (or crater) surface: y at horizontal position x.
class _Surface {
  const _Surface(this.cx, this.baseY, this.height, this.halfW);
  final double cx, baseY, height, halfW;
  double y(double x) => baseY - height * _peak((x - cx).abs() / halfW);
}

/// Wood frame and the faint glass body — never changes, painted once.
class GlassBackPainter extends CustomPainter {
  const GlassBackPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final g = GlassGeometry.of(size);

    // Posts.
    final pw = g.w * 0.032;
    for (final x in [g.w * 0.045, g.w * 0.955]) {
      final rect = Rect.fromLTRB(x - pw / 2, g.capH, x + pw / 2, g.floor);
      final wood = Paint()
        ..shader = const LinearGradient(
          colors: [_woodDark, _woodLight, _woodMid, _woodDark],
          stops: [0, .35, .62, 1],
        ).createShader(rect.inflate(pw * 0.4));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(pw / 2)),
        wood,
      );
      for (final y in [g.capH + pw, g.cy, g.floor - pw]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, y),
            width: pw * 1.7,
            height: pw * 1.1,
          ),
          wood,
        );
      }
    }

    // Glass body: thicker-looking toward the edges, like real glass.
    final tint = dark ? const Color(0xFFFFFFFF) : const Color(0xFF7D98A8);
    canvas.drawPath(
      g.glass,
      Paint()
        ..shader = LinearGradient(
          colors: [
            tint.withValues(alpha: dark ? .14 : .22),
            tint.withValues(alpha: dark ? .03 : .05),
            tint.withValues(alpha: dark ? .02 : .03),
            tint.withValues(alpha: dark ? .05 : .08),
            tint.withValues(alpha: dark ? .16 : .24),
          ],
          stops: const [0, .22, .5, .78, 1],
        ).createShader(Rect.fromLTWH(g.cx - g.maxR, 0, g.maxR * 2, g.h)),
    );

    _cap(canvas, g, top: true);
    _cap(canvas, g, top: false);
  }

  void _cap(Canvas canvas, GlassGeometry g, {required bool top}) {
    final outerH = g.capH * 0.62;
    final outer = top
        ? Rect.fromLTWH(0, 0, g.w, outerH)
        : Rect.fromLTWH(0, g.h - outerH, g.w, outerH);
    final innerRect = top
        ? Rect.fromLTRB(g.w * 0.05, outerH - 1, g.w * 0.95, g.capH)
        : Rect.fromLTRB(g.w * 0.05, g.floor, g.w * 0.95, g.h - outerH + 1);

    for (final (rect, radius, colors) in [
      (innerRect, g.capH * 0.12, const [_woodMid, _woodDark]),
      (outer, g.capH * 0.28, const [_woodLight, _woodDark]),
    ]) {
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      canvas.drawShadow(path, const Color(0xFF000000), 3, false);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(rect),
      );
      // Grain.
      final grain = Paint()
        ..color = const Color(0x12000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.save();
      canvas.clipPath(path);
      for (var j = 0; j < 4; j++) {
        final line = Path();
        for (var x = rect.left; x <= rect.right; x += 4) {
          final y =
              rect.top +
              (j + 0.5) / 4 * rect.height +
              math.sin(x / g.w * math.pi * 3 + j * 1.7) * rect.height * 0.08;
          x == rect.left ? line.moveTo(x, y) : line.lineTo(x, y);
        }
        canvas.drawPath(line, grain);
      }
      canvas.restore();
      // Lit top edge, shaded bottom edge.
      canvas.drawLine(
        Offset(rect.left + radius, rect.top + 0.5),
        Offset(rect.right - radius, rect.top + 0.5),
        Paint()
          ..color = const Color(0x33FFFFFF)
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        Offset(rect.left + radius, rect.bottom - 0.5),
        Offset(rect.right - radius, rect.bottom - 0.5),
        Paint()
          ..color = const Color(0x40000000)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(GlassBackPainter old) => old.dark != dark;
}

/// Glass edges and reflections, drawn over the sand — painted once.
class GlassFrontPainter extends CustomPainter {
  const GlassFrontPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final g = GlassGeometry.of(size);
    final edge = dark ? const Color(0x66FFFFFF) : const Color(0x662A3A44);

    // Inner wall line gives the glass its thickness.
    canvas.drawPath(
      g.clip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = edge.withValues(alpha: edge.a * 0.35),
    );
    canvas.drawPath(
      g.glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = edge,
    );

    // Reflections: a soft wide streak and a crisp thin one on the left of
    // each bulb, a faint one on the right.
    final soft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = g.w * 0.03
      ..color = Color.fromRGBO(255, 255, 255, dark ? .22 : .5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.w * 0.012);
    final crisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.3
      ..color = Color.fromRGBO(255, 255, 255, dark ? .45 : .85);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = g.w * 0.02
      ..color = Color.fromRGBO(255, 255, 255, dark ? .10 : .3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.w * 0.01);
    for (final upper in [true, false]) {
      canvas.drawPath(_streak(g, upper, -0.72, 0.10, 0.62), soft);
      canvas.drawPath(_streak(g, upper, -0.58, 0.20, 0.44), crisp);
      canvas.drawPath(_streak(g, upper, 0.80, 0.22, 0.55), faint);
    }

    // Glass lips where the bulbs meet the caps.
    final lipW = g.outer[0] * 2 + 6;
    for (final y in [g.capH, g.floor]) {
      final lip = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(g.cx, y), width: lipW, height: 5),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(
        lip,
        Paint()..color = edge.withValues(alpha: edge.a * 0.5),
      );
      canvas.drawRRect(
        lip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = edge,
      );
    }
  }

  /// A reflection following the wall at [k]·radius from the centre, between
  /// u = [from] and [to] (0 rim, 1 neck).
  Path _streak(GlassGeometry g, bool upper, double k, double from, double to) {
    final p = Path();
    const steps = 30;
    for (var s = 0; s <= steps; s++) {
      final u = from + (to - from) * s / steps;
      final d = (1 - u) * g.halfH;
      final x = g.cx + k * g.outer[(u * GlassGeometry.n).round()];
      final y = upper ? g.cy - d : g.cy + d;
      s == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p;
  }

  @override
  bool shouldRepaint(GlassFrontPainter old) => old.dark != dark;
}

/// The sand, the falling stream and the splashes — repaints every frame.
///
/// Drawn in gravity's frame: when the phone is upside down the canvas is
/// turned over, so "down" here is always toward the lower bulb.
class SandPainter extends CustomPainter {
  SandPainter(this.scene) : super(repaint: scene);
  final SandScene scene;

  static final _grains = _makeGrains();
  static final _buf = Float32List(_grains.length);

  static Float32List _makeGrains() {
    final r = math.Random(7);
    return Float32List.fromList([
      for (var i = 0; i < 2400; i++) r.nextDouble(),
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = GlassGeometry.of(size);
    canvas.save();
    if (scene.vertical == Tilt.up) {
      canvas
        ..translate(g.cx, g.cy)
        ..rotate(math.pi)
        ..translate(-g.cx, -g.cy);
    }
    canvas.clipPath(g.clip);

    final upperFrac = scene.vertical == Tilt.up
        ? 1 - scene.topSand
        : scene.topSand;
    final pile = _lowerPile(g, (1 - upperFrac) * g.sandVolume);
    _drawUpper(canvas, g, upperFrac * g.sandVolume);
    if (pile != null) {
      final path = _surfacePath(g, pile);
      _fillSand(canvas, g, path, pile.y(g.cx), g.floor, shift: 0);
    }
    _drawStream(canvas, g, pile);
    canvas.restore();
  }

  _Surface? _lowerPile(GlassGeometry g, double v) {
    if (v < g.capacity * 1e-4) return null;
    final rim = g.rAt(g.halfH);
    // A small heap is a lone cone on the floor; once it spans the floor it
    // becomes a level with a mound on top, keeping the same volume.
    final rc = math.pow(3 * v / (math.pi * _repose), 1 / 3).toDouble();
    if (rc < rim) return _Surface(g.cx, g.floor, rc * _repose, rc);
    final d = g.levelFromRim(v);
    final r = g.rAt(d);
    var m = r * _repose;
    final base = g.cy + d + m / 3;
    m = m.clamp(0.0, math.max(0.0, base - g.cy - 4));
    return _Surface(g.cx, base, m, r);
  }

  void _drawUpper(Canvas canvas, GlassGeometry g, double v) {
    if (v < g.capacity * 1e-4) return;
    final d = g.levelFromNeck(v);
    final r = g.rAt(d);
    // The surface starts flat after a flip and caves into a funnel as sand
    // drains through the neck.
    final grow = (scene.drained * 12).clamp(0.0, 1.0);
    final c = math.min(r * _repose * 0.9 * grow, d * 0.85);
    final rimD = math.min(d + c / 3, g.halfH - 2);
    // Upside-down surface: baseY is the wall height, "height" dips down.
    final s = _Surface(g.cx, g.cy - rimD, -c, r);
    final path = _surfacePath(g, s, bottom: g.cy + 1);
    _fillSand(
      canvas,
      g,
      path,
      g.cy - rimD,
      g.cy,
      shift: scene.drained * 1.4,
      hole: scene.flowing ? Offset(g.cx, s.y(g.cx)) : null,
      holeR: r * 0.3,
    );
  }

  Path _surfacePath(GlassGeometry g, _Surface s, {double? bottom}) {
    final left = g.cx - g.maxR - 4, right = g.cx + g.maxR + 4;
    final floor = bottom ?? g.floor + 2;
    final p = Path()..moveTo(left, floor);
    for (var x = left; x <= right; x += 1.5) {
      p.lineTo(x, s.y(x));
    }
    p
      ..lineTo(right, s.y(right))
      ..lineTo(right, floor)
      ..close();
    return p;
  }

  void _fillSand(
    Canvas canvas,
    GlassGeometry g,
    Path path,
    double topY,
    double bottomY, {
    required double shift,
    Offset? hole,
    double holeR = 0,
  }) {
    final box = Rect.fromLTRB(g.cx - g.maxR, topY, g.cx + g.maxR, bottomY);
    canvas.save();
    canvas.clipPath(path);

    // Body: lit at the surface, darker deeper down.
    canvas.drawRect(
      box.inflate(4),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sandLight, sandMid, sandDark],
          stops: [0, .45, 1],
        ).createShader(box),
    );

    // Grains, drifting toward the neck in the draining bulb.
    final gx = g.cx - g.maxR, gw = g.maxR * 2, gh = g.halfH;
    final gy = bottomY > g.cy + 2 ? g.cy : g.cy - gh;
    final half = _grains.length ~/ 2;
    for (var pass = 0; pass < 2; pass++) {
      var j = 0;
      for (var i = pass * half; i < (pass + 1) * half; i += 2) {
        _buf[j++] = gx + _grains[i] * gw;
        _buf[j++] = gy + ((_grains[i + 1] + shift) % 1.0) * gh;
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_buf, 0, j),
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = pass == 0
              ? const Color(0x55FFF4DC)
              : const Color(0x406B4413),
      );
    }

    // Round-glass shading: darker toward the walls.
    canvas.drawRect(
      box.inflate(4),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x55000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x66000000),
          ],
          stops: [0, .3, .65, 1],
        ).createShader(box),
    );

    if (hole != null) {
      canvas.drawCircle(
        hole,
        holeR,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x55000000), Color(0x00000000)],
          ).createShader(Rect.fromCircle(center: hole, radius: holeR)),
      );
    }
    canvas.restore();

    // A fine lit edge along the surface.
    canvas.save();
    canvas.clipRect(box.inflate(1));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66FFF6E0),
    );
    canvas.restore();
  }

  void _drawStream(Canvas canvas, GlassGeometry g, _Surface? pile) {
    final gravity = g.h * 5.5;
    double fall(double t) => t <= 0 ? 0 : 0.5 * gravity * t * t;

    final land = pile?.y(g.cx) ?? g.floor;
    final neck = g.cy - 2;
    final len = land - neck;
    if (len <= 0) return;

    final clock = scene.clock;
    final double front = math.min(len, fall(clock - scene.streamStart));
    final double tail;
    if (scene.flowing) {
      tail = 0;
    } else if (scene.streamStop > scene.streamStart) {
      tail = fall(clock - scene.streamStop);
    } else {
      return;
    }
    if (tail >= front) return;

    // Shorter timers pour thicker and faster: a trickle at an hour, a
    // proper pour at thirty seconds.
    final q =
        ((math.log(scene.rate) - math.log(1 / 3600)) /
                (math.log(1 / 30) - math.log(1 / 3600)))
            .clamp(0.0, 1.0);
    final sw = ui.lerpDouble(0.9, g.w * 0.022, q)!;

    final streamRect = Rect.fromLTRB(
      g.cx - sw / 2,
      neck + tail,
      g.cx + sw / 2,
      neck + front,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(streamRect, Radius.circular(sw / 2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            sandMid.withValues(alpha: ui.lerpDouble(.6, .95, q)!),
            sandLight.withValues(alpha: ui.lerpDouble(.5, .9, q)!),
          ],
        ).createShader(streamRect),
    );

    // Individual grains shimmering down the stream.
    final grain = Paint()..color = sandLight;
    final count = ui.lerpDouble(6, 24, q)!.round();
    for (var i = 0; i < count; i++) {
      final phase = (i * 0.618 + clock * (2.2 + (i % 5) * 0.35)) % 1.0;
      final y = neck + phase * phase * len; // accelerating as it falls
      if (y < neck + tail || y > neck + front) continue;
      final x = g.cx + math.sin(i * 12.9898 + clock * 23) * sw * 0.7;
      canvas.drawCircle(Offset(x, y), 0.6 + (i % 3) * 0.2, grain);
    }

    if (front < len - 0.5 || pile == null) return;

    // Where it lands: a soft glow and grains bouncing off the heap.
    final hit = Offset(g.cx, land);
    final glowR = sw * 4 + 3;
    canvas.drawCircle(
      hit,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            sandLight.withValues(alpha: .45),
            sandLight.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: hit, radius: glowR)),
    );

    final every = ui.lerpDouble(0.09, 0.018, q)!;
    const life = 0.4;
    final fallTime = math.sqrt(2 * len / gravity);
    final splash = Paint();
    for (
      var k = ((clock - life) / every).floor();
      k <= (clock / every).floor();
      k++
    ) {
      final born = k * every;
      final tau = clock - born;
      if (tau <= 0 || tau >= life) continue;
      if (born < scene.streamStart + fallTime) continue;
      if (!scene.flowing && born > scene.streamStop + fallTime) continue;
      final vx = (_hash(k, 1) * 2 - 1) * g.w * 0.2;
      final vy = -(0.3 + 0.7 * _hash(k, 2)) * g.w * (0.18 + 0.2 * q);
      final x = hit.dx + vx * tau;
      final y = hit.dy + vy * tau + 0.5 * gravity * tau * tau;
      if (y > pile.y(x) + 0.5) continue; // landed back on the heap
      splash.color = sandLight.withValues(alpha: 1 - tau / life);
      canvas.drawCircle(Offset(x, y), 0.9, splash);
    }
  }

  static double _hash(int k, int salt) {
    final v = math.sin(k * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  bool shouldRepaint(SandPainter old) => old.scene != scene;
}
