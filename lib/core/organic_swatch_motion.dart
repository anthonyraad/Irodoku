import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

/// Shared clock for animated swatches (Glass / Sky organic, Neon glow).
abstract final class OrganicSwatchMotion {
  static final ValueNotifier<double> seconds = ValueNotifier(0);

  static Listenable get listenable => seconds;

  static int _clients = 0;
  static bool _frameScheduled = false;
  static Duration? _origin;

  static double get timeSeconds => seconds.value;

  static void retain() {
    _clients++;
    _schedule();
  }

  static void release() {
    if (_clients > 0) _clients--;
  }

  static void _schedule() {
    if (_frameScheduled || _clients == 0) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  static void _onFrame(Duration timestamp) {
    _frameScheduled = false;
    _origin ??= timestamp;
    seconds.value = (timestamp - _origin!).inMicroseconds / 1e6;
    if (_clients > 0) _schedule();
  }
}
