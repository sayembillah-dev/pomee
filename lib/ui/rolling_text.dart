import 'package:flutter/material.dart';

import 'spring.dart';

/// A firm spring with just a hint of settle, like a detent clicking in.
final _roll = SpringCurve(bounce: 0.1);

/// Characters on little wheels, like a mechanical counter.
///
/// When a character changes, the old one rolls out of its window and the
/// new one rolls in behind it, hard-clipped, no fading. Counting down rolls
/// downward and counting up rolls upward; when several change at once they
/// go one after another from the right, like a carry.
class RollingText extends StatefulWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  /// +1 rolls downward (value went down), -1 upward.
  int _direction = 1;

  @override
  void didUpdateWidget(RollingText old) {
    super.didUpdateWidget(old);
    final before = _value(old.text), after = _value(widget.text);
    if (before != null && after != null && before != after) {
      _direction = after < before ? 1 : -1;
    }
  }

  static int? _value(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

  /// Widest digit and the window height, so every digit gets the same
  /// window and the text doesn't shift as a narrow "1" comes and goes.
  static (double, double) _measure(TextStyle style, TextScaler scaler) {
    var widest = 0.0, height = 0.0;
    for (var d = 0; d <= 9; d++) {
      final tp = TextPainter(
        text: TextSpan(text: '$d', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (tp.width > widest) widest = tp.width;
      if (tp.height > height) height = tp.height;
      tp.dispose();
    }
    // Room above and below the line box for glyphs that reach past it, like
    // old-style digits hanging below the baseline, so the window never
    // crops them.
    final size = scaler.scale(style.fontSize ?? 14);
    return (widest, height + size * 0.3);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final (slot, height) = _measure(style, MediaQuery.textScalerOf(context));
    final text = widget.text;
    // Read as one string, not the individual (and mid-roll, doubled) digits.
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < text.length; i++)
              _Wheel(
                key: ValueKey(i),
                char: text[i],
                style: style,
                width: _isDigit(text[i]) ? slot : null,
                height: height,
                direction: _direction,
                // Rightmost first, each one a beat after its neighbour.
                delay: Duration(milliseconds: 45 * (text.length - 1 - i)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    super.key,
    required this.char,
    required this.style,
    required this.width,
    required this.height,
    required this.direction,
    required this.delay,
  });

  final String char;
  final TextStyle style;
  final double? width;
  final double height;
  final int direction;
  final Duration delay;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> with SingleTickerProviderStateMixin {
  static const _travel = Duration(milliseconds: 480);

  late final _c = AnimationController(vsync: this, value: 1);
  late String _current = widget.char;
  String? _previous;
  int _direction = 1;

  /// The new glyph has fully arrived once; the spring's settle mustn't pull
  /// a sliver of the old one back into view.
  bool _arrived = true;
  Curve _curve = _roll;

  @override
  void didUpdateWidget(_Wheel old) {
    super.didUpdateWidget(old);
    if (widget.char == _current) return;
    // Interrupted mid-roll: carry on from whatever is showing now.
    _previous = _c.value < 0.5 && _previous != null ? _previous : _current;
    _current = widget.char;
    _direction = widget.direction;
    _arrived = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    final total = _travel + widget.delay;
    _curve = Interval(
      widget.delay.inMicroseconds / total.inMicroseconds,
      1,
      curve: _roll,
    );
    _c.duration = total;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    Widget glyph(String ch) => SizedBox(
      width: widget.width,
      height: h,
      child: Center(child: Text(ch, style: widget.style)),
    );
    return ClipRect(
      child: SizedBox(
        width: widget.width,
        height: h,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _curve.transform(_c.value);
            if (t >= 1) _arrived = true;
            final shift = h * _direction;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (_previous != null && !_arrived)
                  Transform.translate(
                    offset: Offset(0, t * shift),
                    child: glyph(_previous!),
                  ),
                Transform.translate(
                  offset: Offset(0, (t - 1) * shift),
                  child: glyph(_current),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
