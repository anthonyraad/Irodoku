import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online features that sit behind the one-time age step.
enum AgeGateFeature {
  discordSync('Discord sync'),
  graffitiRooms('Graffiti online rooms');

  const AgeGateFeature(this.label);
  final String label;
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

  Future<void> _pickYear() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      builder: (_) => _Grayscale(
        child: _YearList(
          now: widget.now ?? DateTime.now(),
          selected: _year,
        ),
      ),
    );
    if (picked != null) setState(() => _year = picked);
  }

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
              Text(
                "We ask once before ${widget.feature.label}. "
                'Saved on this device only.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
              InkWell(
                key: const Key('age_gate_year_field'),
                borderRadius: BorderRadius.circular(8),
                onTap: _pickYear,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.onSurface, width: 2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _year?.toString() ?? 'Select year',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: _year == null ? 0.45 : 1),
                          ),
                        ),
                      ),
                      Icon(Icons.expand_more, color: scheme.onSurface),
                    ],
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

class _YearList extends StatelessWidget {
  const _YearList({required this.now, this.selected});
  final DateTime now;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final years = [
      for (var y = now.year; y >= now.year - AgeGate.yearSpan; y--) y,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: Column(
        children: [
          Text('Year of birth', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
              ),
              itemCount: years.length,
              itemBuilder: (context, i) {
                final y = years[i];
                final sel = y == selected;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(y),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? scheme.onSurface : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.onSurface.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '$y',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: sel ? scheme.surface : scheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
          title: Text('${feature.label} is for players 13 and up',
              textAlign: TextAlign.center),
          content: const Text(
            'No worries! You can keep playing and use Set Name to '
            'show your name on the boards.',
            textAlign: TextAlign.center,
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
