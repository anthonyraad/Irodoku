import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/achievements_progress.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/game_stats.dart';
import 'package:irodoku/models/iroen_state.dart';
import 'package:irodoku/models/progress_backup.dart';
import 'package:irodoku/services/progress_sync_service.dart';

void main() {
  test('progress backup round-trips stats, achievements, streaks, and Iroen', () {
    final detail = List<int>.filled(IroenState.detailSize * IroenState.detailSize, 0);
    detail[0] = 4;
    final backup = ProgressBackup(
      stats: const GameStats(
        gamesWon: 12,
        pocketWins: 3,
        pocketChromaticWins: 2,
        pocketDailyWins: 1,
        graffitiWins: 4,
        pocketGraffitiWins: 5,
        totalXp: 400,
        winsByDifficulty: {Difficulty.easy: 8, Difficulty.medium: 4},
        bestTimes: {Difficulty.easy: Duration(minutes: 3)},
        unlockedPalettes: {GamePalette.world11},
      ),
      achievements: const AchievementsProgress(
        unlockedIds: {'r1c1'},
        cellsErased: 9,
      ),
      seenAchievementIds: {'r1c1'},
      dailyLastCompleted: '2026-09-04',
      dailyStreak: 4,
      dailyBestStreak: 6,
      pocketSwipeDiscovered: true,
      iroen: IroenState(detail: detail),
      iroenActiveMosaicId: 'abc',
    );

    final copy = ProgressBackup.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(backup.toJson())) as Map,
      ),
    );

    expect(copy.stats.gamesWon, 12);
    expect(copy.stats.pocketWins, 3);
    expect(copy.stats.pocketChromaticWins, 2);
    expect(copy.stats.pocketDailyWins, 1);
    expect(copy.stats.graffitiWins, 4);
    expect(copy.stats.pocketGraffitiWins, 5);
    expect(copy.stats.totalXp, 400);
    expect(copy.stats.winsFor(Difficulty.easy), 8);
    expect(copy.stats.bestTimeFor(Difficulty.easy), const Duration(minutes: 3));
    expect(copy.stats.unlockedPalettes, {GamePalette.world11});
    expect(copy.achievements.unlockedIds, {'r1c1'});
    expect(copy.achievements.cellsErased, 9);
    expect(copy.seenAchievementIds, {'r1c1'});
    expect(copy.dailyLastCompleted, '2026-09-04');
    expect(copy.dailyStreak, 4);
    expect(copy.dailyBestStreak, 6);
    expect(copy.pocketSwipeDiscovered, isTrue);
    expect(copy.iroen?.detail[0], 4);
    expect(copy.iroenActiveMosaicId, 'abc');
    expect(
      copy.stats.iroenUnlockWins,
      12 + 3 + 2 + 1 + 4 + 5,
    );
  });

  test('unsupported backup version is rejected', () {
    expect(
      () => ProgressBackup.fromJson({
        'v': 99,
        'stats': {'gamesWon': 1},
      }),
      throwsFormatException,
    );
  });

  test('missing stats are rejected', () {
    expect(
      () => ProgressBackup.fromJson({'v': 1}),
      throwsFormatException,
    );
  });

  test('coerces non-string day keys and numeric strings', () {
    final backup = ProgressBackup.fromJson({
      'v': 1,
      'stats': {'gamesWon': '7', 'totalXp': 12.4},
      'dailyLastCompleted': 20260904,
      'dailyStreak': '3',
      'seenAchievementIds': ['r1c1', 2],
    });
    expect(backup.stats.gamesWon, 7);
    expect(backup.stats.totalXp, 12);
    expect(backup.dailyLastCompleted, '20260904');
    expect(backup.dailyStreak, 3);
    expect(backup.seenAchievementIds, {'r1c1', '2'});
  });

  test('cloud snapshot parse treats empty and missing json as no backup', () {
    expect(ProgressSyncService.parseCloudSnapshot(null), isNull);
    expect(ProgressSyncService.parseCloudSnapshot({'v': 1}), isNull);
  });

  test('cloud snapshot parse reads a valid json payload', () {
    final backup = ProgressBackup(
      stats: const GameStats(gamesWon: 2, totalXp: 40),
      achievements: const AchievementsProgress(),
    );
    final parsed = ProgressSyncService.parseCloudSnapshot({
      'v': 1,
      'updatedAt': 1,
      'json': jsonEncode(backup.toJson()),
    });
    expect(parsed, isNotNull);
    expect(parsed!.stats.gamesWon, 2);
    expect(parsed.stats.totalXp, 40);
  });

  test('cloud snapshot parse rejects corrupt and newer payloads', () {
    expect(
      () => ProgressSyncService.parseCloudSnapshot('nope'),
      throwsA(isA<ProgressSyncException>()),
    );
    expect(
      () => ProgressSyncService.parseCloudSnapshot({'json': '{'}),
      throwsA(isA<ProgressSyncException>()),
    );
    expect(
      () => ProgressSyncService.parseCloudSnapshot({
        'json': jsonEncode({
          'v': 99,
          'stats': {'gamesWon': 1},
        }),
      }),
      throwsA(
        isA<ProgressSyncException>().having(
          (e) => e.message,
          'message',
          contains('newer version'),
        ),
      ),
    );
  });
}
