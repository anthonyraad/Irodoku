import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../discord/discord_mode.dart';
import '../providers/graffiti_provider.dart';
import '../widgets/age_gate.dart';
import 'menu_action_button.dart';

/// Quick Play / Create / Join over the main menu. The board opens once
/// the match actually starts.
class GraffitiMatchDialog extends StatefulWidget {
  final bool pocket;

  const GraffitiMatchDialog({super.key, this.pocket = false});

  @override
  State<GraffitiMatchDialog> createState() => _GraffitiMatchDialogState();
}

class _GraffitiMatchDialogState extends State<GraffitiMatchDialog> {
  final _join = TextEditingController();
  GraffitiProvider? _game;
  var _prepared = false;
  var _handedOff = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game ??= context.read<GraffitiProvider>();
    if (_prepared) return;
    _prepared = true;
    _game!.prepareLobby(pocket: widget.pocket);
  }

  @override
  void dispose() {
    _join.dispose();
    final game = _game;
    if (!_handedOff && game != null && _isMatchmaking(game.phase)) {
      unawaited(game.leave());
    }
    super.dispose();
  }

  bool _isMatchmaking(GraffitiPhase phase) {
    return phase == GraffitiPhase.connecting ||
        phase == GraffitiPhase.searching ||
        phase == GraffitiPhase.waiting;
  }

  Future<void> _online(Future<void> Function() action) async {
    if (!DiscordMode.enabled) {
      if (!mounted) return;
      final allowed = await ensureAgeOk(context, AgeGateFeature.graffitiRooms);
      if (!allowed || !mounted) return;
    }
    await action();
  }

  Future<void> _cancel() async {
    final game = _game;
    if (game != null && _isMatchmaking(game.phase)) {
      await game.leave();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GraffitiProvider>();
    if (game.phase == GraffitiPhase.playing && !_handedOff) {
      _handedOff = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
    final waiting = _isMatchmaking(game.phase);
    final ink = Theme.of(context).colorScheme.onSurface;
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final description = widget.pocket
        ? '[Pocket] VS; color in more cells than your opponent to win'
        : 'Irodoku VS; color in more cells than your opponent to win';
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
            Text(
              widget.pocket ? '[Graffiti]' : 'Graffiti',
              style: titleStyle,
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: waiting
                  ? _waiting(game, ink)
                  : _form(game, ink, description),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(GraffitiProvider game, Color ink, String description) {
    final quick = widget.pocket ? '[Quick Play]' : 'Quick Play';
    final create = widget.pocket ? '[Create Room]' : 'Create Room';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 18),
        MenuActionButton(
          label: quick,
          enabled: !game.busy,
          onPressed: () => unawaited(_online(game.quickPlay)),
        ),
        const SizedBox(height: 12),
        MenuActionButton(
          label: create,
          enabled: !game.busy,
          onPressed: () => unawaited(_online(game.createRoom)),
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
              onPressed: game.busy
                  ? null
                  : () => unawaited(_online(() => game.joinRoom(_join.text))),
              child: const Text('Join'),
            ),
          ],
        ),
        if (game.statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            game.statusMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ink.withValues(alpha: 0.7),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _cancelButton(ink),
      ],
    );
  }

  Widget _waiting(GraffitiProvider game, Color ink) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (game.statusMessage != null)
          Text(
            game.statusMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (game.isHost && game.roomCode != null) ...[
          const SizedBox(height: 12),
          Text(
            game.roomCode!,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
        const SizedBox(height: 8),
        _cancelButton(ink),
      ],
    );
  }

  Widget _cancelButton(Color ink) {
    return TextButton(
      onPressed: () => unawaited(_cancel()),
      child: Text('Cancel', style: TextStyle(color: ink)),
    );
  }
}
