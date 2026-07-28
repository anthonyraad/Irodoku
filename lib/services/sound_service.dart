import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays short UI sound effects from bundled assets.
class SoundService {
  SoundService() {
    _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  }

  late final AudioPlayer _player;

  Future<void> playNote() => _play('sounds/note.mp3');
  Future<void> playNoteDeselect() => _play('sounds/deselect.mp3', volume: 0.75);
  Future<void> playConfirm() => _play('sounds/confirm.mp3');
  Future<void> playMistake() => _play('sounds/mistake.mp3');
  Future<void> playGameLoss() => _play('sounds/gameloss.mp3');
  Future<void> playComplete() => _play('sounds/complete.mp3');
  Future<void> playGameWin() => _play('sounds/gamewin.mp3');

  Future<void> _play(String assetPath, {double volume = 1.0}) async {
    try {
      await _player.stop();
      await _player.setVolume(volume);
      await _player.play(AssetSource(assetPath));
    } catch (e, st) {
      debugPrint('SoundService failed to play $assetPath: $e\n$st');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
