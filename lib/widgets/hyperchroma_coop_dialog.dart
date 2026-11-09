import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/hyperchroma.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../services/hyperchroma_coop_service.dart';
import 'menu_action_button.dart';

enum HyperchromaMenuResult { solo, started }

/// Solo or Co-op, then Quick Play / Create / Join, over the main menu.
class HyperchromaModeDialog extends StatefulWidget {
  const HyperchromaModeDialog({super.key});

  @override
  State<HyperchromaModeDialog> createState() => _HyperchromaModeDialogState();
}

class _HyperchromaModeDialogState extends State<HyperchromaModeDialog> {
  final _link = HyperchromaCoopLink();
  final _join = TextEditingController();
  var _coop = false;
  var _busy = false;
  var _starting = false;
  String? _message;
  var _handedOff = false;

  @override
  void initState() {
    super.initState();
    _link.onRoom = _onRoom;
  }

  @override
  void dispose() {
    _join.dispose();
    if (!_handedOff) unawaited(_link.closeIfLobby());
    super.dispose();
  }

  Future<void> _quickPlay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Searching for opponent…';
    });
    try {
      if (!await HyperchromaCoopService.ensureReady()) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      final id = HyperchromaCoopService.playerId;
      if (id == null) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      _link.playerId = id;
      if (!mounted) return;
      final name = context.read<SettingsProvider>().displayName;
      for (var attempt = 0; attempt < 6; attempt++) {
        final open = await HyperchromaCoopService.findOpenQuickRoom(id);
        if (open == null) break;
        final joined = await HyperchromaCoopService.joinRoom(
          roomCode: open,
          playerId: id,
          displayName: name,
        );
        if (!joined) continue;
        _link.isHost = false;
        await _link.listen(open);
        await HyperchromaCoopService.armMatchDisconnect(
          roomCode: open,
          playerId: id,
        );
        if (mounted) {
          setState(() => _message = 'Waiting for opponent…');
        }
        return;
      }
      final code = await HyperchromaCoopService.createRoom(
        hostId: id,
        quickMatch: true,
        displayName: name,
      );
      _link.isHost = true;
      await _link.listen(code);
      if (mounted) {
        setState(() => _message = 'Waiting for opponent…');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Quick Play failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Creating room…';
    });
    try {
      if (!await HyperchromaCoopService.ensureReady()) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      final id = HyperchromaCoopService.playerId;
      if (id == null) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      _link.playerId = id;
      if (!mounted) return;
      final name = context.read<SettingsProvider>().displayName;
      final code = await HyperchromaCoopService.createRoom(
        hostId: id,
        quickMatch: false,
        displayName: name,
      );
      _link.isHost = true;
      await _link.listen(code);
      if (mounted) setState(() => _message = 'Room $code — waiting for opponent…');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not create room.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    if (_busy) return;
    final code = _join.text.trim().toUpperCase();
    if (code.length != 5) {
      setState(() => _message = 'Enter the 5-character code.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Joining $code…';
    });
    try {
      if (!await HyperchromaCoopService.ensureReady()) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      final id = HyperchromaCoopService.playerId;
      if (id == null) {
        setState(() => _message = 'Could not reach the server.');
        return;
      }
      _link.playerId = id;
      if (!mounted) return;
      final name = context.read<SettingsProvider>().displayName;
      final joined = await HyperchromaCoopService.joinRoom(
        roomCode: code,
        playerId: id,
        displayName: name,
      );
      if (!joined) {
        if (mounted) setState(() => _message = 'Could not join $code.');
        return;
      }
      _link.isHost = false;
      await _link.listen(code);
      await HyperchromaCoopService.armMatchDisconnect(
        roomCode: code,
        playerId: id,
      );
      if (mounted) setState(() => _message = 'Joined $code — waiting to start…');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not join $code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onRoom(Map<dynamic, dynamic> room) {
    if (!mounted || _handedOff) return;
    final state = room['gameState']?.toString();
    final players = Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
    if (state == 'waiting' &&
        _link.isHost &&
        players.length >= 2 &&
        !_starting) {
      _starting = true;
      unawaited(_startMatch());
    }
    if (state == 'closed') {
      setState(() {
        _message = 'The room closed.';
        _busy = false;
        _starting = false;
      });
      _link.roomCode = null;
      return;
    }
    if (state == 'playing') {
      unawaited(_enterGame());
      return;
    }
    setState(() {
      _message = _link.isHost && _link.roomCode != null
          ? 'Room ${_link.roomCode} — waiting for opponent…'
          : 'Waiting for opponent…';
    });
  }

  Future<void> _startMatch() async {
    final code = _link.roomCode;
    final id = _link.playerId;
    if (code == null || id == null) return;
    setState(() => _message = 'Starting…');
    try {
      final game = context.read<GameProvider>();
      final settings = context.read<SettingsProvider>();
      final boards = await game.generateHyperchromaCoopBoard(
        HyperchromaRules.difficultyForBoard(0),
      );
      final palette = settings.palette == GamePalette.iro
          ? GamePalette.standard
          : settings.palette;
      await HyperchromaCoopService.armMatchDisconnect(
        roomCode: code,
        playerId: id,
      );
      await HyperchromaCoopService.publishBoard(
        roomCode: code,
        puzzle: boards[0],
        solution: boards[1],
        boardId: 1,
        boardsCleared: 0,
        endsAt:
            HyperchromaCoopService.now() +
            HyperchromaRules.startSeconds * 1000,
        sketches: 0,
        steadfast: 0,
        trace: false,
        telepathy: false,
        palette: palette.storageKey,
        cellsFilled: 0,
        emptyOnBoard: HyperchromaCoopService.emptyCount(boards[0]),
      );
    } catch (_) {
      _starting = false;
      if (mounted) setState(() => _message = 'Could not start the match.');
    }
  }

  Future<void> _enterGame() async {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    final game = context.read<GameProvider>();
    final started = await game.adoptHyperchromaCoop(_link);
    if (!mounted) return;
    Navigator.of(context).pop(
      started ? HyperchromaMenuResult.started : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ink, width: 2.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 110),
              child: Text(
                _coop ? 'Co-op' : 'Hyperchroma',
                key: ValueKey(_coop),
                style: titleStyle,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _link.roomCode != null
                  ? _waitingPanel(ink)
                  : Stack(
                      children: [
                        IgnorePointer(
                          ignoring: !_coop,
                          child: AnimatedOpacity(
                            opacity: _coop ? 1 : 0,
                            duration: const Duration(milliseconds: 110),
                            child: _coopForm(ink),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: _coop,
                            child: AnimatedOpacity(
                              opacity: _coop ? 0 : 1,
                              duration: const Duration(milliseconds: 110),
                              child: _modePanel(ink),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modePanel(Color ink) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            'Irodoku Arcade; play against the clock on an infinite board',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ink.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 18),
        MenuActionButton(
          label: 'Solo',
          onPressed: () => Navigator.of(context).pop(HyperchromaMenuResult.solo),
        ),
        const SizedBox(height: 12),
        MenuActionButton(
          label: 'Co-op',
          onPressed: () => setState(() => _coop = true),
        ),
        const Spacer(),
        _cancel(ink),
      ],
    );
  }

  Widget _coopForm(Color ink) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuActionButton(
          label: 'Quick Play',
          enabled: !_busy,
          onPressed: () => unawaited(_quickPlay()),
        ),
        const SizedBox(height: 12),
        MenuActionButton(
          label: 'Create Room',
          enabled: !_busy,
          onPressed: () => unawaited(_create()),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _join,
                textCapitalization: TextCapitalization.characters,
                maxLength: 5,
                decoration: IrodokuTheme.joinCodeDecoration(context),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: IrodokuTheme.joinButtonStyle(context),
              onPressed: _busy ? null : () => unawaited(_joinByCode()),
              child: const Text('Join'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ink.withValues(alpha: 0.7),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _cancel(ink),
      ],
    );
  }

  Widget _waitingPanel(Color ink) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_message != null)
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (_link.isHost && _link.roomCode != null) ...[
          const SizedBox(height: 12),
          Text(
            _link.roomCode!,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
        const SizedBox(height: 8),
        _cancel(ink),
      ],
    );
  }

  Widget _cancel(Color ink) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text('Cancel', style: TextStyle(color: ink)),
    );
  }
}
