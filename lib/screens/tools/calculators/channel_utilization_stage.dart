// The stage for the Channel Utilization Meter (Wi-Fi Classroom): the meter
// and station count, a strip of channel time scrolling left, the beacon
// intervals with the averaging window sliding over them, the split bar
// (payload, overhead, collisions, other network, non-Wi-Fi, required idle,
// truly spare), and the BSS Load element as a beacon carries it. Reads a
// [ChannelUtilizationController]; owns no state, so a presenter layout can
// place it beside [ChannelUtilizationControls].
//
// COLOR (GL-003 §8.13, §8.15, §8.15.2). This network's frames reuse Airtime
// Anatomy's block styles (paintAirtimeBlock): gray preamble, lime data,
// outlined ACK, dashed SIFS, hatched waiting. Two categories must be told
// apart for the lesson, the neighbor network and non-Wi-Fi energy, so they
// take two hues from the Wi-Fi Classroom client palette (§8.15.2, one
// harmonious family), each with its own pattern (vertical stripes, zigzag).
// Collisions are a failure verdict and use the danger status hue with a
// cross pattern (§8.13). Every block kind is also named in the legend, and
// inside the block when it is wide enough (§8.15.2: never color alone).
//
// MOTION (§8.8). The strip moves only while the channel runs. With reduced
// motion on it never runs by itself; Step and Skip still move it.
//
// ACCESSIBILITY. The drawings are pictures: each carries a worded Semantics
// label, and every number they show is also in text (SC 1.4.1).
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box; the
// strip and the window share the height, and the headline numbers use the
// presenter headline scale.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/channel_utilization_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'airtime_anatomy_timeline.dart'
    show AirtimeBlockStyle, paintAirtimeBlock;
import 'channel_utilization_controller.dart';
import 'channel_utilization_controls.dart' show CuTransport;

// ── Block styles ────────────────────────────────────────────────────────────

/// How one kind of channel time is drawn.
enum CuPaint {
  preamble('Preamble'),
  data('This network: data'),
  ack('ACK (acknowledgment)'),
  gap('SIFS (short interframe space)'),
  wait('Required wait: DIFS (distributed interframe space) and backoff'),
  neighbor('Other network'),
  collision('Collision'),
  nonWifi('Non-Wi-Fi energy'),
  spare('Idle, nobody waiting');

  const CuPaint(this.label);

  final String label;
}

/// The two §8.15.2 hues: index 6 (blue) and 7 (violet) of the client
/// palette.
Color cuNeighborHue(AppColorScheme c) => WifiLabClientPalette.of(6, c).hue;
Color cuNonWifiHue(AppColorScheme c) => WifiLabClientPalette.of(7, c).hue;

/// Paints one block of channel time.
void paintCuBlock(
  Canvas canvas,
  Rect rect,
  CuPaint style,
  AppColorScheme colors, {
  double stroke = 1,
}) {
  switch (style) {
    case CuPaint.preamble:
      paintAirtimeBlock(
        canvas,
        rect,
        AirtimeBlockStyle.preamble,
        colors,
        stroke: stroke,
      );
    case CuPaint.data:
      paintAirtimeBlock(
        canvas,
        rect,
        AirtimeBlockStyle.data,
        colors,
        stroke: stroke,
      );
    case CuPaint.ack:
      paintAirtimeBlock(
        canvas,
        rect,
        AirtimeBlockStyle.control,
        colors,
        stroke: stroke,
      );
    case CuPaint.gap:
      paintAirtimeBlock(
        canvas,
        rect,
        AirtimeBlockStyle.gap,
        colors,
        stroke: stroke,
      );
    case CuPaint.wait:
      paintAirtimeBlock(
        canvas,
        rect,
        AirtimeBlockStyle.wait,
        colors,
        stroke: stroke,
      );
    case CuPaint.neighbor:
      final Color hue = cuNeighborHue(colors);
      canvas.drawRect(rect, Paint()..color = hue.withValues(alpha: 0.35));
      _stripes(canvas, rect, hue, stroke);
      _outline(canvas, rect, hue, stroke);
    case CuPaint.collision:
      canvas.drawRect(rect, Paint()..color = colors.statusDangerFill);
      _cross(canvas, rect, colors.statusDanger, stroke);
      _outline(canvas, rect, colors.statusDanger, stroke);
    case CuPaint.nonWifi:
      final Color hue = cuNonWifiHue(colors);
      canvas.drawRect(rect, Paint()..color = hue.withValues(alpha: 0.25));
      _zigzag(canvas, rect, hue, stroke);
      _outline(canvas, rect, hue, stroke);
    case CuPaint.spare:
      _outline(canvas, rect, colors.border, stroke);
  }
}

void _outline(Canvas canvas, Rect rect, Color color, double w) {
  canvas.drawRect(
    rect.deflate(w / 2),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = color,
  );
}

void _stripes(Canvas canvas, Rect rect, Color color, double w) {
  canvas.save();
  canvas.clipRect(rect);
  final Paint p = Paint()
    ..color = color
    ..strokeWidth = w;
  final double step = 4 * w;
  for (double x = rect.left + step / 2; x < rect.right; x += step) {
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), p);
  }
  canvas.restore();
}

void _cross(Canvas canvas, Rect rect, Color color, double w) {
  canvas.save();
  canvas.clipRect(rect);
  final Paint p = Paint()
    ..color = color
    ..strokeWidth = w;
  final double step = 7 * w;
  for (double x = rect.left - rect.height; x < rect.right; x += step) {
    canvas.drawLine(
      Offset(x, rect.bottom),
      Offset(x + rect.height, rect.top),
      p,
    );
    canvas.drawLine(
      Offset(x, rect.top),
      Offset(x + rect.height, rect.bottom),
      p,
    );
  }
  canvas.restore();
}

void _zigzag(Canvas canvas, Rect rect, Color color, double w) {
  canvas.save();
  canvas.clipRect(rect);
  final Paint p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5 * w;
  final double step = 5 * w;
  final double amp = math.min(rect.height * 0.3, 5 * w);
  final double mid = rect.center.dy;
  final Path path = Path()..moveTo(rect.left, mid);
  bool up = true;
  for (double x = rect.left + step; x < rect.right + step; x += step) {
    path.lineTo(x, up ? mid - amp : mid + amp);
    up = !up;
  }
  canvas.drawPath(path, p);
  canvas.restore();
}

// ── Stage ───────────────────────────────────────────────────────────────────

class ChannelUtilizationStage extends StatelessWidget {
  const ChannelUtilizationStage({super.key, required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget strip = _StripCard(
          controller: controller,
          fill: presenting,
        );
        final Widget window = _WindowCard(
          controller: controller,
          fill: presenting,
        );
        final Widget split = _SplitCard(controller: controller);
        final Widget beacon = CuBeaconCard(controller: controller);
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: headline),
                  CuTransport(controller: controller, compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: strip),
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: window),
              const SizedBox(height: AppSpacing.xs),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: split),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(flex: 2, child: beacon),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            headline,
            const SizedBox(height: AppSpacing.sm),
            strip,
            const SizedBox(height: AppSpacing.sm),
            window,
            const SizedBox(height: AppSpacing.sm),
            split,
            const SizedBox(height: AppSpacing.sm),
            beacon,
          ],
        );
      },
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final CuReading? r = controller.reading;
    final CuConfig c = controller.config;
    final bool masked = controller.masked;
    final String hidden = 'hidden until Reveal';

    final String meterValue = masked ? '?' : (r == null ? '…' : cuPct(r.share));
    final String meterNote = masked
        ? hidden
        : r == null
        ? 'collecting the first beacon interval'
        : '${r.byte} of 255${r.filling ? ', window filling' : ''}';
    final double? spare = r == null
        ? null
        : cuSplitShares(
            r,
            countReserved: controller.countReserved,
          )[CuSplit.spare];

    final List<Widget> tiles = <Widget>[
      CuHeadlineTile(
        label: 'Channel utilization',
        value: meterValue,
        note: meterNote,
        semantics: masked
            ? 'Channel utilization hidden until Reveal'
            : r == null
            ? 'Channel utilization: collecting the first beacon interval'
            : 'Channel utilization ${cuPct(r.share)}, ${r.byte} of 255',
      ),
      CuHeadlineTile(
        label: 'Station count',
        value: '${c.stationCount}',
        note: 'associated, ${c.senders} sending',
        semantics:
            'Station count ${c.stationCount} associated, ${c.senders} '
            'sending',
      ),
      CuHeadlineTile(
        label: 'Truly spare',
        value: masked ? '?' : (spare == null ? '…' : cuPct(spare)),
        note: masked ? hidden : 'idle with nobody waiting',
        semantics: masked
            ? 'Truly spare hidden until Reveal'
            : spare == null
            ? 'Truly spare: collecting'
            : 'Truly spare ${cuPct(spare)} of the window',
      ),
    ];
    if (PresenterMode.isActive(context)) {
      // One row, never wrapping, so the strip and the window keep the
      // height below it.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < tiles.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Flexible(child: tiles[i]),
          ],
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: tiles,
    );
  }
}

class CuHeadlineTile extends StatelessWidget {
  const CuHeadlineTile({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.semantics,
  });

  final String label;
  final String value;
  final String note;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: scale.headlineStyle(
              mono.outputLarge.copyWith(color: colors.textAccent),
            ),
          ),
          Text(
            note,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── The channel right now ───────────────────────────────────────────────────

class _StripCard extends StatelessWidget {
  const _StripCard({required this.controller, required this.fill});

  final ChannelUtilizationController controller;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final double spanMs = controller.stripTenths / 10000;
    final Widget paint = Semantics(
      label:
          'The last ${spanMs.toStringAsFixed(1)} ms of channel time, newest '
          'on the right: this network\'s frames and ACKs, the required '
          'waits between them, and any other network, collision or '
          'non-Wi-Fi energy.',
      excludeSemantics: true,
      child: CustomPaint(
        painter: CuStripPainter(
          controller: controller,
          colors: colors,
          scale: scale,
          labelStyle: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        child: const SizedBox.expand(),
      ),
    );
    final CuConfig c = controller.config;
    final List<CuPaint> keys = <CuPaint>[
      CuPaint.preamble,
      CuPaint.data,
      CuPaint.gap,
      CuPaint.ack,
      CuPaint.wait,
      if (c.senders > 1 || c.neighbor) CuPaint.collision,
      if (c.neighbor) CuPaint.neighbor,
      CuPaint.nonWifi,
    ];
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          AirtimeSectionTitle(
            'The channel right now: the last ${spanMs.toStringAsFixed(1)} ms',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill)
            Expanded(child: paint)
          else
            SizedBox(height: AppSpacing.xxl, child: paint),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[for (final CuPaint k in keys) CuKey(k)],
          ),
        ],
      ),
    );
  }
}

/// One legend entry: a swatch in the block's style and its name.
class CuKey extends StatelessWidget {
  const CuKey(this.style, {super.key, this.text});

  final CuPaint style;

  /// Overrides the style's label.
  final String? text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme tt = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: AppSpacing.md,
            height: AppSpacing.sm,
            child: CustomPaint(
              painter: _SwatchPainter(style: style, colors: colors),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            text ?? style.label,
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({required this.style, required this.colors});

  final CuPaint style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) =>
      paintCuBlock(canvas, Offset.zero & size, style, colors);

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.style != style || old.colors != colors;
}

/// The strip: [ChannelUtilizationController.stripTenths] of channel time up
/// to now, newest on the right. Repaints on every frame of a running channel.
class CuStripPainter extends CustomPainter {
  CuStripPainter({
    required this.controller,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  }) : super(repaint: controller.frame);

  final ChannelUtilizationController controller;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = (labelStyle ?? const TextStyle()).copyWith(
      fontSize: scale.paintFont(labelStyle?.fontSize ?? 12),
    );
    final double axisH = style.fontSize! * 1.6;
    final Rect lane = Rect.fromLTRB(0, 0, size.width, size.height - axisH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane, const Radius.circular(AppRadius.control)),
      Paint()..color = colors.inputFill,
    );
    final CuSim sim = controller.sim;
    final int span = controller.stripTenths;
    final int end = sim.nowTenths;
    final int start = end - span;
    final double px = lane.width / span;
    final double top = lane.top + lane.height * 0.12;
    final double bottom = lane.bottom - lane.height * 0.12;
    final int preamble = sim.timing.preambleTenths;

    double x(int t) => (t - start) * px;

    for (final CuBlock b in sim.blocks) {
      if (b.endTenths <= start) continue;
      final double l = math.max(0, x(b.startTenths));
      final double r = math.min(lane.width, x(b.endTenths));
      if (r - l <= 0) continue;
      final Rect rect = Rect.fromLTRB(l, top, math.max(r, l + 1), bottom);
      final double stroke = rect.width < 3 ? 0.5 : scale.stroke;
      String? label;
      switch (b.kind) {
        case CuBlockKind.data:
          final double split = math.min(r, x(b.startTenths + preamble));
          if (split > l) {
            paintCuBlock(
              canvas,
              Rect.fromLTRB(l, top, split, bottom),
              CuPaint.preamble,
              colors,
              stroke: stroke,
            );
          }
          if (r > split) {
            paintCuBlock(
              canvas,
              Rect.fromLTRB(math.max(l, split), top, r, bottom),
              CuPaint.data,
              colors,
              stroke: stroke,
            );
          }
          label = 'Data';
        case CuBlockKind.ack:
          paintCuBlock(canvas, rect, CuPaint.ack, colors, stroke: stroke);
          label = 'ACK';
        case CuBlockKind.gap:
        case CuBlockKind.neighborGap:
          paintCuBlock(canvas, rect, CuPaint.gap, colors, stroke: stroke);
        case CuBlockKind.collision:
          paintCuBlock(canvas, rect, CuPaint.collision, colors, stroke: stroke);
          label = 'Collision';
        case CuBlockKind.neighborData:
        case CuBlockKind.neighborAck:
          paintCuBlock(canvas, rect, CuPaint.neighbor, colors, stroke: stroke);
          label = b.kind == CuBlockKind.neighborData ? 'Other network' : null;
        case CuBlockKind.nonWifi:
          paintCuBlock(canvas, rect, CuPaint.nonWifi, colors, stroke: stroke);
          label = 'Non-Wi-Fi';
        case CuBlockKind.wait:
          paintCuBlock(canvas, rect, CuPaint.wait, colors, stroke: stroke);
      }
      if (label != null) {
        _label(canvas, rect, label, style);
      }
    }

    // Axis: "-x ms" on the left, "now" on the right.
    final TextStyle axis = style.copyWith(color: colors.textTertiary);
    final TextPainter left = TextPainter(
      text: TextSpan(
        text: '−${(span / 10000).toStringAsFixed(1)} ms',
        style: axis,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    left.paint(canvas, Offset(0, lane.bottom + axisH * 0.15));
    final TextPainter right = TextPainter(
      text: TextSpan(text: 'now', style: axis),
      textDirection: TextDirection.ltr,
    )..layout();
    right.paint(
      canvas,
      Offset(size.width - right.width, lane.bottom + axisH * 0.15),
    );
  }

  void _label(Canvas canvas, Rect rect, String label, TextStyle style) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          backgroundColor: colors.surface1.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width + 4 > rect.width || tp.height > rect.height) return;
    tp.paint(canvas, Offset(rect.left + 2, rect.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(CuStripPainter old) =>
      old.controller != controller ||
      old.colors != colors ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}

// ── The averaging window ────────────────────────────────────────────────────

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.controller, required this.fill});

  final ChannelUtilizationController controller;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final CuReading? r = controller.reading;
    final bool masked = controller.masked;
    final int n = controller.window;
    final String seconds = controller.windowSeconds.toStringAsFixed(2);

    final String status = masked
        ? 'The meter\'s value is hidden until Reveal.'
        : r == null
        ? 'Collecting the first beacon interval (102.4 ms).'
        : r.filling
        ? 'Window filling: ${r.intervalsUsed} of $n intervals so far. '
              'The AP reports ${r.byte} of 255 = ${cuPct(r.share)}.'
        : 'The AP reports ${r.byte} of 255 = ${cuPct(r.share)}, the '
              'average over the bracket.';

    final Widget paint = Semantics(
      label: masked
          ? 'Busy share of each beacon interval, hidden until Reveal'
          : 'Busy share of each beacon interval, newest on the right; the '
                'bracket spans the last $n intervals, $seconds seconds. '
                '$status',
      excludeSemantics: true,
      child: CustomPaint(
        painter: CuWindowPainter(
          intervals: controller.sim.intervals,
          current: controller.sim.currentInterval,
          currentProgress: controller.sim.currentIntervalProgress,
          window: n,
          countReserved: controller.countReserved,
          average: masked ? null : r?.share,
          masked: masked,
          colors: colors,
          scale: scale,
          labelStyle: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
        child: const SizedBox.expand(),
      ),
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('What the AP averages'),
          Text(
            fill
                ? 'Bars: beacon intervals (100 TU, time units of 1024 µs). '
                      'Bracket: the window, $seconds s.'
                : 'Each bar is one beacon interval (100 TU, time units of '
                      '1024 µs: 102.4 ms). The bracket is the window, $n '
                      'intervals = $seconds s, sliding right as time passes.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill)
            Expanded(child: paint)
          else
            SizedBox(height: AppSpacing.xxl * 1.5, child: paint),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            status,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Busy share per beacon interval, newest on the right, with the window's
/// bracket over the last N completed intervals and the average as a line.
class CuWindowPainter extends CustomPainter {
  CuWindowPainter({
    required this.intervals,
    required this.current,
    required this.currentProgress,
    required this.window,
    required this.countReserved,
    required this.average,
    required this.masked,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  });

  final List<CuTotals> intervals;
  final CuTotals current;
  final double currentProgress;
  final int window;
  final bool countReserved;

  /// The meter (byte / 255), or null while hidden or empty.
  final double? average;
  final bool masked;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle? labelStyle;

  /// Bars drawn: the window plus some history either side, at least 40.
  int get slots => math.min(kCuHistoryIntervals, math.max(40, window + 12)) + 1;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = (labelStyle ?? const TextStyle()).copyWith(
      fontSize: scale.paintFont(labelStyle?.fontSize ?? 12),
    );
    final double bracketH = style.fontSize! * 1.8;
    final Rect plot = Rect.fromLTRB(0, bracketH, size.width, size.height);
    canvas.drawRect(plot, Paint()..color = colors.inputFill);

    final int n = slots;
    final double w = plot.width / n;
    final double gap = w > 4 ? 1 : 0;

    // Completed intervals fill slots 0 .. n-2 from the right; the interval
    // in progress is the last slot.
    final int shown = math.min(intervals.length, n - 1);
    final Paint bar = Paint()..color = colors.primary;
    for (int k = 0; k < shown; k++) {
      final CuTotals t = intervals[intervals.length - shown + k];
      final int slot = n - 1 - shown + k;
      final double share = masked
          ? 0
          : t.busyTenths(countReserved: countReserved) / kCuIntervalTenths;
      final double left = plot.left + slot * w;
      final double h = plot.height * share.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(left, plot.bottom - h, left + w - gap, plot.bottom),
        bar,
      );
    }
    // In progress: outlined, height = busy so far over the interval's time
    // so far.
    final double sofar = current.totalTenths.toDouble();
    if (!masked && sofar > 0) {
      final double share =
          current.busyTenths(countReserved: countReserved) / sofar;
      final double left = plot.left + (n - 1) * w;
      final double h = plot.height * share.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(
          left,
          plot.bottom - h,
          left + w - gap,
          plot.bottom,
        ).deflate(scale.stroke / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale.strokeWidth(1)
          ..color = colors.textSecondary,
      );
    }
    // Progress tick along the bottom of the in-progress slot.
    final double pLeft = plot.left + (n - 1) * w;
    canvas.drawLine(
      Offset(pLeft, plot.bottom - 1),
      Offset(
        pLeft + (w - gap) * currentProgress.clamp(0.0, 1.0),
        plot.bottom - 1,
      ),
      Paint()
        ..color = colors.textPrimary
        ..strokeWidth = scale.strokeWidth(2),
    );

    // 100% line.
    final Paint dashed = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = scale.strokeWidth(1);
    for (double x = plot.left; x < plot.right; x += 8) {
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(math.min(x + 4, plot.right), plot.top),
        dashed,
      );
    }
    final TextPainter hundred = TextPainter(
      text: TextSpan(
        text: '100%',
        style: style.copyWith(backgroundColor: colors.inputFill),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hundred.paint(canvas, Offset(plot.left + 2, plot.top + 2));

    // Bracket over the last N completed intervals (or as many as exist).
    final int used = math.min(window, intervals.length);
    final int bracketSlots = math.max(used, 1);
    final double bRight = plot.left + (n - 1) * w;
    final double bLeft = bRight - math.min(bracketSlots, n - 1) * w;
    final Paint bp = Paint()
      ..color = colors.textPrimary
      ..strokeWidth = scale.strokeWidth(1.5)
      ..style = PaintingStyle.stroke;
    final double by = bracketH * 0.75;
    canvas.drawPath(
      Path()
        ..moveTo(bLeft, plot.top)
        ..lineTo(bLeft, by)
        ..lineTo(bRight, by)
        ..lineTo(bRight, plot.top),
      bp,
    );
    final String bLabel = used < window
        ? 'window: $used of $window intervals'
        : 'window: $window interval${window == 1 ? '' : 's'}';
    final TextPainter bl = TextPainter(
      text: TextSpan(
        text: bLabel,
        style: style.copyWith(color: colors.textPrimary),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, size.width));
    double lx = (bLeft + bRight) / 2 - bl.width / 2;
    lx = lx.clamp(0, math.max(0, size.width - bl.width));
    bl.paint(canvas, Offset(lx, 0));

    // The average as a line across the bracket.
    final double? avg = average;
    if (avg != null && used > 0) {
      final double y = plot.bottom - plot.height * avg.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(bLeft, y),
        Offset(bRight, y),
        Paint()
          ..color = colors.textPrimary
          ..strokeWidth = scale.strokeWidth(2.5),
      );
      final TextPainter al = TextPainter(
        text: TextSpan(
          text: 'meter ${cuPct(avg)}',
          style: style.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            backgroundColor: colors.surface1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double ax = bLeft + 4;
      if (bRight - bLeft < al.width + 8) ax = math.max(0, bRight - al.width);
      final double ay = (y - al.height - 2).clamp(
        plot.top,
        math.max(plot.top, plot.bottom - al.height),
      );
      al.paint(canvas, Offset(ax, ay));
    }
  }

  @override
  bool shouldRepaint(CuWindowPainter old) => true;
}

// ── Split bar ───────────────────────────────────────────────────────────────

/// The block style each split segment is drawn with.
CuPaint cuSplitPaint(CuSplit s) => switch (s) {
  CuSplit.payload => CuPaint.data,
  CuSplit.overhead => CuPaint.preamble,
  CuSplit.collision => CuPaint.collision,
  CuSplit.neighbor => CuPaint.neighbor,
  CuSplit.nonWifi => CuPaint.nonWifi,
  CuSplit.requiredIdle => CuPaint.wait,
  CuSplit.spare => CuPaint.spare,
};

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final CuReading? r = controller.reading;
    final bool masked = controller.masked;
    final Map<CuSplit, double>? shares = r == null || masked
        ? null
        : cuSplitShares(r, countReserved: controller.countReserved);
    final double busy = shares == null
        ? 0
        : CuSplit.values
              .where((CuSplit s) => s.busy)
              .fold<double>(0, (double a, CuSplit s) => a + shares[s]!);

    final String semantics = shares == null
        ? (masked
              ? 'Where the time went: hidden until Reveal'
              : 'Where the time went: collecting')
        : 'Where the time went: ${CuSplit.values.map((CuSplit s) => '${s.label} ${cuPct(shares[s]!)}').join(', ')}';

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('Where the window\'s time went'),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: semantics,
            excludeSemantics: true,
            child: SizedBox(
              height: AppSpacing.lg * scale.text,
              child: CustomPaint(
                painter: CuSplitPainter(
                  shares: shares,
                  colors: colors,
                  scale: scale,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (shares != null)
            Text(
              'Busy (what the meter counts): ${cuPct(busy)}. Payload, the '
              'part that is your data: ${cuPct(shares[CuSplit.payload]!)}. '
              'Truly spare: ${cuPct(shares[CuSplit.spare]!)}.',
              style: text.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              for (final CuSplit s in CuSplit.values)
                if (shares == null || shares[s]! > 0 || _always(s))
                  CuKey(
                    cuSplitPaint(s),
                    text: shares == null
                        ? s.label
                        : '${s.label} ${cuPct(shares[s]!)}',
                  ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _always(CuSplit s) =>
      s == CuSplit.payload ||
      s == CuSplit.overhead ||
      s == CuSplit.requiredIdle ||
      s == CuSplit.spare;
}

/// The stacked split bar, left to right in [CuSplit] order.
class CuSplitPainter extends CustomPainter {
  CuSplitPainter({
    required this.shares,
    required this.colors,
    required this.scale,
  });

  /// Null while hidden or empty: an empty outline.
  final Map<CuSplit, double>? shares;
  final AppColorScheme colors;
  final PresenterScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = colors.inputFill);
    final Map<CuSplit, double>? s = shares;
    if (s != null) {
      double x = 0;
      for (final CuSplit k in CuSplit.values) {
        final double w = s[k]! * size.width;
        if (w > 0) {
          paintCuBlock(
            canvas,
            Rect.fromLTWH(x, 0, w, size.height),
            cuSplitPaint(k),
            colors,
            stroke: w < 3 ? 0.5 : scale.stroke,
          );
        }
        x += w;
      }
    }
    _outline(canvas, all, colors.borderStrong, scale.stroke);
  }

  @override
  bool shouldRepaint(CuSplitPainter old) =>
      !mapEquals(old.shares, shares) ||
      old.colors != colors ||
      old.scale != scale;
}

// ── Beacon inspector ────────────────────────────────────────────────────────

/// The BSS Load element as the next beacon carries it.
class CuBeaconCard extends StatelessWidget {
  const CuBeaconCard({super.key, required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final CuReading? r = controller.reading;
    final bool masked = controller.masked;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    TableRow row(String name, String v) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(v, textAlign: TextAlign.end, style: value),
        ),
      ],
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('BSS Load element, in every beacon'),
          Text('BSS: basic service set, one AP\'s network.', style: note),
          const SizedBox(height: AppSpacing.xxs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
            },
            children: <TableRow>[
              row('Station Count', '${controller.config.stationCount}'),
              row(
                'Channel Utilization',
                masked
                    ? '?'
                    : (r == null ? '…' : '${r.byte} (${cuPct(r.share)})'),
              ),
              row('Available Admission Capacity', 'not in use'),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            PresenterMode.isActive(context)
                ? 'Most networks run no admission control.'
                : 'Admission capacity only means something under explicit '
                      'admission control, which most networks do not run.',
            style: note,
          ),
        ],
      ),
    );
  }
}
