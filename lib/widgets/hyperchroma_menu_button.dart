import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/sound_service.dart';
import 'menu_action_button.dart';
import 'menu_select_sound.dart';

/// Chromatic menu button that becomes Hyperchroma after a 950 ms hold.
///
/// The label eases into a shake and swaps text when the hold completes.
/// Holding Hyperchroma for 600 ms shakes it back to Chromatic.
/// Releasing early keeps whichever label is showing. Leaving the menu
/// disposes this widget, which restores the resting label the same way
/// Pocket mode does.
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
  static const _armDuration = Duration(milliseconds: 950);
  static const _disarmDuration = Duration(milliseconds: 600);

  /// A shorter press on Chromatic is still a tap.
  static const _armTap = Duration(milliseconds: 125);

  /// A shorter press on Hyperchroma is a tap and opens the mode. The revert
  /// shake waits out this window, then still finishes at [_disarmDuration].
  static const _disarmTap = Duration(milliseconds: 125);

  late final AnimationController _rumble;
  late final Animation<double> _disarmRumble;
  bool _armed = false;

  /// Hold on the Hyperchroma label, reversing the arm instead of entering.
  bool _disarming = false;

  /// Stay on the Hyperchroma label after the tap that enters the mode.
  /// Turning the hold off for the loading transition must not flash Chromatic.
  bool _keepHyperchromaLabel = false;
  bool _suppressTap = false;
  int? _pointer;
  SoundService? _riser;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsProvider>();
    _riser = settings.soundEnabled ? context.read<SoundService>() : null;
  }

  @override
  void initState() {
    super.initState();
    _rumble = AnimationController(vsync: this, duration: _armDuration)
      ..addStatusListener(_onRumbleStatus);
    _disarmRumble = _rumble.drive(
      Tween<double>(begin: 0, end: 1).chain(
        CurveTween(
          curve: Interval(
            _disarmTap.inMilliseconds / _disarmDuration.inMilliseconds,
            1,
          ),
        ),
      ),
    );
  }

  void _onRumbleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (!widget.holdEnabled) return;
    if (_disarming) {
      setState(() {
        _disarming = false;
        _armed = false;
        _keepHyperchromaLabel = false;
      });
      _eatNextTap();
      playMenuSelectSound(context);
      return;
    }
    if (_armed) return;
    setState(() => _armed = true);
    playHyperchromaSelectSound(context);
  }

  @override
  void didUpdateWidget(covariant HyperchromaMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pocket swaps this label to [Chromatic] and shakes it with the others.
    // That leaves the armed Hyperchroma label, including after the tap that
    // would have entered the mode.
    if (oldWidget.label != widget.label) {
      _cancelHyperchromaArm();
      return;
    }
    if (widget.holdEnabled || (!_armed && !_rumble.isAnimating)) return;
    _pointer = null;
    _disarming = false;
    _rumble.stop();
    _rumble.value = 0;
    if (_keepHyperchromaLabel) return;
    _stopRiser();
    _armed = false;
  }

  void _cancelHyperchromaArm() {
    _pointer = null;
    _disarming = false;
    _keepHyperchromaLabel = false;
    _armed = false;
    _rumble.stop();
    _rumble.value = 0;
    _stopRiser();
  }

  @override
  void dispose() {
    _stopRiser();
    _rumble.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.holdEnabled || !widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    if (_armed || _keepHyperchromaLabel) {
      _disarming = true;
      _rumble.duration = _disarmDuration;
      _rumble.forward(from: 0);
      return;
    }
    _rumble.duration = _armDuration;
    _rumble.forward(from: 0);
    _startRiser();
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    final progress = _rumble.value;
    if (_disarming) {
      final pastTap = _disarmDuration * progress > _disarmTap;
      _disarming = false;
      _rumble.stop();
      _rumble.value = 0;
      if (pastTap) _eatNextTap();
      return;
    }
    if (!_armed) {
      _stopRiser();
      _rumble.stop();
      _rumble.value = 0;
      if (_armDuration * progress > _armTap) _eatNextTap();
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
    if (_disarming) {
      _disarming = false;
      _rumble.stop();
      _rumble.value = 0;
      return;
    }
    if (_armed) {
      _rumble.stop();
      _rumble.value = 0;
      return;
    }
    _stopRiser();
    _rumble.stop();
    _rumble.value = 0;
  }

  void _startRiser() {
    final riser = _riser;
    if (riser == null) return;
    unawaited(riser.playHyperchromaRiser(_armDuration));
  }

  void _stopRiser() {
    final riser = _riser;
    if (riser == null) return;
    unawaited(riser.stopHyperchromaRiser());
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
    playMenuSelectSound(context);
    if (_armed) {
      _keepHyperchromaLabel = true;
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
        label: _armed || _keepHyperchromaLabel ? 'Hyperchroma' : widget.label,
        fillTint: widget.fillTint,
        enabled: widget.enabled,
        locked: widget.locked,
        onPressed: _onPressed,
        labelShake: widget.labelShake,
        labelRumble: _disarming ? _disarmRumble : _rumble,
        labelSweep: widget.labelSweep,
        playTapSound: false,
      ),
    );
  }
}
