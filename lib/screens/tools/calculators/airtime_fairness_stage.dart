// Airtime Fairness (Wi-Fi Lab) — the STAGE: everything the student watches.
//
// The airtime share bar, the throughput bars and the animated round, drawn
// from the model state it is handed. It holds no inputs and edits nothing, so
// the phone layout can stack it between the controls and a presenter layout
// can put it beside them unchanged.
//
// THEME: context.colors only. Clients are told apart by letter and position,
// never by hue (GL-003 §8.15). Lime marks the quantity the charts are about.
// Status danger appears only in the invalid-input state (§8.13 verdict).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'airtime_fairness_common.dart';
import 'airtime_round_painter.dart';

class AirtimeFairnessStage extends StatelessWidget {
  const AirtimeFairnessStage({
    super.key,
    required this.clients,
    required this.payloadBytes,
    required this.view,
    required this.round,
    this.invalidClient,
  });

  /// Every client's config, or null while any row is invalid.
  final List<ClientConfig>? clients;
  final int payloadBytes;
  final FairnessView view;

  /// 0 to 1 progress of the round animation, owned by the screen.
  final Animation<double> round;

  /// Index of the first invalid client, for the error state.
  final int? invalidClient;

  @override
  Widget build(BuildContext context) {
    final List<ClientConfig>? cs = clients;
    if (cs == null || cs.isEmpty) return _error(context);
    final FairnessResult packet = computeFairness(
      cs,
      FairnessMode.packet,
      payloadBytes: payloadBytes,
    );
    final FairnessResult airtime = computeFairness(
      cs,
      FairnessMode.airtime,
      payloadBytes: payloadBytes,
    );
    FairnessResult pick(FairnessMode m) =>
        m == FairnessMode.packet ? packet : airtime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _shareCard(context, <FairnessResult>[
          for (final FairnessMode m in view.modes) pick(m),
        ]),
        const SizedBox(height: AppSpacing.md),
        _throughputCard(context, packet, airtime),
        const SizedBox(height: AppSpacing.md),
        _roundCard(context, cs),
      ],
    );
  }

  Widget _error(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return LabCard(
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: colors.statusDanger),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Results need a valid rate for every client. Client '
                '${clientLetter(math.max(0, invalidClient ?? 0))} needs a PHY '
                'rate from 1 to 10,000 Mbps.',
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Airtime share ──────────────────────────────────────────────────────────

  Widget _shareCard(BuildContext context, List<FairnessResult> shown) {
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionTitle('Who holds the air'),
          for (final FairnessResult r in shown) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ShareBar(result: r),
          ],
        ],
      ),
    );
  }

  // ── Throughput ─────────────────────────────────────────────────────────────

  Widget _throughputCard(
    BuildContext context,
    FairnessResult packet,
    FairnessResult airtime,
  ) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<FairnessMode> modes = view.modes;
    final bool compare = modes.length > 1;
    FairnessResult pick(FairnessMode m) =>
        m == FairnessMode.packet ? packet : airtime;

    double maxClient = 0;
    double maxTotal = 0;
    for (final FairnessMode m in modes) {
      for (final ClientResult c in pick(m).clients) {
        maxClient = math.max(maxClient, c.throughputMbps);
      }
      maxTotal = math.max(maxTotal, pick(m).aggregateMbps);
    }
    final TextStyle valueStyle = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    final TextStyle tagStyle =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget bar(FairnessMode m, double value, double max, String who) =>
        _ThroughputBar(
          tag: compare
              ? (m == FairnessMode.packet ? 'Packet' : 'Airtime')
              : null,
          filled: !compare || m == FairnessMode.airtime,
          fraction: max <= 0 ? 0 : value / max,
          valueText: '${fmtMbps(value)} Mbps',
          semanticLabel: '$who, ${m.label}: ${fmtMbps(value)} Mbps',
          valueStyle: valueStyle,
          tagStyle: tagStyle,
        );

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionTitle('Throughput'),
          if (compare) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Outlined bars are packet fairness, filled bars are airtime '
              'fairness.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          for (int i = 0; i < packet.clients.length; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            ExcludeSemantics(
              child: Text(
                'Client ${clientLetter(i)} · '
                '${rateText(packet.clients[i].config)}',
                style: labLabelStyle(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (final FairnessMode m in modes)
              bar(
                m,
                pick(m).clients[i].throughputMbps,
                maxClient,
                'Client ${clientLetter(i)}',
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: Text('Total, all clients', style: labLabelStyle(context)),
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final FairnessMode m in modes)
            bar(m, pick(m).aggregateMbps, maxTotal, 'Total'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Client bars share one scale; the total has its own.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Animated round ─────────────────────────────────────────────────────────

  Widget _roundCard(BuildContext context, List<ClientConfig> cs) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double window = roundWindowUs(cs, payloadBytes: payloadBytes);
    final TextStyle letterStyle = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      height: 1.2,
    );
    final TextStyle axis = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textTertiary,
    );

    Widget lane(FairnessMode m) {
      final List<ScheduledTx> s = buildSchedule(
        cs,
        m,
        windowUs: window,
        payloadBytes: payloadBytes,
      );
      final List<ScheduledTx> inWindow = <ScheduledTx>[
        for (final ScheduledTx tx in s)
          if (tx.startUs < window) tx,
      ];
      final List<int> turns = List<int>.filled(cs.length, 0);
      for (final ScheduledTx tx in inWindow) {
        turns[tx.client]++;
      }
      final String order = inWindow
          .map((ScheduledTx tx) => clientLetter(tx.client))
          .join(' ');
      final String counts = <String>[
        for (int i = 0; i < cs.length; i++)
          '${clientLetter(i)} ${turns[i]} turn${turns[i] == 1 ? '' : 's'}',
      ].join(', ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ExcludeSemantics(child: Text(m.label, style: labLabelStyle(context))),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            container: true,
            label:
                '${m.label}, ${fmtUs(window)} of air. Order: $order. '
                '$counts.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: RoundLaneGeometry.height,
                child: CustomPaint(
                  painter: AirtimeRoundPainter(
                    schedule: s,
                    windowUs: window,
                    progress: round,
                    colors: colors,
                    letterStyle: letterStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionTitle('One round on the air'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Each block is one transmission, as wide as the time it holds the '
            'air. The letter above it is the client.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          for (final FairnessMode m in view.modes) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            lane(m),
          ],
          const SizedBox(height: AppSpacing.xxs),
          ExcludeSemantics(
            child: Row(
              children: <Widget>[
                Text('0', style: axis),
                const Spacer(),
                Text(fmtUs(window), style: axis),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _swatch(context, frames: true, label: 'Frames (payload)'),
              _swatch(
                context,
                frames: false,
                label: 'Overhead: wait, backoff, preamble, SIFS, ACK',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatch(
    BuildContext context, {
    required bool frames,
    required String label,
  }) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: AppSpacing.md,
            height: AppSpacing.sm,
            child: CustomPaint(
              painter: RoundSwatchPainter(frames: frames, colors: colors),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Share bar ────────────────────────────────────────────────────────────────

/// One horizontal bar split per client, widths by airtime share. The letter
/// sits in the segment when it fits; the list under the bar always names
/// every client, so a thin segment is never unlabeled.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.result});

  final FairnessResult result;

  static const double _barHeight = 32;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<ClientResult> cs = result.clients;
    final TextStyle inBar = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.onPrimary,
      fontWeight: FontWeight.w600,
    );
    final TextStyle listStyle = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    final String summary = <String>[
      for (final ClientResult c in cs)
        '${clientLetter(c.index)} ${fmtPct(c.airtimeShare)}',
    ].join(', ');

    return Semantics(
      container: true,
      label: '${result.mode.label}, share of airtime: $summary',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(result.mode.label, style: labLabelStyle(context)),
            const SizedBox(height: AppSpacing.xxs),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double usable = box.maxWidth - _gap * (cs.length - 1);
                return SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < cs.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: _gap),
                        _segment(
                          colors,
                          inBar,
                          cs[i],
                          math.max(1, usable * cs[i].airtimeShare),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final ClientResult c in cs)
                  Text(
                    '${clientLetter(c.index)} ${fmtPct(c.airtimeShare)}',
                    style: listStyle,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    AppColorScheme colors,
    TextStyle style,
    ClientResult c,
    double width,
  ) {
    final String letter = clientLetter(c.index);
    final String withPct = '$letter ${fmtPct(c.airtimeShare)}';
    final String? label = width >= AppSpacing.xxl + AppSpacing.xs
        ? withPct
        : width >= AppSpacing.sm
        ? letter
        : null;
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        border: Border.all(color: colors.textAccent),
      ),
      child: label == null
          ? null
          : Text(label, style: style, maxLines: 1, overflow: TextOverflow.clip),
    );
  }
}

// ── Throughput bar ───────────────────────────────────────────────────────────

class _ThroughputBar extends StatelessWidget {
  const _ThroughputBar({
    required this.tag,
    required this.filled,
    required this.fraction,
    required this.valueText,
    required this.semanticLabel,
    required this.valueStyle,
    required this.tagStyle,
  });

  /// Mode name in compare view; null in single-mode view.
  final String? tag;
  final bool filled;
  final double fraction;
  final String valueText;
  final String semanticLabel;
  final TextStyle valueStyle;
  final TextStyle tagStyle;

  static const double _barHeight = 20;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // Room for the widest value label at the current text scale, so the
    // number after the bar never runs off the card.
    final TextPainter tp = TextPainter(
      text: TextSpan(text: '8888.8 Mbps', style: valueStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double reserve = tp.width + AppSpacing.xs;
    tp.dispose();

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              if (tag != null) ...<Widget>[
                SizedBox(
                  width: AppSpacing.xxl,
                  child: Text(tag!, style: tagStyle, maxLines: 1),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double track = math.max(0, box.maxWidth - reserve);
                    final double w = math.max(
                      2,
                      track * fraction.clamp(0.0, 1.0),
                    );
                    return Row(
                      children: <Widget>[
                        Container(
                          width: w,
                          height: _barHeight,
                          decoration: BoxDecoration(
                            color: filled ? colors.primary : colors.surface2,
                            border: Border.all(
                              color: filled
                                  ? colors.textAccent
                                  : colors.borderStrong,
                              width: filled ? 1 : 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            valueText,
                            style: valueStyle,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
