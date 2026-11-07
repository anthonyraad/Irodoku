import 'dart:math' as math;

import 'difficulty.dart';
import 'player_xp.dart';

/// Clock and score for Hyperchroma, the escalating Chromatic arcade run.
///
/// The clock counts down. Every correct fill adds the same amount of time,
/// and a mistake removes slightly more than one fill gives back.
abstract final class HyperchromaRules {
  /// Opening bank, in seconds.
  static const startSeconds = 60;

  /// Removed from the clock for a wrong fill.
  static const mistakePenaltySeconds = 12;

  /// Seconds added for every correct fill, on every difficulty.
  static const gainSeconds = 10;

  /// Twice the normal finish XP for that difficulty.
  static int boardXp(Difficulty difficulty) => PlayerXp.baseXp(difficulty) * 2;

  /// Easy, then Medium, Hard, Expert, and Master. Further clears stay Master.
  static Difficulty difficultyForBoard(int boardsCleared) {
    final last = Difficulty.values.length - 1;
    final index = boardsCleared.clamp(0, last);
    return Difficulty.values[index];
  }

  /// Furthest fully cleared difficulty. Master repeats are counted.
  static String victoryLabel(int boardsCleared) {
    if (boardsCleared <= 0) return '';
    final ladder = Difficulty.values.length;
    if (boardsCleared < ladder) {
      return Difficulty.values[boardsCleared - 1].label;
    }
    final masters = boardsCleared - (ladder - 1);
    return masters <= 1 ? 'Master' : 'Master ×$masters';
  }

  /// Base XP for every cleared board, plus that fraction of the board that
  /// was in progress when the clock ran out.
  static int xp({
    required int boardsCleared,
    required int filledOnCurrent,
    required int emptyOnCurrent,
  }) {
    var total = 0;
    for (var i = 0; i < boardsCleared; i++) {
      total += boardXp(difficultyForBoard(i));
    }
    if (emptyOnCurrent > 0 && filledOnCurrent > 0) {
      final board = boardXp(difficultyForBoard(boardsCleared));
      final filled = math.min(filledOnCurrent, emptyOnCurrent);
      total += (board * filled / emptyOnCurrent).floor();
    }
    return total;
  }
}
