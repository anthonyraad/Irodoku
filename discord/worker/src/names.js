// Leaderboard names must satisfy the app's DisplayName rules
// (lib/models/daily_leaderboard.dart): 2–10 chars of [A-Za-z0-9 ._-].
export function leaderboardName(user) {
  for (const raw of [user?.global_name, user?.username]) {
    const s = String(raw || '').replace(/[^A-Za-z0-9 ._-]/g, '').replace(/\s+/g, ' ').trim().slice(0, 10).trim();
    if (s.length >= 2) return s;
  }
  return 'Player';
}

// Same fixed UTC-8 day key as DailyIrodoku.dayKeyFor.
export function pstDayKey(ms = Date.now()) {
  return new Date(ms - 8 * 3600e3).toISOString().slice(0, 10);
}
