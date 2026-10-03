import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/daily_irodoku.dart';
import '../models/daily_leaderboard.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../services/daily_leaderboard_service.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/typing_title.dart';

class DailyLeaderboardScreen extends StatefulWidget {
  final bool pocket;

  const DailyLeaderboardScreen({super.key, this.pocket = false});

  @override
  State<DailyLeaderboardScreen> createState() => _DailyLeaderboardScreenState();
}

class _DailyLeaderboardScreenState extends State<DailyLeaderboardScreen> {
  Future<DailyLeaderboardBoard>? _future;
  late final TextEditingController _nameController;
  bool _resolvedName = false;
  bool _needName = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedName) return;
    _resolvedName = true;
    final settings = context.read<SettingsProvider>();
    _nameController.text = settings.displayName;
    _needName = DisplayName.trySanitize(settings.displayName) == null;
    if (!_needName) {
      _future = _submitAndLoad();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<DailyLeaderboardBoard> _submitAndLoad() {
    final game = context.read<GameProvider>();
    final settings = context.read<SettingsProvider>();
    final dayKey = game.dailyDayKey ?? DailyIrodoku.dayKeyFor(DateTime.now());
    final name = DisplayName.orFallback(settings.displayName);
    final submit = game.isDaily && game.isWon
        ? DailyLeaderboardService.submit(
            dayKey: dayKey,
            pocket: widget.pocket,
            name: name,
            ms: game.elapsed.inMilliseconds,
          )
        : Future<bool>.value(true);
    return submit.then(
      (_) => DailyLeaderboardService.fetch(
        dayKey: dayKey,
        pocket: widget.pocket,
      ),
    );
  }

  Future<void> _continueWithName(String name) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await context.read<SettingsProvider>().setDisplayName(name);
    if (!mounted) return;
    setState(() {
      _needName = false;
      _future = _submitAndLoad();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.pocket ? '[Leaderboard]' : 'Leaderboard';
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          leading: const MenuBackButton(),
          title: TypingTitle(text: title),
          actions: [
            IconButton(
              tooltip: 'Main Menu',
              icon: Image.asset(
                'assets/icons/settings.png',
                width: 24,
                height: 24,
                filterQuality: FilterQuality.none,
              ),
              onPressed: withMenuSelect(context, () {
                final navigator = Navigator.of(context);
                navigator.pop();
                if (navigator.canPop()) navigator.pop();
              }),
            ),
          ],
        ),
        body: _needName ? _buildNamePrompt(context) : _buildBoard(context),
      ),
    );
  }

  Widget _buildNamePrompt(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final onInk = dark ? Colors.black : Colors.white;
    final sanitized = DisplayName.trySanitize(_nameController.text);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Set Name',
              textAlign: TextAlign.center,
              style: TextStyle(color: ink),
            ),
            content: TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: DisplayName.maxLength,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ._\-]')),
              ],
              textInputAction: TextInputAction.done,
              style: TextStyle(color: ink),
              decoration: InputDecoration(
                hintText: 'Name',
                counterText: '',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: ink.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: ink, width: 2),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (sanitized != null) {
                  _continueWithName(sanitized);
                }
              },
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: onInk,
                ),
                onPressed: sanitized == null
                    ? null
                    : withMenuSelect(
                        context,
                        () => _continueWithName(sanitized),
                      ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final dayKey = DailyIrodoku.dayKeyFor(DateTime.now());
    final date = DailyIrodoku.shortDateLabel(dayKey);
    return FutureBuilder<DailyLeaderboardBoard>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final board = snapshot.data ?? const DailyLeaderboardBoard(top: []);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              date,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (board.top.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'Be the first today.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            else ...[
              for (var i = 0; i < board.top.length; i++)
                _LeaderboardRow(
                  rank: i + 1,
                  entry: board.top[i],
                  highlight: board.you?.uid == board.top[i].uid,
                ),
            ],
            if (board.you != null &&
                (board.youRank == null ||
                    board.youRank! > DailyLeaderboardService.topN)) ...[
              const SizedBox(height: 16),
              const Divider(),
              _LeaderboardRow(
                rank: board.youRank,
                entry: board.you!,
                highlight: true,
                youLabel: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int? rank;
  final DailyLeaderboardEntry entry;
  final bool highlight;
  final bool youLabel;

  const _LeaderboardRow({
    required this.rank,
    required this.entry,
    this.highlight = false,
    this.youLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = youLabel ? '${entry.name} (You)' : entry.name;
    final rankText = rank == null ? '—' : '$rank';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlight
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  rankText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                entry.formattedTime,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
