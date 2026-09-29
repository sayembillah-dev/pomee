import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/preset.dart';
import '../theme.dart';

/// The four session lengths in a pill. Tap one, or drag the thumb and let
/// go: it follows the finger, stretches with speed, and springs onto the
/// nearest time, clicking as it passes each one.
///
/// While [enabled] is false (the timer is running) it only wiggles and calls
/// [onLocked], so a stray swipe never changes a running session.
class PresetSlider extends StatefulWidget {
  const PresetSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
    this.enabled = true,
    this.onLocked,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final Color accent;
  final bool enabled;
  final VoidCallback? onLocked;

  @override
  State<PresetSlider> createState() => _PresetSliderState();
}

class _PresetSliderState extends State<PresetSlider>
    with SingleTickerProviderStateMixin {
  static final _snap = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.62,
  );

  /// Thumb position in slots: 0 = first preset, 3 = last.
  late final _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.value.toDouble(),
  );
  bool _dragging = false;
  int _lastSlot = 0;
  double _slotWidth = 1;

  static const _pad = 6.0;
  static int get _last => presets.length - 1;

  @override
  void initState() {
    super.initState();
    _lastSlot = widget.value;
  }

  @override
  void didUpdateWidget(PresetSlider old) {
    super.didUpdateWidget(old);
    if (!_dragging && widget.value != _pos.value.round()) {
      _springTo(widget.value, _pos.velocity);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _springTo(int slot, double velocity) {
    _lastSlot = slot;
    _pos.animateWith(
      SpringSimulation(
        _snap,
        _pos.value,
        slot.toDouble(),
        velocity,
        tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
      ),
    );
  }

  double _slotAt(double dx) => (dx - _pad) / _slotWidth - 0.5;

  void _choose(int slot) {
    if (slot != widget.value) widget.onChanged(slot);
  }

  void _locked() {
    HapticFeedback.lightImpact();
    // A shake of the head: kick the thumb and let the spring pull it back.
    _pos.animateWith(
      SpringSimulation(_snap, _pos.value, widget.value.toDouble(), 7),
    );
    widget.onLocked?.call();
  }

  void _tapUp(TapUpDetails d) {
    if (!widget.enabled) return _locked();
    final slot = _slotAt(d.localPosition.dx).round().clamp(0, _last);
    if (slot != _lastSlot) HapticFeedback.selectionClick();
    _springTo(slot, _pos.velocity);
    _choose(slot);
  }

  // The thumb goes wherever the finger is, not by how far it moved, so a
  // slide can start anywhere on the pill.
  void _dragStart(DragStartDetails d) {
    if (!widget.enabled) return _locked();
    _dragging = true;
    _pos.stop();
    _follow(d.localPosition.dx);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_dragging) _follow(d.localPosition.dx);
  }

  void _follow(double dx) {
    var p = _slotAt(dx);
    // Past either end it resists, like pulling on elastic.
    if (p < 0) p = (p * 0.35).clamp(-0.4, 0.0);
    if (p > _last) p = _last + ((p - _last) * 0.35).clamp(0.0, 0.4);
    _pos.value = p;
    final slot = p.round().clamp(0, _last);
    if (slot != _lastSlot) {
      _lastSlot = slot;
      HapticFeedback.selectionClick();
      _choose(slot); // the big timer rolls to it live
    }
  }

  void _dragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.velocity.pixelsPerSecond.dx / _slotWidth;
    // A flick carries on a little before picking a slot.
    final slot = (_pos.value + v * 0.08).round().clamp(0, _last);
    if (slot != _lastSlot) HapticFeedback.selectionClick();
    _springTo(slot, v);
    _choose(slot);
  }

  @override
  Widget build(BuildContext context) {
    final c = PomeeColors.of(context);
    final p = presets[widget.value];
    return Semantics(
      slider: true,
      label: 'Session length',
      value: '${p.workMinutes} minute focus, ${p.breakMinutes} minute break',
      increasedValue: widget.value < _last
          ? '${presets[widget.value + 1].workMinutes} minute focus'
          : null,
      decreasedValue: widget.value > 0
          ? '${presets[widget.value - 1].workMinutes} minute focus'
          : null,
      hint: widget.enabled ? null : 'Pause the timer to change',
      onIncrease: widget.enabled && widget.value < _last
          ? () => _choose(widget.value + 1)
          : null,
      onDecrease: widget.enabled && widget.value > 0
          ? () => _choose(widget.value - 1)
          : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: _tapUp,
          onHorizontalDragStart: _dragStart,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onHorizontalDragCancel: () {
            if (!_dragging) return;
            _dragging = false;
            _springTo(_pos.value.round().clamp(0, _last), 0);
          },
          child: Container(
            height: 76,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.track, c.background),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                _slotWidth = box.maxWidth / presets.length;
                return AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) => _paint(c, box),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _paint(PomeeColors c, BoxConstraints box) {
    final pos = _pos.value;
    // Stretch along the direction of travel, like a drop of liquid.
    final stretch = (_pos.velocity.abs() * 0.035).clamp(0.0, 0.3);
    final thumbW = _slotWidth * (1 + stretch);
    final left = pos * _slotWidth - (thumbW - _slotWidth) / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: thumbW,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        Positioned.fill(
          child: Row(
            children: [
              for (var i = 0; i < presets.length; i++)
                Expanded(child: Center(child: _label(c, i, pos))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(PomeeColors c, int i, double pos) {
    // 1 when the thumb sits on this slot, fading as it slides away.
    final on = (1 - (i - pos).abs()).clamp(0.0, 1.0);
    // Mid-session the other times fade back: they can't be picked.
    final idle = c.ink.withValues(alpha: widget.enabled ? 0.55 : 0.2);
    final color = Color.lerp(idle, c.onAccent, on)!;
    return Transform.scale(
      scale: 0.92 + 0.08 * on,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${presets[i].workMinutes}',
                style: TextStyle(
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '+${presets[i].breakMinutes} break',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: color.a * 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
