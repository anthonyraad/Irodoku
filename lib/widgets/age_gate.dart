import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online features that sit behind the one-time age step.
enum AgeGateFeature {
  discordSync('Discord sync'),
  graffitiRooms('Graffiti online rooms');

  const AgeGateFeature(this.label);
  final String label;

  /// Friendly note shown to under-13 players.
  String get under13Message => switch (this) {
        discordSync => 'No worries! Discord sync is intended for players '
            'that are 13+, but you can keep enjoying the rest of Irodoku.',
        graffitiRooms => 'No worries! Graffiti online rooms are intended for '
            'players that are 13+, but you can keep enjoying the rest of '
            'Irodoku.',
      };
}

/// One-time, neutral age step (Play Families policy): asks birth year only,
/// no preselected year, answer remembered on device and never asked again.
abstract final class AgeGate {
  static const prefBirthYear = 'age_gate_birth_year';
  static const minAge = 13;

  /// Oldest year offered in the picker (current year - [yearSpan]).
  static const yearSpan = 100;

  /// Birth year only: treat someone as 13+ when they turn 13 this year or
  /// earlier (currentYear - birthYear >= 13).
  static bool isOldEnough(int birthYear, {DateTime? now}) =>
      (now ?? DateTime.now()).year - birthYear >= minAge;

  static Future<int?> storedBirthYear() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(prefBirthYear);
  }
}

/// Returns true when the player may use [feature]. Shows the age step the
/// first time only; afterwards answers from the saved birth year. Under-13
/// players see a friendly note and get false.
Future<bool> ensureAgeOk(BuildContext context, AgeGateFeature feature) async {
  final prefs = await SharedPreferences.getInstance();
  var year = prefs.getInt(AgeGate.prefBirthYear);
  if (year == null) {
    if (!context.mounted) return false;
    year = await showDialog<int>(
      context: context,
      builder: (_) => AgeGateDialog(feature: feature),
    );
    if (year == null) return false; // dismissed: ask again next time
    await prefs.setInt(AgeGate.prefBirthYear, year);
  }
  if (AgeGate.isOldEnough(year)) return true;
  if (context.mounted) await showAgeGateBlockedNote(context, feature);
  return false;
}

Future<void> showAgeGateBlockedNote(BuildContext context, AgeGateFeature feature) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AgeGateUnderNote(feature: feature),
  );
}

/// Grayscale-only theme wrapper so the gate never shows palette colors.
class _Grayscale extends StatelessWidget {
  const _Grayscale({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFEEEEEE) : const Color(0xFF212121);
    final bg = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: base.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    ).copyWith(
      primary: fg,
      onPrimary: bg,
      surface: bg,
      onSurface: fg,
      surfaceTint: Colors.transparent,
      surfaceContainerHigh: bg,
    );
    return Theme(data: base.copyWith(colorScheme: scheme), child: child);
  }
}

Widget _grayButton(BuildContext context, String label, VoidCallback? onPressed,
    {bool filled = false}) {
  final scheme = Theme.of(context).colorScheme;
  final enabled = onPressed != null;
  final fg = filled ? scheme.surface : scheme.onSurface;
  final bg = filled ? scheme.onSurface : scheme.surface;
  return FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.35),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(
        color: scheme.onSurface.withValues(alpha: enabled ? 1 : 0.25),
        width: 2,
      ),
      minimumSize: const Size(112, 44),
      textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class AgeGateDialog extends StatefulWidget {
  const AgeGateDialog({super.key, required this.feature, this.now});
  final AgeGateFeature feature;
  final DateTime? now;

  @override
  State<AgeGateDialog> createState() => _AgeGateDialogState();
}

class _AgeGateDialogState extends State<AgeGateDialog> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    return _Grayscale(
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.onSurface, width: 2),
          ),
          title: const Text('What year were you born?',
              textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const Key('age_gate_year_field'),
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.onSurface, width: 2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _year,
                    isExpanded: true,
                    menuMaxHeight: 320,
                    dropdownColor: scheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    icon: Icon(Icons.expand_more, color: scheme.onSurface),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: scheme.onSurface),
                    hint: Text(
                      'Select year',
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.45)),
                    ),
                    items: [
                      for (var y = (widget.now ?? DateTime.now()).year;
                          y >= (widget.now ?? DateTime.now()).year -
                              AgeGate.yearSpan;
                          y--)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) => setState(() => _year = y),
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            _grayButton(context, 'Not now', () => Navigator.of(context).pop()),
            _grayButton(
              context,
              'Continue',
              _year == null ? null : () => Navigator.of(context).pop(_year),
              filled: true,
            ),
          ],
        );
      }),
    );
  }
}

class _AgeGateUnderNote extends StatelessWidget {
  const _AgeGateUnderNote({required this.feature});
  final AgeGateFeature feature;

  @override
  Widget build(BuildContext context) {
    return _Grayscale(
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.onSurface, width: 2),
          ),
          content: Text(
            feature.under13Message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            _grayButton(context, 'Got it', () => Navigator.of(context).pop(),
                filled: true),
          ],
        );
      }),
    );
  }
}
