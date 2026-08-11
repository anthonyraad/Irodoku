import 'dart:math';

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
  static const _slide = 'sounds/slide.mp3';
  static const _rainbowConfirm = 'sounds/rainbowconfirm.mp3';
  static const _gsConfirm = 'sounds/gsconfirm.mp3';
  static const _gsConfirm2 = 'sounds/gsconfirm2.mp3';
  static const _gsConfirm3 = 'sounds/gsconfirm3.mp3';
  static const _gsConfirm4 = 'sounds/gsconfirm4.mp3';
  static const _gsConfirm5 = 'sounds/gsconfirm5.mp3';
  static const _gsConfirm6 = 'sounds/gsconfirm6.mp3';
  static const _mistake = 'sounds/mistake.mp3';
  static const _gameLoss = 'sounds/gameloss.mp3';
  static const _complete = 'sounds/complete.mp3';
  static const _gameWin = 'sounds/gamewin.mp3';
  static const _achievement = 'sounds/achievement.mp3';

  /// Glass palette: three shared organic confirms.
  static const _glassConfirms = <String>[
    _gsConfirm,
    _gsConfirm2,
    _gsConfirm3,
  ];

  /// Sky palette: shared confirms plus three Sky-only variants.
  static const _skyConfirms = <String>[
    _gsConfirm,
    _gsConfirm2,
    _gsConfirm3,
    _gsConfirm4,
    _gsConfirm5,
    _gsConfirm6,
  ];

  static const _assets = <String>[
    _note,
    _deselect,
    _confirm,
    _coin,
    _plink,
    _slide,
    _rainbowConfirm,
    _gsConfirm,
    _gsConfirm2,
    _gsConfirm3,
    _gsConfirm4,
    _gsConfirm5,
    _gsConfirm6,
    _mistake,
    _gameLoss,
    _complete,
    _gameWin,
    _achievement,
  ];

  /// Playback gains tuned for typical phone speakers (peak + body vs confirm).
  static const Map<String, double> _volumes = {
    _confirm: 1.0,
    _plink: 1.0,
    _mistake: 1.0,
    _gameLoss: 1.0,
    _note: 1.0,
    _deselect: 0.95,
    // Hotter source assets — attenuated to sit with confirm/note.
    _rainbowConfirm: 0.70, // ~3 dB hotter mean than confirm.mp3
    // Glass/Sky confirms are hotter in mean than confirm.mp3.
    _gsConfirm: 0.55,
    _gsConfirm2: 0.55,
    _gsConfirm3: 0.55,
    _gsConfirm4: 0.55,
    _gsConfirm5: 0.55,
    _gsConfirm6: 0.55,
    _coin: 0.50,
    _slide: 0.62,
    _complete: 0.57,
    _gameWin: 0.72,
    _achievement: 0.79,
  };

  static double _volumeFor(String asset) => _volumes[asset] ?? 1.0;

  /// SFX should layer (e.g. achievement over game win), not steal focus.
  static final AudioContext _mixContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  late final Future<void> _ready;
  final Map<String, AudioPlayer> _players = {};
  AudioPlayer? _fallbackPlayer;
  bool _disposed = false;
  final Random _rng = Random();
  final List<String> _glassConfirmQueue = [];
  final List<String> _skyConfirmQueue = [];
  String? _lastGlassConfirm;
  String? _lastSkyConfirm;

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
        await player.setVolume(_volumeFor(asset));
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
  /// Neon palette placement sting (replaces [playConfirm]).
  Future<void> playSlide() => _play(_slide);
  /// Rainbow palette placement sting (replaces [playConfirm]).
  Future<void> playRainbowConfirm() => _play(_rainbowConfirm);
  /// Glass placement sting — shuffled round-robin of three variants.
  Future<void> playGlassConfirm() => _play(
        _nextShuffledConfirm(
          pool: _glassConfirms,
          queue: _glassConfirmQueue,
          last: _lastGlassConfirm,
          setLast: (v) => _lastGlassConfirm = v,
        ),
      );

  /// Sky placement sting — shuffled round-robin of six variants.
  Future<void> playSkyConfirm() => _play(
        _nextShuffledConfirm(
          pool: _skyConfirms,
          queue: _skyConfirmQueue,
          last: _lastSkyConfirm,
          setLast: (v) => _lastSkyConfirm = v,
        ),
      );

  Future<void> playMistake() => _play(_mistake);
  Future<void> playGameLoss() => _play(_gameLoss);
  Future<void> playComplete() => _play(_complete);
  Future<void> playGameWin() => _play(_gameWin);
  Future<void> playAchievement() => _play(_achievement);

  String _nextShuffledConfirm({
    required List<String> pool,
    required List<String> queue,
    required String? last,
    required void Function(String) setLast,
  }) {
    if (queue.isEmpty) {
      queue
        ..addAll(pool)
        ..shuffle(_rng);
      // Avoid repeating the last clip across reshuffles when possible.
      if (queue.length > 1 && queue.first == last) {
        queue.add(queue.removeAt(0));
      }
    }
    final next = queue.removeAt(0);
    setLast(next);
    return next;
  }

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
      await fallback.setVolume(_volumeFor(assetPath));
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
