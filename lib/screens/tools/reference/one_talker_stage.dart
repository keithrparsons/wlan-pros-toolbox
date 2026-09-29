// The stage of the One Talker per Channel lesson (one-talker): the room (each
// access point and its devices, the one talking marked), a bar per device for
// its share of the time, and one airtime pie per channel. Controls live in
// one_talker_controls.dart, so this widget only draws.
//
// States (SOP-007 §5): the model is compiled in, so there is no loading,
// empty or error state; every count from 1 to the cap renders. One device
// alone is a teaching state ("no one to wait for"), drawn in words.
//
// LAYOUT: a phone stacks everything. The presenter layout puts the room and
// the pies on the left and the bars on the right, and scales the whole stage
// down to fit (never a page scroll).
//
// MOTION (§8.8): bars ease to their new length over AppMotion.slow; reduced
// motion makes them jump.
//
// THEME: `context.colors` and the Classroom client palette (GL-003 §8.15.2).
// Every device carries its letter and every bar its percent.
//
// ACCESSIBILITY: the headline is a live region; each bar is one semantics
// node ("Device B, access point 1: 25% of the time").
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'one_talker_controller.dart';
import 'one_talker_parts.dart';

/// The headline for one channel, in plain words.
String channelHeadline(OneTalkerChannel ch, {required bool bothAps}) {
  final int n = ch.talkers;
  final String where = bothAps
      ? 'Channel ${ch.number}, both access points'
      : 'Channel ${ch.number}';
  if (n == 1) {
    return '$where: 1 device, no one to wait for. It gets all of the time '
        '(100%).';
  }
  final OneTalkerClient? slow = ch.clients
      .where((OneTalkerClient k) => k.slow)
      .firstOrNull;
  if (slow != null) {
    return '$where: $n devices get ${shareFraction(n)} of the turns each, '
        'but slow device ${slow.letter} uses '
        '${sharePercent(slow.airtimeShare)} of the time.';
  }
  return '$where: $n devices take turns. Each gets ${shareFraction(n)} of '
      'the time (${sharePercent(1 / n)}).';
}

class OneTalkerStage extends StatelessWidget {
  const OneTalkerStage({super.key, required this.controller});

  final OneTalkerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final OneTalkerScene scene = controller.scene;
        if (!PresenterMode.isActive(context)) {
          return _Phone(scene: scene, turn: controller.turn);
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: c.maxWidth,
              child: _Presenter(scene: scene, turn: controller.turn),
            ),
          ),
        );
      },
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({required this.scene, required this.turn});

  final OneTalkerScene scene;
  final int turn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Headlines(scene: scene),
        const SizedBox(height: AppSpacing.sm),
        _Rooms(scene: scene, turn: turn),
        const SizedBox(height: AppSpacing.md),
        _Bars(scene: scene),
        const SizedBox(height: AppSpacing.md),
        _Pies(scene: scene),
      ],
    );
  }
}

class _Presenter extends StatelessWidget {
  const _Presenter({required this.scene, required this.turn});

  final OneTalkerScene scene;
  final int turn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Headlines(scene: scene),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Rooms(scene: scene, turn: turn),
                  const SizedBox(height: AppSpacing.md),
                  _Pies(scene: scene),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(flex: 4, child: _Bars(scene: scene)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headline.
// ─────────────────────────────────────────────────────────────────────────────

class _Headlines extends StatelessWidget {
  const _Headlines({required this.scene});

  final OneTalkerScene scene;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final PresenterScale s = PresenterMode.scaleOf(context);
    final TextStyle style = s.headlineStyle(
      (t.titleMedium ?? const TextStyle()).copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final OneTalkerChannel ch in scene.channels)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                channelHeadline(ch, bothAps: ch.aps.length > 1),
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The room.
// ─────────────────────────────────────────────────────────────────────────────

class _Rooms extends StatelessWidget {
  const _Rooms({required this.scene, required this.turn});

  final OneTalkerScene scene;
  final int turn;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final Set<int> talking = <int>{
      for (final OneTalkerClient k in scene.talkingAt(turn)) k.index,
    };
    final List<OneTalkerClient> all = scene.clients;
    final bool two = scene.config.hasSecondAp;
    List<OneTalkerClient> on(int ap) =>
        all.where((OneTalkerClient k) => k.ap == ap).toList();
    int channelOf(int ap) => on(ap).first.channel;

    final List<Widget> rooms = <Widget>[
      _Room(ap: 1, channel: channelOf(1), clients: on(1), talking: talking),
      if (two)
        _Room(ap: 2, channel: channelOf(2), clients: on(2), talking: talking),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (rooms.length == 1 || c.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < rooms.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    rooms[i],
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: rooms[0]),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: rooms[1]),
                ],
              ),
            );
          },
        ),
        if (two) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _WaitingLines(same: scene.channels.length == 1),
        ],
        const SizedBox(height: AppSpacing.xs),
        for (final OneTalkerChannel ch in scene.channels)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const ExcludeSemantics(
                  child: WalkieTalkie(talking: true, size: 22),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _talkingLine(ch, turn),
                    style: t.bodyMedium?.copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _talkingLine(OneTalkerChannel ch, int turn) {
    final OneTalkerClient k = ch.talkingAt(turn);
    final int others = ch.talkers - 1;
    final String wait = switch (others) {
      0 => 'No one else is waiting.',
      1 => 'The other device waits.',
      _ => 'The other $others wait.',
    };
    return 'Channel ${ch.number}, talking now: ${k.letter}. $wait';
  }
}

class _Room extends StatelessWidget {
  const _Room({
    required this.ap,
    required this.channel,
    required this.clients,
    required this.talking,
  });

  final int ap;
  final int channel;
  final List<OneTalkerClient> clients;
  final Set<int> talking;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final String spoken =
        'Access point $ap on channel $channel, ${clients.length} '
        '${clients.length == 1 ? 'device' : 'devices'}: '
        '${clients.map((OneTalkerClient k) => talking.contains(k.index) ? '${k.letter} talking' : k.letter).join(', ')}';
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.router_outlined, color: colors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Access point $ap',
                    style: t.labelLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface3,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    'Channel $channel',
                    style: t.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xxs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final OneTalkerClient k in clients)
                  OtClientChip(client: k, talking: talking.contains(k.index)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The band under two rooms: one waiting line, or two.
class _WaitingLines extends StatelessWidget {
  const _WaitingLines({required this.same});

  final bool same;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              same ? Icons.merge_type_rounded : Icons.call_split_rounded,
              color: colors.textAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              same
                  ? 'Same channel: one waiting line for both access points.'
                  : 'Two channels: two waiting lines, and two devices can '
                        'transmit at once, one on each channel.',
              style: t.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The bars.
// ─────────────────────────────────────────────────────────────────────────────

class _Bars extends StatelessWidget {
  const _Bars({required this.scene});

  final OneTalkerScene scene;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool split = scene.channels.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            "Each device's share of the time",
            style: t.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final OneTalkerChannel ch in scene.channels) ...<Widget>[
          if (split) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Channel ${ch.number}',
              style: t.labelLarge?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          for (final OneTalkerClient k in ch.clients) _BarRow(client: k),
        ],
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.client});

  final OneTalkerClient client;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final WifiLabClientStyle st = WifiLabClientPalette.of(client.index, colors);
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final String pct = sharePercent(client.airtimeShare);
    final double barH = PresenterMode.scaleOf(context).markerSize(14);
    return Semantics(
      container: true,
      label:
          'Device ${client.letter}${client.slow ? ', slow' : ''}, access '
          'point ${client.ap}: $pct of the time',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
        child: Row(
          children: <Widget>[
            OtClientChip(client: client, diameter: 22),
            const SizedBox(width: AppSpacing.xs),
            if (client.slow) ...<Widget>[
              Text(
                'slow',
                style: t.labelMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Container(
                height: barH,
                decoration: BoxDecoration(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(barH / 2),
                  border: Border.all(color: colors.border),
                ),
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: reduce ? Duration.zero : AppMotion.slow,
                  curve: AppMotion.standardEase,
                  widthFactor: client.airtimeShare,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: st.hue,
                      borderRadius: BorderRadius.circular(barH / 2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: 48,
              child: Text(
                pct,
                textAlign: TextAlign.end,
                style: t.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The pies.
// ─────────────────────────────────────────────────────────────────────────────

class _Pies extends StatelessWidget {
  const _Pies({required this.scene});

  final OneTalkerScene scene;

  @override
  Widget build(BuildContext context) {
    final List<OneTalkerChannel> chs = scene.channels;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final OneTalkerChannel ch in chs)
          Flexible(
            child: OtPie(channel: ch, diameter: chs.length > 1 ? 130 : 160),
          ),
      ],
    );
  }
}
