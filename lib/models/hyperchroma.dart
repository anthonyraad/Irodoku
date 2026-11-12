import 'dart:math' as math;

import 'difficulty.dart';
import 'player_xp.dart';

/// Pause-shop powers. The sketch cost is paid up front; the effect waits
/// until the player aims it on the board.
enum HyperchromaEffect {
  steadfast(
    3,
    'Steadfast',
    "The palette doesn't hop for your next 8 fills, or until you complete a unit.",
  ),
  levitate(
    4,
    'Levitate',
    'Every unit you complete in the next 4 seconds grants 2x time bonus.',
  ),
  trace(
    5,
    'Trace',
    'The next box you tap into gets filled with all color notes.',
  ),
  illuminate(
    6,
    'Illuminate',
    'The next color you tap fills the board with all of its notes.',
  ),
  telepathy(
    7,
    'Telepathy',
    'The next color you drag into a box locks that color in its correct place.',
  );

  final int cost;
  final String title;
  final String description;

  const HyperchromaEffect(this.cost, this.title, this.description);
}

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

  /// Co-op correct fills add half as much. Stays at 5 even if a partner leaves.
  static const coopGainSeconds = 5;

  /// Points awarded for each correct fill.
  static const pointsPerCell = 10;

  /// Correct fills Steadfast can hold the palette still.
  static const steadfastFills = 8;

  /// How long Levitate doubles the time bonus for each completed unit.
  static const levitateSeconds = 4;

  /// Levitate grants this many times the usual correct-fill time bonus.
  static const levitateTimeMultiplier = 2;

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
