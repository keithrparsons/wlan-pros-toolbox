// DfsSimulatorStage: the pictures half of DFS and Radar.
//
// The 5 GHz channel strip (every 20 MHz channel of the region's plan, DFS
// channels marked, each showing what it is doing now: available, CAC
// running, in use, or blocked with its non-occupancy countdown) and, below
// it, a timeline for the AP and its three clients: CAC, service, radar,
// the move, the outage gap, and which channels are blocked. Takes the shared
// DfsSimulatorController and nothing else, so a phone layout can stack it
// with DfsSimulatorControls and a presenter layout can put the two side by
// side.
//
// COLOR (GL-003 §8.13, §8.3): lime marks the channel in use and the time
// the AP and clients are served (the active state). The status hues are
// verdicts about a channel or about service, always with a word or an icon:
// amber = not usable yet (CAC running), red = may not be used (blocked after
// radar) or no service. Everything else is the neutral stack.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/dfs_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import 'dfs_simulator_controller.dart';
import 'dfs_simulator_parts.dart';

class DfsSimulatorStage extends StatelessWidget {
  const DfsSimulatorStage({super.key, required this.controller});

  final DfsSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StripCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _TimelineCard(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Channel strip ───────────────────────────────────────────────────────────

/// Cells per strip row: the widest row (100 to 144) sets the cell width.
const int _kCellsPerRow = 12;

class _StripRow {
  const _StripRow(this.heading, this.channels);

  final String heading;
  final List<int> channels;
}

List<_StripRow> _stripRows(DfsRegion region) {
  final bool eu = region == DfsRegion.eu;
  return <_StripRow>[
    const _StripRow('5150-5350 MHz: 36 to 48, then DFS 52 to 64', <int>[
      36, 40, 44, 48, 52, 56, 60, 64, //
    ]),
    _StripRow(
      eu
          ? '5470-5725 MHz: DFS 100 to 140; 144 is outside the EU plan'
          : '5470-5730 MHz: DFS 100 to 144',
      const <int>[100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144],
    ),
    _StripRow(
      eu
          ? '5725-5835 MHz: 149 to 165, not in the EU plan used here'
          : '5725-5835 MHz: 149 to 165',
      const <int>[149, 153, 157, 161, 165],
    ),
  ];
}

class _StripCard extends StatelessWidget {
  const _StripCard({required this.controller});

  final DfsSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final DfsSimulatorController c = controller;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DfsRegion region = c.config.region;
    final List<_StripRow> rows = _stripRows(region);
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DfsSectionLabel(
            '5 GHz channels, ${region.label}, at ${fmtClock(c.timeS)}',
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double gap = 2;
              final double cellW =
                  (box.maxWidth - gap * (_kCellsPerRow - 1)) / _kCellsPerRow;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final _StripRow row in rows) ...<Widget>[
                    ExcludeSemantics(
                      child: Text(
                        row.heading,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: <Widget>[
                        for (
                          int i = 0;
                          i < row.channels.length;
                          i++
                        ) ...<Widget>[
                          if (i > 0) SizedBox(width: gap),
                          SizedBox(
                            width: cellW,
                            child: _ChannelCell(
                              channel: row.channels[i],
                              status: c.run.statusOf(row.channels[i], c.timeS),
                              now: c.timeS,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (region == DfsRegion.eu && row.channels.contains(120))
                      _WeatherBracket(cellW: cellW, gap: gap),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              );
            },
          ),
          const _StripLegend(),
        ],
      ),
    );
  }
}

/// A bracket under 120 to 128 (cells 5 to 7 of the 100-144 row): the EU
/// 5600-5650 MHz band that takes a 10-minute CAC.
class _WeatherBracket extends StatelessWidget {
  const _WeatherBracket({required this.cellW, required this.gap});

  final double cellW;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(left: 5 * (cellW + gap), top: AppSpacing.xxs),
      child: Semantics(
        label:
            'Channels 120, 124 and 128 sit in 5600 to 5650 megahertz and need '
            'a 10-minute channel availability check in the EU.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 3 * cellW + 2 * gap,
              height: 2,
              color: colors.borderStrong,
            ),
            const SizedBox(height: 2),
            Text(
              '5600-5650 MHz: 10-min CAC',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CellLook {
  const _CellLook({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.ink,
    this.icon,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final Color ink;
  final IconData? icon;
}

_CellLook _lookFor(ChannelUse use, AppColorScheme colors) {
  final double tint = colors.isLight ? 0.14 : 0.18;
  switch (use) {
    case ChannelUse.notInPlan:
      return _CellLook(
        fill: Colors.transparent,
        border: colors.border,
        borderWidth: 1,
        ink: colors.textDisabled,
        icon: Icons.remove_rounded,
      );
    case ChannelUse.available:
      return _CellLook(
        fill: colors.surface2,
        border: colors.border,
        borderWidth: 1,
        ink: colors.textPrimary,
      );
    case ChannelUse.cac:
      return _CellLook(
        fill: colors.statusWarning.withValues(alpha: tint),
        border: colors.statusWarning,
        borderWidth: 1.5,
        ink: colors.textPrimary,
        icon: Icons.hourglass_top_rounded,
      );
    case ChannelUse.inUse:
      return _CellLook(
        fill: colors.primary.withValues(alpha: tint),
        border: colors.textAccent,
        borderWidth: 2,
        ink: colors.textPrimary,
        icon: Icons.wifi_rounded,
      );
    case ChannelUse.leaving:
    case ChannelUse.blocked:
      return _CellLook(
        fill: colors.statusDanger.withValues(alpha: tint),
        border: colors.statusDanger,
        borderWidth: 1.5,
        ink: colors.textPrimary,
        icon: Icons.block_rounded,
      );
  }
}

/// Icon hue: the verdict color, lime for in use.
Color _iconColor(ChannelUse use, AppColorScheme colors) {
  switch (use) {
    case ChannelUse.cac:
      return colors.statusWarning;
    case ChannelUse.inUse:
      return colors.textAccent;
    case ChannelUse.leaving:
    case ChannelUse.blocked:
      return colors.statusDanger;
    case ChannelUse.notInPlan:
    case ChannelUse.available:
      return colors.textTertiary;
  }
}

String _cellSemantics(int ch, ChannelStatus s, double now) {
  final String dfs = s.isDfs ? ', DFS' : '';
  switch (s.use) {
    case ChannelUse.notInPlan:
      return 'Channel $ch, not in this plan';
    case ChannelUse.available:
      return 'Channel $ch$dfs, available';
    case ChannelUse.cac:
      return 'Channel $ch$dfs, channel availability check, '
          '${fmtSpan((s.untilS ?? now) - now)} left';
    case ChannelUse.inUse:
      return 'Channel $ch$dfs, in use';
    case ChannelUse.leaving:
      return 'Channel $ch$dfs, radar detected, the AP is leaving';
    case ChannelUse.blocked:
      return 'Channel $ch$dfs, blocked after radar until '
          '${fmtClock(s.untilS ?? now)}';
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.status,
    required this.now,
  });

  final int channel;
  final ChannelStatus status;
  final double now;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final _CellLook look = _lookFor(status.use, colors);
    final TextStyle numStyle = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption - 2,
      color: look.ink,
      fontWeight: status.use == ChannelUse.inUse
          ? FontWeight.w600
          : FontWeight.w400,
      decoration: status.use == ChannelUse.notInPlan
          ? TextDecoration.lineThrough
          : null,
      decorationColor: look.ink,
    );
    return Semantics(
      label: _cellSemantics(channel, status, now),
      excludeSemantics: true,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: look.fill,
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
          border: Border.all(color: look.border, width: look.borderWidth),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$channel', style: numStyle, maxLines: 1),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 14,
              child: look.icon == null
                  ? null
                  : Icon(
                      look.icon,
                      size: 14,
                      color: _iconColor(status.use, colors),
                    ),
            ),
            const Spacer(),
            // The DFS mark: a bar along the bottom of every DFS cell.
            Container(
              height: 3,
              margin: const EdgeInsets.fromLTRB(3, 0, 3, 3),
              decoration: BoxDecoration(
                color: status.isDfs ? colors.textTertiary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripLegend extends StatelessWidget {
  const _StripLegend();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    Widget item(IconData? icon, Color iconColor, String label, {Widget? mark}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ?mark,
          if (icon != null) Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }

    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          item(Icons.wifi_rounded, colors.textAccent, 'In use'),
          item(
            Icons.hourglass_top_rounded,
            colors.statusWarning,
            'CAC: listening, not usable yet',
          ),
          item(
            Icons.block_rounded,
            colors.statusDanger,
            'Blocked 30 min after radar',
          ),
          item(
            null,
            colors.textTertiary,
            'DFS channel',
            mark: Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: colors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          item(Icons.remove_rounded, colors.textDisabled, 'Not in the plan'),
        ],
      ),
    );
  }
}

// ── Timeline ────────────────────────────────────────────────────────────────

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.controller});

  final DfsSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final DfsSimulatorController c = controller;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;
    final (double w0, double w1) = c.window;
    final DfsTimelineStyle style = DfsTimelineStyle(
      accent: colors.textAccent,
      primary: colors.primary,
      warning: colors.statusWarning,
      danger: colors.statusDanger,
      text: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      future: colors.surface2,
      tint: colors.isLight ? 0.22 : 0.28,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption - 2,
        color: colors.textSecondary,
      ),
      rowLabelStyle:
          text.bodySmall?.copyWith(color: colors.textSecondary) ??
          TextStyle(color: colors.textSecondary),
    );
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DfsSectionLabel('Timeline: the AP and its clients'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<DfsTimelineView>(
            value: c.view,
            semanticLabel: 'Timeline span',
            expand: true,
            items: <AppToggleItem<DfsTimelineView>>[
              for (final DfsTimelineView v in DfsTimelineView.values)
                (v, v.label),
            ],
            onChanged: (DfsTimelineView v) => c.view = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _timelineSemantics(c),
            excludeSemantics: true,
            child: SizedBox(
              height: 200,
              child: CustomPaint(
                painter: DfsTimelinePainter(
                  run: c.run,
                  now: c.timeS,
                  w0: w0,
                  w1: w1,
                  style: style,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _TimelineLegend(),
        ],
      ),
    );
  }

  static String _timelineSemantics(DfsSimulatorController c) {
    final DfsRun run = c.run;
    final double now = c.timeS;
    final StringBuffer b = StringBuffer(
      'Timeline up to ${fmtClock(now)}. AP: ',
    );
    for (final ApSegment s in run.segments) {
      if (s.startS > now) break;
      final double end = s.endS < now ? s.endS : now;
      final String what = switch (s.phase) {
        ApPhase.cac => 'channel availability check',
        ApPhase.service => 'serving',
        ApPhase.moving => 'leaving after radar',
      };
      b.write(
        '$what on ${placementLabel(s.channel)} from ${fmtClock(s.startS)} '
        'to ${fmtClock(end)}. ',
      );
    }
    final List<RadarHit> hits = run.hitsUpTo(now);
    if (hits.isEmpty) {
      b.write('No radar yet. ');
    } else {
      for (final RadarHit h in hits) {
        b.write('Radar at ${fmtClock(h.timeS)}. ');
      }
    }
    final int connected = <int>[
      for (int i = 0; i < run.clients.length; i++)
        if (run.clientConnectedAt(i, now)) i,
    ].length;
    b.write('$connected of ${run.clients.length} clients connected now.');
    return b.toString();
  }
}

class _TimelineLegend extends StatelessWidget {
  const _TimelineLegend();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double tint = colors.isLight ? 0.22 : 0.28;
    Widget swatch(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 16,
          height: 10,
          decoration: BoxDecoration(
            color: c.withValues(alpha: tint),
            border: Border.all(color: c, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          swatch(colors.textAccent, 'Serving (channel shown)'),
          swatch(colors.statusWarning, 'CAC'),
          swatch(colors.statusDanger, 'No service, leaving, blocked'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.arrow_drop_down, size: 18, color: colors.statusDanger),
              Text(
                'Radar',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

@immutable
class DfsTimelineStyle {
  const DfsTimelineStyle({
    required this.accent,
    required this.primary,
    required this.warning,
    required this.danger,
    required this.text,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.axis,
    required this.future,
    required this.tint,
    required this.labelStyle,
    required this.rowLabelStyle,
  });

  final Color accent;
  final Color primary;
  final Color warning;
  final Color danger;
  final Color text;
  final Color secondary;
  final Color tertiary;
  final Color grid;
  final Color axis;
  final Color future;
  final double tint;
  final TextStyle labelStyle;
  final TextStyle rowLabelStyle;

  @override
  bool operator ==(Object other) =>
      other is DfsTimelineStyle &&
      other.accent == accent &&
      other.warning == warning &&
      other.danger == danger &&
      other.text == text &&
      other.future == future &&
      other.tint == tint &&
      other.labelStyle == labelStyle;

  @override
  int get hashCode =>
      Object.hash(accent, warning, danger, text, future, tint, labelStyle);
}

/// Rows: AP, three clients, and the blocked channels.
class DfsTimelinePainter extends CustomPainter {
  DfsTimelinePainter({
    required this.run,
    required this.now,
    required this.w0,
    required this.w1,
    required this.style,
  });

  final DfsRun run;
  final double now;
  final double w0;
  final double w1;
  final DfsTimelineStyle style;

  static const double _labelW = 64;
  static const double _axisH = 18;
  static const double _markerH = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final List<String> rows = <String>[
      'AP',
      for (int i = 0; i < run.clients.length; i++) 'Client ${i + 1}',
      'Blocked',
    ];
    final double top = _markerH;
    final double plotH = size.height - _axisH - top;
    final double rowH = plotH / rows.length;
    final double left = _labelW;
    final double right = size.width - 4;
    final double span = w1 - w0;
    double x(double t) => left + (t - w0) / span * (right - left);
    final double shown = now.clamp(w0, w1);
    final double xNow = x(shown);

    // The future: a quiet band, so the student sees where "now" is.
    if (xNow < right) {
      canvas.drawRect(
        Rect.fromLTRB(xNow, top, right, top + plotH),
        Paint()..color = style.future,
      );
    }

    // Row labels and separators.
    for (int i = 0; i < rows.length; i++) {
      final double y = top + i * rowH;
      _text(
        canvas,
        rows[i],
        style.rowLabelStyle,
        Offset(0, y + rowH / 2),
        alignLeft: true,
        vCenter: true,
        maxWidth: _labelW - 4,
      );
      canvas.drawLine(
        Offset(left, y + rowH),
        Offset(right, y + rowH),
        Paint()
          ..color = style.grid
          ..strokeWidth = 1,
      );
    }

    // Grid and axis labels. A label that would touch the one before it is
    // skipped (the grid line stays), so phone widths never print "0:0010:00".
    final double tick = span > 600 ? 600 : 30;
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    double lastRight = double.negativeInfinity;
    for (double t = (w0 / tick).ceil() * tick; t <= w1 + 1e-6; t += tick) {
      final double gx = x(t);
      canvas.drawLine(Offset(gx, top), Offset(gx, top + plotH), grid);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: fmtClock(t), style: style.labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final double lx = (gx - tp.width / 2).clamp(left, right - tp.width);
      if (lx < lastRight + 6) continue;
      tp.paint(canvas, Offset(lx, top + plotH + 3));
      lastRight = lx + tp.width;
    }

    // Everything below is drawn only up to now.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, 0, xNow, size.height));

    Rect bar(int row, double a, double b) {
      final double y = top + row * rowH;
      return Rect.fromLTRB(x(a), y + 4, x(b), y + rowH - 4);
    }

    void block(Rect r, Color c, String? label) {
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = c.withValues(alpha: style.tint));
      canvas.drawRRect(
        rr,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (label != null) {
        final double visibleRight = r.right < xNow ? r.right : xNow;
        final double w = visibleRight - r.left;
        if (w > 36) {
          _text(
            canvas,
            label,
            style.labelStyle.copyWith(color: style.text),
            Offset(r.left + 4, r.center.dy),
            alignLeft: true,
            vCenter: true,
            maxWidth: w - 6,
          );
        }
      }
    }

    // AP row.
    for (final ApSegment s in run.segments) {
      if (s.endS < w0 || s.startS > w1) continue;
      final Rect r = bar(0, s.startS, s.endS);
      switch (s.phase) {
        case ApPhase.cac:
          block(r, style.warning, 'CAC ${placementLabel(s.channel)}');
        case ApPhase.service:
          block(r, style.accent, placementLabel(s.channel));
        case ApPhase.moving:
          block(r, style.danger, null);
      }
    }

    // Client rows: served spans in lime, the rest (up to now) as no service.
    for (int i = 0; i < run.clients.length; i++) {
      double cursor = 0;
      for (final ClientSpan s in run.clients[i]) {
        if (s.startS > cursor) {
          block(bar(i + 1, cursor, s.startS), style.danger, 'No service');
        }
        block(bar(i + 1, s.startS, s.endS), style.accent, null);
        cursor = s.endS;
      }
      if (cursor < kDfsHorizonS) {
        block(bar(i + 1, cursor, kDfsHorizonS), style.danger, 'No service');
      }
    }

    // Blocked row: one bar per block, stacked thin if they overlap.
    final int blockedRow = rows.length - 1;
    for (int k = 0; k < run.blocks.length; k++) {
      final ChannelBlock b = run.blocks[k];
      final Rect full = bar(blockedRow, b.fromS, b.untilS);
      final int lanes = run.blocks.length.clamp(1, 3);
      final double laneH = full.height / lanes;
      final Rect r = Rect.fromLTWH(
        full.left,
        full.top + (k % lanes) * laneH,
        full.width,
        laneH - 1,
      );
      final String label = b.channels.length == 1
          ? '${b.channels.first}'
          : '${b.channels.first}-${b.channels.last}';
      block(r, style.danger, lanes == 1 ? 'ch $label' : label);
    }

    canvas.restore();

    // Radar markers (up to now).
    for (final RadarHit h in run.hitsUpTo(now)) {
      if (h.timeS < w0 || h.timeS > w1) continue;
      final double rx = x(h.timeS);
      final Paint p = Paint()
        ..color = style.danger
        ..strokeWidth = 2;
      _dashed(canvas, Offset(rx, top), Offset(rx, top + plotH), p);
      final Path tri = Path()
        ..moveTo(rx - 6, 2)
        ..lineTo(rx + 6, 2)
        ..lineTo(rx, _markerH - 2)
        ..close();
      canvas.drawPath(tri, Paint()..color = style.danger);
    }

    // Now cursor.
    if (now >= w0 && now <= w1) {
      canvas.drawLine(
        Offset(xNow, top - 2),
        Offset(xNow, top + plotH),
        Paint()
          ..color = style.text
          ..strokeWidth = 1.5,
      );
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const double dash = 4;
    const double gap = 3;
    double y = a.dy;
    while (y < b.dy) {
      final double y2 = (y + dash).clamp(a.dy, b.dy);
      canvas.drawLine(Offset(a.dx, y), Offset(a.dx, y2), p);
      y += dash + gap;
    }
  }

  void _text(
    Canvas canvas,
    String s,
    TextStyle st,
    Offset at, {
    bool alignLeft = false,
    bool vCenter = false,
    double? maxWidth,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final double dx = alignLeft ? at.dx : at.dx - tp.width / 2;
    final double dy = vCenter ? at.dy - tp.height / 2 : at.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(DfsTimelinePainter old) =>
      old.run != run ||
      old.now != now ||
      old.w0 != w0 ||
      old.w1 != w1 ||
      old.style != style;
}
