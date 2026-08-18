import 'package:flutter/material.dart';

import '../models/player_xp.dart';

const _bonusStartMs = 210;
const _bonusStaggerMs = 80;
const _popMs = 180;
const _levelAfterBonusMs = 150;

/// XP breakdown + level bar shown on Victory and Stats.
class XpGainPanel extends StatelessWidget {
  final XpAward award;
  final Color ink;
  final bool compact;

  const XpGainPanel({
    super.key,
    required this.award,
    required this.ink,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lineStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: ink,
        );
    final amountStyle = lineStyle?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final lines = award.breakdown.length;
    final lastBonusDelayMs =
        _bonusStartMs + _bonusStaggerMs * (lines > 0 ? lines - 1 : 0);
    final levelDelayMs = lines == 0
        ? _bonusStartMs
        : lastBonusDelayMs + _popMs + _levelAfterBonusMs;
    final levelDelay = Duration(milliseconds: levelDelayMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines; i++)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 2 : 4),
            child: compact
                ? _xpLine(award.breakdown[i], lineStyle, amountStyle)
                : _PopIn(
                    delay: Duration(
                      milliseconds: _bonusStartMs + _bonusStaggerMs * i,
                    ),
                    child: _xpLine(award.breakdown[i], lineStyle, amountStyle),
                  ),
          ),
        if (compact) ...[
          const SizedBox(height: 12),
          XpLevelBar(
            totalXp: award.newTotal,
            fromTotalXp: award.previousTotal,
            ink: ink,
            compact: true,
          ),
        ] else
          _RevealDown(
            delay: levelDelay,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                XpLevelBar(
                  totalXp: award.newTotal,
                  fromTotalXp: award.previousTotal,
                  ink: ink,
                  staggerPop: true,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _xpLine(
    ({String label, int xp}) line,
    TextStyle? lineStyle,
    TextStyle? amountStyle,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(line.label, style: lineStyle),
        ),
        Text(line.xp >= 0 ? '+${line.xp}' : '${line.xp}', style: amountStyle),
      ],
    );
  }
}

class _RevealDown extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _RevealDown({required this.delay, required this.child});

  @override
  State<_RevealDown> createState() => _RevealDownState();
}

class _RevealDownState extends State<_RevealDown>
    with SingleTickerProviderStateMixin {
  static const _expandMs = 200;
  late final AnimationController _controller;
  bool _showChild = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _expandMs),
    );
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _showChild = true);
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
      axisAlignment: -1,
      child: _showChild ? widget.child : const SizedBox.shrink(),
    );
  }
}

class _PopIn extends StatefulWidget {
  final Duration delay;
  final Widget child;
  final Alignment alignment;

  const _PopIn({
    required this.delay,
    required this.child,
    this.alignment = Alignment.center,
  });

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _popMs),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
      child: ScaleTransition(
        alignment: widget.alignment,
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

class XpLevelBar extends StatefulWidget {
  final int totalXp;
  final int? fromTotalXp;
  final Color ink;
  final bool compact;
  final bool staggerPop;

  const XpLevelBar({
    super.key,
    required this.totalXp,
    this.fromTotalXp,
    required this.ink,
    this.compact = false,
    this.staggerPop = false,
  });

  @override
  State<XpLevelBar> createState() => _XpLevelBarState();
}

class _XpLevelBarState extends State<XpLevelBar> {
  late bool _xpTweenStarted;
  late bool _barTweenStarted;

  @override
  void initState() {
    super.initState();
    final delayed = widget.staggerPop;
    _xpTweenStarted = !delayed;
    _barTweenStarted = !delayed;
    if (delayed) {
      Future<void>.delayed(
        const Duration(milliseconds: _bonusStaggerMs),
        () {
          if (mounted) setState(() => _xpTweenStarted = true);
        },
      );
      Future<void>.delayed(
        const Duration(milliseconds: _bonusStaggerMs * 2),
        () {
          if (mounted) setState(() => _barTweenStarted = true);
        },
      );
    }
  }

  Widget _pop({
    required Duration extra,
    required Widget child,
    Alignment alignment = Alignment.center,
  }) {
    if (!widget.staggerPop) return child;
    return _PopIn(
      delay: extra,
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalXp = widget.totalXp;
    final fromTotalXp = widget.fromTotalXp;
    final compact = widget.compact;
    final ink = widget.ink;
    final level = PlayerXp.levelFor(totalXp);
    final fromLevel =
        fromTotalXp == null ? level : PlayerXp.levelFor(fromTotalXp);
    final fromProgress = PlayerXp.progress(fromTotalXp ?? totalXp);
    final progress = PlayerXp.progress(totalXp);
    final fromFraction = fromLevel < level
        ? 0.0
        : PlayerXp.progressFraction(fromTotalXp ?? totalXp);
    final fraction = PlayerXp.progressFraction(totalXp);
    final xpIntoLevel = progress.intoLevel;
    final xpForLevel = progress.toNext;
    final fromIntoLevel =
        fromLevel < level ? 0 : fromProgress.intoLevel;
    final muted = ink.withValues(alpha: 0.55);
    final levelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _pop(
              extra: Duration.zero,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Level ', style: levelStyle),
                  if (fromLevel < level)
                    _LevelUpDigit(
                      from: fromLevel,
                      to: level,
                      style: levelStyle,
                      delay: const Duration(milliseconds: 630),
                    )
                  else
                    Text('$level', style: levelStyle),
                ],
              ),
            ),
            const Spacer(),
            _pop(
              extra: const Duration(milliseconds: _bonusStaggerMs),
              alignment: Alignment.centerRight,
              child: TweenAnimationBuilder<int>(
                key: ValueKey(_xpTweenStarted),
                tween: IntTween(
                  begin: fromIntoLevel,
                  end: _xpTweenStarted ? xpIntoLevel : fromIntoLevel,
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    '$value / $xpForLevel',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        _pop(
          extra: const Duration(milliseconds: _bonusStaggerMs * 2),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_barTweenStarted),
            tween: Tween(
              begin: fromFraction,
              end: _barTweenStarted ? fraction : fromFraction,
            ),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: compact ? 6 : 8,
                  backgroundColor: ink.withValues(alpha: 0.12),
                  color: ink,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LevelUpDigit extends StatefulWidget {
  final int from;
  final int to;
  final TextStyle? style;
  final Duration delay;

  const _LevelUpDigit({
    required this.from,
    required this.to,
    required this.style,
    this.delay = const Duration(milliseconds: 625),
  });

  @override
  State<_LevelUpDigit> createState() => _LevelUpDigitState();
}

class _LevelUpDigitState extends State<_LevelUpDigit>
    with SingleTickerProviderStateMixin {
  static const _swapAt = 0.42;
  late final AnimationController _controller;
  late final Animation<double> _out;
  late final Animation<double> _in;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _out = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, _swapAt, curve: Curves.easeIn),
      ),
    );
    _in = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(_swapAt, 1, curve: Curves.easeOut),
      ),
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final outgoing = _controller.value < _swapAt;
        return Transform.scale(
          scale: outgoing ? _out.value : _in.value,
          child: Text(
            '${outgoing ? widget.from : widget.to}',
            style: widget.style,
          ),
        );
      },
    );
  }
}
