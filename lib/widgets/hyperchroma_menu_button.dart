import 'package:flutter/material.dart';

import 'menu_action_button.dart';
import 'menu_select_sound.dart';

/// Chromatic menu button that becomes Hyperchroma after a 1.7-second hold.
///
/// The label eases into a shake and swaps text when the hold completes.
/// Releasing early keeps Chromatic. Leaving the menu disposes this widget,
/// which restores the resting label the same way Pocket mode does.
class HyperchromaMenuButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final bool locked;

  /// Hold-to-arm is only offered on the unlocked 9×9 Chromatic button.
  final bool holdEnabled;
  final VoidCallback onPressed;
  final VoidCallback onHyperchroma;
  final Animation<double>? labelShake;
  final Animation<double>? labelSweep;
  final Color? fillTint;

  const HyperchromaMenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.onHyperchroma,
    this.enabled = true,
    this.locked = false,
    this.holdEnabled = false,
    this.labelShake,
    this.labelSweep,
    this.fillTint,
  });

  @override
  State<HyperchromaMenuButton> createState() => _HyperchromaMenuButtonState();
}

class _HyperchromaMenuButtonState extends State<HyperchromaMenuButton>
    with SingleTickerProviderStateMixin {
  static const _armDuration = Duration(milliseconds: 1700);

  /// Past this fraction of the hold, releasing is not a Chromatic tap.
  static const _tapSlop = 0.12;

  late final AnimationController _rumble;
  bool _armed = false;
  bool _suppressTap = false;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _rumble = AnimationController(vsync: this, duration: _armDuration)
      ..addStatusListener(_onRumbleStatus);
  }

  void _onRumbleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _armed || !mounted) return;
    if (!widget.holdEnabled) return;
    setState(() => _armed = true);
    playMenuSelectSound(context);
  }

  @override
  void didUpdateWidget(covariant HyperchromaMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.holdEnabled || (!_armed && !_rumble.isAnimating)) return;
    _armed = false;
    _pointer = null;
    _rumble.stop();
    _rumble.value = 0;
  }

  @override
  void dispose() {
    _rumble.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.holdEnabled || !widget.enabled || _armed) return;
    _pointer = event.pointer;
    _rumble.forward(from: 0);
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    final progress = _rumble.value;
    if (!_armed) {
      _rumble.stop();
      _rumble.value = 0;
      if (progress > _tapSlop) _eatNextTap();
      return;
    }
    _eatNextTap();
    // Snap still. Animating the rumble back to 0 swings the new label once more.
    _rumble.stop();
    _rumble.value = 0;
  }

  void _onPointerCancel(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (_armed) {
      _rumble.stop();
      _rumble.value = 0;
      return;
    }
    _rumble.stop();
    _rumble.value = 0;
  }

  void _eatNextTap() {
    _suppressTap = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suppressTap = false;
    });
  }

  void _onPressed() {
    if (_suppressTap) {
      _suppressTap = false;
      return;
    }
    if (_armed) {
      widget.onHyperchroma();
    } else {
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: MenuActionButton(
        label: _armed ? 'Hyperchroma' : widget.label,
        fillTint: widget.fillTint,
        enabled: widget.enabled,
        locked: widget.locked,
        onPressed: _onPressed,
        labelShake: widget.labelShake,
        labelRumble: _rumble,
        labelSweep: widget.labelSweep,
      ),
    );
  }
}
