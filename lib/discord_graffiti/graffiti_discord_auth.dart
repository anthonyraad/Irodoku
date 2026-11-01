import 'dart:convert';

/// Parsed `/api/firebase-token` response.
class GraffitiDiscordAuth {
  final String token;
  final String uid;
  final String name;
  const GraffitiDiscordAuth({
    required this.token,
    required this.uid,
    required this.name,
  });

  static GraffitiDiscordAuth? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final token = m['token'], uid = m['uid'], name = m['name'];
      if (token is! String || token.isEmpty) return null;
      if (uid is! String || !uid.startsWith('discord_')) return null;
      return GraffitiDiscordAuth(
        token: token,
        uid: uid,
        name: name is String ? name : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// One-line summary of the bridge's network telemetry for the debug overlay.
String describeNet(String? raw, {bool? rtdbConnected}) {
  final conn = rtdbConnected == null
      ? 'rtdb ?'
      : (rtdbConnected ? 'rtdb CONNECTED' : 'rtdb offline');
  Map<dynamic, dynamic> m = const {};
  try {
    final d = raw == null ? null : jsonDecode(raw);
    if (d is Map) m = d;
  } catch (_) {}
  final ws = m['ws'] ?? 'none';
  final lp = (m['longPolls'] as num?)?.toInt() ?? 0;
  final transport = ws == 'open'
      ? 'websocket'
      : (lp > 0 ? 'long-poll($lp)' : 'ws:$ws');
  final parts = <String>[conn, transport];
  final errs = (m['wsErrors'] as num?)?.toInt() ?? 0;
  if (errs > 0) parts.add('wsErr:$errs');
  final close = m['lastClose']?.toString() ?? '';
  if (close.isNotEmpty) parts.add('close:$close');
  return parts.join(' | ');
}
