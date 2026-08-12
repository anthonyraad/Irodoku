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

  /// Concurrent voices per note so same-color fills can overlap.
  static const _noteOverlapSlots = 3;

  static const _note = 'sounds/note.mp3';
  static const _deselect = 'sounds/deselect.mp3';
  static const _confirm = 'sounds/confirm.mp3';
  static const _coin = 'sounds/coin.mp3';
  static const _plink = 'sounds/plink.mp3';
  static const _slide = 'sounds/slide.mp3';
  static const _rainbowConfirm = 'sounds/rainbowconfirm.mp3';
  static const _noteG2 = 'sounds/sky_g2.mp3';
  static const _noteA2 = 'sounds/sky_a2.mp3';
  static const _noteC3 = 'sounds/sky_c3.mp3';
  static const _noteD3 = 'sounds/sky_d3.mp3';
  static const _noteF3 = 'sounds/sky_f3.mp3';
  static const _noteG3 = 'sounds/sky_g3.mp3';
  static const _noteA3 = 'sounds/sky_a3.mp3';
  static const _noteC4 = 'sounds/sky_c4.mp3';
  static const _noteD4 = 'sounds/sky_d4.mp3';
  static const _mistake = 'sounds/mistake.mp3';
  static const _gameLoss = 'sounds/gameloss.mp3';
  static const _complete = 'sounds/complete.mp3';
  static const _gameWin = 'sounds/gamewin.mp3';
  static const _achievement = 'sounds/achievement.mp3';

  /// Glass / Sky: one pitch per color value 1–9.
  static const _noteConfirmsByValue = <String>[
    _noteG2, // 1
    _noteA2, // 2
    _noteC3, // 3
    _noteD3, // 4
    _noteF3, // 5
    _noteG3, // 6
    _noteA3, // 7
    _noteC4, // 8
    _noteD4, // 9
  ];

  static const _noteConfirmAssetSet = {..._noteConfirmsByValue};

  static const _assets = <String>[
    _note,
    _deselect,
    _confirm,
    _coin,
    _plink,
    _slide,
    _rainbowConfirm,
    ..._noteConfirmsByValue,
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
    // Glass/Sky note stings.
    _noteG2: 0.52,
    _noteA2: 0.52,
    _noteC3: 0.52,
    _noteD3: 0.52,
    _noteF3: 0.52,
    _noteG3: 0.52,
    _noteA3: 0.52,
    _noteC4: 0.52,
    _noteD4: 0.52,
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
  /// Round-robin voices so the same note can layer.
  final Map<String, List<AudioPlayer>> _notePlayerPools = {};
  final Map<String, int> _notePoolCursor = {};
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
        if (_noteConfirmAssetSet.contains(asset)) {
          final pool = <AudioPlayer>[];
          for (var i = 0; i < _noteOverlapSlots; i++) {
            if (_disposed) return;
            pool.add(await _createPlayer(asset));
          }
          _notePlayerPools[asset] = pool;
          _notePoolCursor[asset] = 0;
        } else {
          _players[asset] = await _createPlayer(asset);
        }
      }
    } catch (e, st) {
      debugPrint('SoundService preload failed: $e\n$st');
    }
  }

  Future<AudioPlayer> _createPlayer(String asset) async {
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
    return player;
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

  /// Glass / Sky placement sting — pitch mapped to the filled color (1–9).
  Future<void> playNoteConfirm(int colorValue) {
    final index = (colorValue - 1).clamp(0, _noteConfirmsByValue.length - 1);
    return _playPooledNote(_noteConfirmsByValue[index]);
  }

  Future<void> playMistake() => _play(_mistake);
  Future<void> playGameLoss() => _play(_gameLoss);
  Future<void> playComplete() => _play(_complete);
  Future<void> playGameWin() => _play(_gameWin);
  Future<void> playAchievement() => _play(_achievement);

  Future<void> _playPooledNote(String assetPath) async {
    if (_disposed) return;
    try {
      await _ready;
      if (_disposed) return;

      final pool = _notePlayerPools[assetPath];
      if (pool == null || pool.isEmpty) {
        await _play(assetPath);
        return;
      }

      final cursor = _notePoolCursor[assetPath] ?? 0;
      final player = pool[cursor % pool.length];
      _notePoolCursor[assetPath] = cursor + 1;
      // Don't stop other voices in the pool — only restart this slot.
      await player.stop();
      await player.resume();
    } catch (e, st) {
      debugPrint('SoundService failed to play $assetPath: $e\n$st');
    }
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
      for (final pool in _notePlayerPools.values) ...pool,
      if (_fallbackPlayer != null) _fallbackPlayer!,
    ];
    _players.clear();
    _notePlayerPools.clear();
    _notePoolCursor.clear();
    _fallbackPlayer = null;
    await Future.wait(players.map((player) => player.dispose()));
  }
}
