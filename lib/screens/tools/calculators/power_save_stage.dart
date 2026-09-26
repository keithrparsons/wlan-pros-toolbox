// PowerSaveStage: the pictures half of Power Save.
//
// A timeline window over the run: the beacons (DTIM beacons taller), and for
// each mode on screen (the chosen one, and the comparison if any) the
// frames the AP is holding for the client, the TIM bit at each beacon, and
// the client's radio: doze as a thin line, awake as a bar colored by what
// it is doing. Takes the shared PowerSaveController and nothing else, so a
// phone layout can stack it with PowerSaveControls and a presenter layout
// can put the two side by side.
//
// COLOR: the awake states take the four PsPalette hues (GL-003 §8.15.2),
// each named in the legend; the AP's buffer and the beacons are the neutral
// stack. No status hue on the stage: nothing drawn here is a verdict.
//
// DRAWING HONESTY: a 1.5 ms wake is under a pixel at most widths, so every
// awake span is drawn at least 2 px wide, and the card says so. The
// readouts carry the true awake share.
//
// PRESENTER (PresenterMode.isActive): the same card fills the bounded stage
// box with no scroll, under a headline per mode with the numbers the lesson
// is about (time awake at the headline scale, the battery estimate, the
// average current and the worst downlink wait), moved here from the
// readouts. The timeline's rows, labels and strokes grow with the presenter
// scale (its painter lays out its own text).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/power_save_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'power_save_controller.dart';
import 'power_save_parts.dart';

class PowerSaveStage extends StatelessWidget {
  const PowerSaveStage({super.key, required this.controller});

  final PowerSaveController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final PowerSaveController c = controller;
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        final AppMonoText mono =
            Theme.of(context).extension<AppMonoText>() ??
            AppMonoText.defaults();
        final PresenterScale scale = PresenterMode.scaleOf(context);
        final bool presenting = PresenterMode.isActive(context);
        final PsConfig cfg = c.config;
        TextStyle painted(TextStyle st) => st.fontSize == null
            ? st
            : st.copyWith(fontSize: scale.paintFont(st.fontSize!));
        final PsTimelineStyle style = PsTimelineStyle(
          text: colors.textPrimary,
          secondary: colors.textSecondary,
          grid: colors.border,
          doze: colors.textTertiary,
          held: colors.textSecondary,
          listen: PsPalette.of(AwakeKind.listen, colors),
          frames: PsPalette.of(AwakeKind.frames, colors),
          send: PsPalette.of(AwakeKind.send, colors),
          twtSp: PsPalette.of(AwakeKind.twtSp, colors),
          tint: colors.isLight ? 0.16 : 0.22,
          labelStyle: mono.inlineCode.copyWith(
            fontSize: scale.paintFont(AppTextSize.caption - 2),
            color: colors.textSecondary,
          ),
          rowLabelStyle: painted(
            text.bodySmall?.copyWith(color: colors.textSecondary) ??
                TextStyle(color: colors.textSecondary),
          ),
          titleStyle: painted(
            text.bodySmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ) ??
                TextStyle(color: colors.textPrimary),
          ),
        );
        final List<PsRun> runs = c.runs;
        final double dtimMs = tuToMs(cfg.beaconTu * cfg.dtimPeriod);
        final Widget card = PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PsSectionLabel(
                runs.length == 1
                    ? 'Timeline: ${runs.first.mode.short}'
                    : 'Timeline: ${runs[0].mode.short} vs ${runs[1].mode.short}',
              ),
              const SizedBox(height: AppSpacing.xxs),
              PsHint(
                'A beacon every ${cfg.beaconTu} TU '
                '(${tuToMs(cfg.beaconTu).toStringAsFixed(1)} ms); '
                '${cfg.dtimPeriod == 1 ? 'every beacon is a DTIM' : 'a DTIM every ${_ordinal(cfg.dtimPeriod)} beacon (${dtimMs.toStringAsFixed(1)} ms)'}. '
                '1 TU = 1024 µs.',
              ),
              const SizedBox(height: AppSpacing.xs),
              AppToggle<PsView>(
                value: c.view,
                semanticLabel: 'Timeline span',
                expand: true,
                items: <AppToggleItem<PsView>>[
                  for (final PsView v in PsView.values) (v, v.label),
                ],
                onChanged: (PsView v) => c.view = v,
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                label: _summary(c),
                excludeSemantics: true,
                child: SizedBox(
                  height: PsTimelinePainter.heightFor(runs.length, scale),
                  child: CustomPaint(
                    painter: PsTimelinePainter(
                      runs: runs,
                      w0: c.startUs,
                      w1: c.endUs,
                      style: style,
                      scale: scale,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PsSlider(
                label: 'Window start, run ${(cfg.horizonUs / 1e6).round()} s',
                valueText: fmtUs(c.startUs),
                value: c.startUs,
                min: 0,
                max: math.max(c.maxStartUs, 1),
                divisions: math.max(
                  1,
                  (c.maxStartUs / (c.view.spanUs / 4)).round(),
                ),
                onChanged: c.maxStartUs <= 0 ? (_) {} : c.seek,
                semanticValue: (double v) =>
                    '${fmtUs(v)} of ${fmtUs(cfg.horizonUs.toDouble())}',
              ),
              const SizedBox(height: AppSpacing.xxs),
              _Legend(style: style),
              const SizedBox(height: AppSpacing.xs),
              const PsHint(
                'Wakes of a millisecond or two are drawn at least 2 px wide '
                'so you can see them; when there are too many for that, as '
                'thin ticks. The title of each mode gives the true count and '
                'share of time awake in the window.',
              ),
            ],
          ),
        );
        if (!presenting) return card;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PsCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < runs.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    Expanded(child: _Headline(run: runs[i])),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: LayoutBuilder(
                // Full size when it fits; otherwise the card scales down as
                // one piece, never a scroll.
                builder: (BuildContext context, BoxConstraints box) =>
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(width: box.maxWidth, child: card),
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _ordinal(int n) => switch (n) {
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };

  static String _summary(PowerSaveController c) {
    final double w0 = c.startUs;
    final double w1 = c.endUs;
    final StringBuffer b = StringBuffer(
      'Timeline from ${fmtUs(w0)} to ${fmtUs(w1)}. ',
    );
    final PsRun first = c.run;
    final int beacons = first.beacons
        .where((BeaconMark m) => m.tUs >= w0 && m.tUs < w1)
        .length;
    final int dtims = first.beacons
        .where((BeaconMark m) => m.dtim && m.tUs >= w0 && m.tUs < w1)
        .length;
    b.write('$beacons beacons, $dtims of them DTIM. ');
    for (final PsRun r in c.runs) {
      final double awake = r.awakeUsBetween(w0, w1);
      final int heard = r.beacons
          .where((BeaconMark m) => m.listened && m.tUs >= w0 && m.tUs < w1)
          .length;
      final int delivered = r.frames
          .where(
            (FrameRecord f) =>
                f.kind == FrameKind.downlink &&
                f.doneUs != null &&
                f.doneUs! >= w0 &&
                f.doneUs! < w1,
          )
          .length;
      b.write(
        '${r.mode.short}: ${r.wakesBetween(w0, w1)} wakes, awake '
        '${fmtPct(awake / (w1 - w0))} of this window, woke for $heard '
        'beacons, $delivered downlink frames delivered. ',
      );
    }
    return b.toString().trimRight();
  }
}

/// One mode's lesson numbers over the whole run: time awake, large, and
/// what it buys (battery) and costs (the worst downlink wait).
class _Headline extends StatelessWidget {
  const _Headline({required this.run});

  final PsRun run;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final PsRun r = run;
    final LatencyStats dl = r.downlink;
    final String wait = dl.count == 0
        ? 'no downlink'
        : 'downlink waits up to ${fmtUs(dl.worstUs!)}';
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${r.mode.label}: time awake',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            fmtPct(r.awakeFraction),
            style: scale
                .headlineStyle(mono.outputLarge)
                .copyWith(color: colors.textAccent),
          ),
          Text(
            'Battery ${fmtLife(r.batteryLifeHours)}, '
            '${fmtCurrent(r.averageMa)} average',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          Text(
            wait,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (r.groupMissed > 0)
            Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: AppSpacing.md,
                  color: colors.statusWarning,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    '${r.groupMissed} group frames missed',
                    style: text.bodySmall?.copyWith(
                      color: colors.statusWarning,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.style});

  final PsTimelineStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final AwakeKind k in AwakeKind.values)
            PsSwatch(label: PsPalette.label(k), color: PsPalette.of(k, colors)),
          PsSwatch(
            label: 'Doze',
            child: Center(child: Container(height: 1.5, color: style.doze)),
          ),
          PsSwatch(
            label: 'Frames held at the AP',
            color: style.held.withValues(alpha: 0.35),
          ),
          PsSwatch(
            label: 'TIM bit set',
            child: Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: style.text,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          PsSwatch(
            label: 'Beacon / DTIM (tall)',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Container(width: 1.5, height: 6, color: style.secondary),
                Container(width: 2, height: 12, color: style.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class PsTimelineStyle {
  const PsTimelineStyle({
    required this.text,
    required this.secondary,
    required this.grid,
    required this.doze,
    required this.held,
    required this.listen,
    required this.frames,
    required this.send,
    required this.twtSp,
    required this.tint,
    required this.labelStyle,
    required this.rowLabelStyle,
    required this.titleStyle,
  });

  final Color text;
  final Color secondary;
  final Color grid;
  final Color doze;
  final Color held;
  final Color listen;
  final Color frames;
  final Color send;
  final Color twtSp;
  final double tint;
  final TextStyle labelStyle;
  final TextStyle rowLabelStyle;
  final TextStyle titleStyle;

  Color of(AwakeKind k) => switch (k) {
    AwakeKind.listen => listen,
    AwakeKind.frames => frames,
    AwakeKind.send => send,
    AwakeKind.twtSp => twtSp,
  };

  @override
  bool operator ==(Object other) =>
      other is PsTimelineStyle &&
      other.text == text &&
      other.grid == grid &&
      other.listen == listen &&
      other.frames == frames &&
      other.tint == tint &&
      other.labelStyle == labelStyle;

  @override
  int get hashCode => Object.hash(text, grid, listen, frames, tint, labelStyle);
}

/// Beacons on top; per run a title, the AP's buffer, and the client.
class PsTimelinePainter extends CustomPainter {
  PsTimelinePainter({
    required this.runs,
    required this.w0,
    required this.w1,
    required this.style,
    this.scale = PresenterScale.normal,
  });

  final List<PsRun> runs;
  final double w0;
  final double w1;
  final PsTimelineStyle style;

  /// Presenter scale. This painter lays out its own labels, which
  /// MediaQuery's text scale does not reach, so its rows grow with the text
  /// factor and its strokes with the stroke factor. Identity elsewhere.
  final PresenterScale scale;

  static const double _labelWBase = 64;
  static const double _beaconHBase = 22;
  static const double _titleHBase = 18;
  static const double _heldHBase = 32;
  static const double _clientHBase = 22;
  static const double _gapBase = 8;
  static const double _axisHBase = 18;

  double get _k => scale.text;
  double get _labelW => _labelWBase * _k;
  double get _beaconH => _beaconHBase * _k;
  double get _titleH => _titleHBase * _k;
  double get _heldH => _heldHBase * _k;
  double get _clientH => _clientHBase * _k;
  double get _gap => _gapBase * _k;
  double get _axisH => _axisHBase * _k;

  static double heightFor(
    int runs, [
    PresenterScale scale = PresenterScale.normal,
  ]) =>
      (_beaconHBase +
          runs * (_titleHBase + _heldHBase + _clientHBase + _gapBase) +
          _axisHBase) *
      scale.text;

  @override
  void paint(Canvas canvas, Size size) {
    if (runs.isEmpty) return;
    final double left = _labelW;
    final double right = size.width - 4;
    final double span = w1 - w0;
    double x(double t) => left + (t - w0) / span * (right - left);
    final double plotBottom = size.height - _axisH;
    final Paint gridP = Paint()
      ..color = style.grid
      ..strokeWidth = scale.strokeWidth(1);

    // Time grid and axis labels. A label that would touch the one before
    // it is skipped (the grid line stays).
    final double tick = span <= 400000
        ? 50000
        : span <= 1100000
        ? 200000
        : span <= 11000000
        ? 2000000
        : 10000000;
    double lastRight = double.negativeInfinity;
    for (double t = (w0 / tick).ceil() * tick; t <= w1 + 1e-6; t += tick) {
      final double gx = x(t);
      canvas.drawLine(Offset(gx, 0), Offset(gx, plotBottom), gridP);
      final String label = tick < 1000000
          ? '${(t / 1000).round()} ms'
          : '${(t / 1000000).round()} s';
      final TextPainter tp = _layout(label, style.labelStyle);
      final double lx = (gx - tp.width / 2).clamp(left, right - tp.width);
      if (lx < lastRight + 6) continue;
      tp.paint(canvas, Offset(lx, plotBottom + 3));
      lastRight = lx + tp.width;
    }

    // Beacons, from the first run (every mode has the same beacons).
    _rowLabel(canvas, 'Beacons', 0, _beaconH);
    final List<BeaconMark> beacons = runs.first.beacons;
    final double pxPerBeacon = beacons.length < 2
        ? double.infinity
        : (x(beacons[1].tUs) - x(beacons[0].tUs));
    final int dtimEvery = runs.first.config.dtimPeriod;
    // Too dense to draw one by one: say so instead of painting a solid bar.
    final bool beaconsDense = pxPerBeacon * dtimEvery < 4;
    if (beaconsDense) {
      _text(
        canvas,
        'too dense to draw: zoom in',
        style.labelStyle,
        Offset(left + 2, _beaconH / 2),
        vCenter: true,
        maxWidth: right - left - 2,
      );
    }
    for (final BeaconMark b in beaconsDense ? const <BeaconMark>[] : beacons) {
      if (b.tUs < w0 || b.tUs > w1) continue;
      if (!b.dtim && pxPerBeacon < 3) continue;
      final double bx = x(b.tUs);
      final double h = b.dtim ? _beaconH - 4 * _k : (_beaconH - 4 * _k) / 2;
      canvas.drawLine(
        Offset(bx, _beaconH - 2 * _k - h),
        Offset(bx, _beaconH - 2 * _k),
        Paint()
          ..color = b.dtim ? style.text : style.secondary
          ..strokeWidth = scale.strokeWidth(b.dtim ? 2 : 1.5),
      );
    }

    double y = _beaconH;
    for (final PsRun r in runs) {
      // Title.
      final int wakes = r.wakesBetween(w0, w1);
      _text(
        canvas,
        '${r.mode.short}: $wakes wake${wakes == 1 ? '' : 's'}, awake '
        '${fmtPct(r.awakeUsBetween(w0, w1) / span)} here',
        style.titleStyle,
        Offset(0, y + _titleH / 2),
        vCenter: true,
        maxWidth: size.width,
      );
      y += _titleH;

      // The AP's buffer for this client: a step area, scaled to the peak in
      // the window.
      final int peak = _peak(r.queue);
      _rowLabel(canvas, 'AP holds', y, _heldH);
      final TextPainter peakTp = _layout(
        peak == 0 ? 'nothing held' : 'peak $peak',
        style.labelStyle,
      );
      peakTp.paint(canvas, Offset(right - peakTp.width, y));
      canvas.drawLine(
        Offset(left, y + _heldH),
        Offset(right, y + _heldH),
        gridP,
      );
      if (peak > 0) {
        final double top = y + peakTp.height + 1;
        final double base = y + _heldH - 1;
        double yd(int d) => base - d / peak * (base - top);
        final Path p = Path()..moveTo(left, base);
        int depth = _depthAt(r.queue, w0);
        p.lineTo(left, yd(depth));
        for (final QueueStep s in r.queue) {
          if (s.tUs <= w0) continue;
          if (s.tUs > w1) break;
          final double sx = x(s.tUs);
          p.lineTo(sx, yd(depth));
          depth = s.depth;
          p.lineTo(sx, yd(depth));
        }
        p
          ..lineTo(right, yd(depth))
          ..lineTo(right, base)
          ..close();
        canvas.drawPath(p, Paint()..color = style.held.withValues(alpha: 0.35));
      }
      // TIM dots.
      for (final BeaconMark b in r.beacons) {
        if (pxPerBeacon < 6) break;
        if (!b.tim || b.tUs < w0 || b.tUs > w1) continue;
        canvas.drawCircle(
          Offset(x(b.tUs), y + scale.markerSize(3.5)),
          scale.markerSize(3),
          Paint()..color = style.text,
        );
      }
      y += _heldH;

      // The client: doze line, then awake spans on top.
      _rowLabel(canvas, 'Client', y, _clientH);
      final double mid = y + _clientH / 2;
      canvas.drawLine(
        Offset(left, mid),
        Offset(right, mid),
        Paint()
          ..color = style.doze
          ..strokeWidth = scale.strokeWidth(1.5),
      );
      // With more wakes than room, a 2 px minimum would paint a solid bar
      // and look like "always awake". Then each wake is a 1 px tick at half
      // height, and the title line carries the count and the true share.
      final bool dense = wakes * 4 > right - left && r.mode != PsMode.awake;
      final List<AwakeSpan> visible = <AwakeSpan>[
        for (final AwakeSpan s in r.spans)
          if (s.endUs >= w0 && s.startUs <= w1) s,
      ];
      for (final AwakeKind k in <AwakeKind>[
        AwakeKind.twtSp,
        AwakeKind.listen,
        AwakeKind.frames,
        AwakeKind.send,
      ]) {
        for (final AwakeSpan s in visible) {
          if (s.kind != k) continue;
          double a = x(math.max(s.startUs, w0));
          double b = x(math.min(s.endUs, w1));
          final double minW = scale.strokeWidth(dense ? 1 : 2);
          if (b - a < minW) {
            final double c = (a + b) / 2;
            a = c - minW / 2;
            b = c + minW / 2;
          }
          final double inset = dense ? _clientH / 4 : 2 * _k;
          final Rect rect = Rect.fromLTRB(
            a,
            y + inset,
            b,
            y + _clientH - inset,
          );
          final Color col = style.of(k);
          if (k == AwakeKind.twtSp) {
            canvas.drawRect(
              rect,
              Paint()..color = col.withValues(alpha: style.tint),
            );
            canvas.drawRect(
              rect,
              Paint()
                ..color = col
                ..style = PaintingStyle.stroke
                ..strokeWidth = scale.strokeWidth(1.5),
            );
          } else {
            canvas.drawRect(rect, Paint()..color = col);
          }
        }
      }
      y += _clientH + _gap;
    }
  }

  int _peak(List<QueueStep> q) {
    int peak = _depthAt(q, w0);
    for (final QueueStep s in q) {
      if (s.tUs <= w0) continue;
      if (s.tUs > w1) break;
      if (s.depth > peak) peak = s.depth;
    }
    return peak;
  }

  static int _depthAt(List<QueueStep> q, double t) {
    int d = 0;
    for (final QueueStep s in q) {
      if (s.tUs > t) break;
      d = s.depth;
    }
    return d;
  }

  void _rowLabel(
    Canvas canvas,
    String label,
    double top,
    double h, {
    String? second,
  }) {
    if (second == null) {
      _text(
        canvas,
        label,
        style.rowLabelStyle,
        Offset(0, top + h / 2),
        vCenter: true,
        maxWidth: _labelW - 4,
      );
      return;
    }
    _text(
      canvas,
      label,
      style.rowLabelStyle,
      Offset(0, top + h / 2 - 7 * _k),
      vCenter: true,
      maxWidth: _labelW - 4,
    );
    _text(
      canvas,
      second,
      style.labelStyle,
      Offset(0, top + h / 2 + 7 * _k),
      vCenter: true,
      maxWidth: _labelW - 4,
    );
  }

  TextPainter _layout(String s, TextStyle st, {double? maxWidth}) =>
      TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '',
      )..layout(maxWidth: maxWidth ?? double.infinity);

  void _text(
    Canvas canvas,
    String s,
    TextStyle st,
    Offset at, {
    bool vCenter = false,
    double? maxWidth,
  }) {
    final TextPainter tp = _layout(s, st, maxWidth: maxWidth);
    final double dy = vCenter ? at.dy - tp.height / 2 : at.dy;
    tp.paint(canvas, Offset(at.dx, dy));
  }

  @override
  bool shouldRepaint(PsTimelinePainter old) =>
      !identical(old.runs.first, runs.first) ||
      old.runs.length != runs.length ||
      (runs.length > 1 && !identical(old.runs[1], runs[1])) ||
      old.w0 != w0 ||
      old.w1 != w1 ||
      old.style != style ||
      old.scale != scale;
}
