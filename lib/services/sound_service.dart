import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays short UI sound effects from bundled assets.
///
/// Sounds are preloaded into dedicated [AudioPlayer]s (low-latency mode) so
/// taps don't pay AssetSource prepare cost on every play.
class SoundService {
  SoundService() {
    _ready = _init();
  }

  static const _note = 'sounds/note.mp3';
  static const _deselect = 'sounds/deselect.mp3';
  static const _confirm = 'sounds/confirm.mp3';
  static const _coin = 'sounds/coin.mp3';
  static const _plink = 'sounds/plink.mp3';
  static const _mistake = 'sounds/mistake.mp3';
  static const _gameLoss = 'sounds/gameloss.mp3';
  static const _complete = 'sounds/complete.mp3';
  static const _gameWin = 'sounds/gamewin.mp3';
  static const _achievement = 'sounds/achievement.mp3';

  static const _assets = <String>[
    _note,
    _deselect,
    _confirm,
    _coin,
    _plink,
    _mistake,
    _gameLoss,
    _complete,
    _gameWin,
    _achievement,
  ];

  /// SFX should layer (e.g. achievement over game win), not steal focus.
  static final AudioContext _mixContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  late final Future<void> _ready;
  final Map<String, AudioPlayer> _players = {};
  AudioPlayer? _fallbackPlayer;
  bool _disposed = false;

  Future<void> _init() async {
    try {
      // Copy assets into the cache once so later setSource/play stays cheap.
      await AudioCache.instance.loadAll(_assets);
      if (_disposed) return;

      await AudioPlayer.global.setAudioContext(_mixContext);
      if (_disposed) return;

      for (final asset in _assets) {
        if (_disposed) return;
        final player = AudioPlayer();
        await player.setAudioContext(_mixContext);
        // Achievement is a longer overlay sting; mediaPlayer mixes more
        // reliably with concurrent SFX than SoundPool/lowLatency.
        await player.setPlayerMode(
          asset == _achievement
              ? PlayerMode.mediaPlayer
              : PlayerMode.lowLatency,
        );
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(asset));
        await player.setVolume(
          asset == _deselect
              ? 0.95
              : asset == _coin
                  ? 0.7
                  : 1.0,
        );
        _players[asset] = player;
      }
    } catch (e, st) {
      debugPrint('SoundService preload failed: $e\n$st');
    }
  }

  Future<void> playNote() => _play(_note);
  Future<void> playNoteDeselect() => _play(_deselect);
  Future<void> playConfirm() => _play(_confirm);
  /// 1-1 palette placement sting (replaces [playConfirm]).
  Future<void> playCoin() => _play(_coin);
  /// Kanto / Johto placement sting (replaces [playConfirm]).
  Future<void> playPlink() => _play(_plink);
  Future<void> playMistake() => _play(_mistake);
  Future<void> playGameLoss() => _play(_gameLoss);
  Future<void> playComplete() => _play(_complete);
  Future<void> playGameWin() => _play(_gameWin);
  Future<void> playAchievement() => _play(_achievement);

  Future<void> _play(String assetPath) async {
    if (_disposed) return;
    try {
      await _ready;
      if (_disposed) return;

      final player = _players[assetPath];
      if (player != null) {
        // Source is already prepared; restart from the beginning.
        // (seek is unavailable in lowLatency mode.)
        await player.stop();
        await player.resume();
        return;
      }

      // Fallback if preload failed: same single-player path as before.
      final fallback = _fallbackPlayer ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop);
      await fallback.setAudioContext(_mixContext);
      await fallback.setPlayerMode(
        assetPath == _achievement
            ? PlayerMode.mediaPlayer
            : PlayerMode.lowLatency,
      );
      await fallback.stop();
      await fallback.setVolume(
        assetPath == _deselect
            ? 0.95
            : assetPath == _coin
                ? 0.7
                : 1.0,
      );
      await fallback.play(AssetSource(assetPath));
    } catch (e, st) {
      debugPrint('SoundService failed to play $assetPath: $e\n$st');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _ready;
    } catch (_) {
      // Ignore init errors during teardown.
    }
    final players = <AudioPlayer>[
      ..._players.values,
      if (_fallbackPlayer != null) _fallbackPlayer!,
    ];
    _players.clear();
    _fallbackPlayer = null;
    await Future.wait(players.map((player) => player.dispose()));
  }
}
