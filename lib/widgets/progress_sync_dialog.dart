import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/progress_backup.dart';
import '../providers/achievements_provider.dart';
import '../providers/game_provider.dart';
import '../providers/graffiti_provider.dart';
import '../providers/iroen_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../services/preferences_service.dart';
import '../services/progress_sync_service.dart';
import 'menu_select_sound.dart';

const _ctaGrey = Color(0xFF424242);

ButtonStyle get _textCtaStyle => TextButton.styleFrom(
      foregroundColor: _ctaGrey,
    );

ButtonStyle _outlinedCtaStyle(Color ink) => OutlinedButton.styleFrom(
      foregroundColor: _ctaGrey,
      side: BorderSide(color: ink.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.16),
    );

ButtonStyle get _filledCtaStyle => FilledButton.styleFrom(
      backgroundColor: _ctaGrey,
      foregroundColor: Colors.white,
    );

ThemeData _syncDialogTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: _ctaGrey,
      onPrimary: Colors.white,
      secondary: _ctaGrey,
    ),
  );
}

Future<void> showProgressSyncDialog(BuildContext context) {
  unawaited(ProgressSyncService.warmUp());
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final dark = Theme.of(dialogContext).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      return Theme(
        data: _syncDialogTheme(dialogContext),
        child: AlertDialog(
          title: SizedBox(
            width: double.infinity,
            child: Text(
              'Sync',
              textAlign: TextAlign.center,
              style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                    color: ink,
                    fontSize: 18,
                  ),
            ),
          ),
          content: Text(
            'Save or load your data to transfer progress between devices',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: ink,
                ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              style: _outlinedCtaStyle(ink),
              onPressed: withMenuSelect(dialogContext, () {
                Navigator.of(dialogContext).pop();
                _confirmAndRun(
                  context,
                  title: 'Save progress?',
                  body:
                      'This replaces the cloud backup for this Google account.',
                  onConfirm: () => _save(context),
                );
              }),
              child: const Text('Save'),
            ),
            OutlinedButton(
              style: _outlinedCtaStyle(ink),
              onPressed: withMenuSelect(dialogContext, () {
                Navigator.of(dialogContext).pop();
                _confirmAndRun(
                  context,
                  title: 'Load progress?',
                  body:
                      'This replaces all progress on this device with the cloud backup.',
                  onConfirm: () => _load(context),
                );
              }),
              child: const Text('Load'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String body,
  required Future<String> Function() onConfirm,
}) async {
  var busy = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final dark = Theme.of(dialogContext).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      return Theme(
        data: _syncDialogTheme(dialogContext),
        child: StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: Text(title, style: TextStyle(color: ink)),
              content: Text(
                body,
                style: Theme.of(dialogContext)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: ink),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  style: _textCtaStyle,
                  onPressed: busy
                      ? null
                      : withMenuSelect(dialogContext, () {
                          Navigator.of(dialogContext).pop(false);
                        }),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: _filledCtaStyle,
                  onPressed: busy
                      ? null
                      : withMenuSelect(dialogContext, () async {
                          if (busy) return;
                          setState(() => busy = true);
                          try {
                            _assertCanSync(context);
                            await ProgressSyncService.ensureSignedIn();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } on ProgressSyncCancelled {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(false);
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(false);
                            }
                            if (context.mounted) {
                              _snack(context, _errorMessage(e));
                            }
                          }
                        }),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
  if (go != true || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Theme(
        data: _syncDialogTheme(dialogContext),
        child: const Center(
          child: CircularProgressIndicator(color: _ctaGrey),
        ),
      ),
    ),
  );
  // Let the spinner route push before work / pop, or we dismiss Settings.
  await Future<void>.delayed(Duration.zero);
  try {
    final message = await onConfirm();
    if (context.mounted) _snack(context, message);
  } on ProgressSyncCancelled {
    // User closed Google Sign-In; no toast.
  } catch (e) {
    if (context.mounted) _snack(context, _errorMessage(e));
  } finally {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }
}

Future<String> _save(BuildContext context) async {
  _assertCanSync(context);
  final stats = context.read<StatsProvider>();
  final achievements = context.read<AchievementsProvider>();
  final iroen = context.read<IroenProvider>();
  final prefs = context.read<PreferencesService>();
  await stats.persist();
  await achievements.persist();
  await iroen.flushWrites();
  final backup = prefs.captureProgressBackup();
  await ProgressSyncService.save(backup);
  return 'Progress saved.';
}

Future<String> _load(BuildContext context) async {
  _assertCanSync(context);
  final backup = await ProgressSyncService.load();
  if (backup == null) {
    throw const ProgressSyncException(
      'No backup found for this Google account.',
    );
  }
  if (!context.mounted) {
    throw const ProgressSyncException('Sync was interrupted.');
  }
  await _applyBackup(context, backup);
  return 'Progress loaded.';
}

Future<void> _applyBackup(BuildContext context, ProgressBackup backup) async {
  final stats = context.read<StatsProvider>();
  final achievements = context.read<AchievementsProvider>();
  final iroen = context.read<IroenProvider>();
  final settings = context.read<SettingsProvider>();
  final game = context.read<GameProvider>();
  final prefs = context.read<PreferencesService>();
  await stats.flushWrites();
  await achievements.prepareForRemoteApply();
  await iroen.flushWrites();
  try {
    await prefs.applyProgressBackup(backup);
    stats.replaceFromPrefs();
    await achievements.replaceFromPrefs();
    settings.applyAfterProgressLoad();
    iroen.reloadFromPrefs();
    game.notifyProgressReloaded();
  } catch (_) {
    achievements.cancelRemoteApply();
    rethrow;
  }
}

void _assertCanSync(BuildContext context) {
  if (context.read<GraffitiProvider>().phase != GraffitiPhase.idle) {
    throw const ProgressSyncException('Leave Graffiti before Sync.');
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message, textAlign: TextAlign.center),
      ),
    );
}

String _errorMessage(Object e) {
  if (e is ProgressSyncException) return e.message;
  return 'Sync failed. Check your connection and try again.';
}
