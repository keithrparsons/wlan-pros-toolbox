// MloSimulatorStage: the pictures half of Multi-Link Operation.
//
// Two cards over one MloSimulatorState:
//   1. Lanes: one horizontal lane per link, with other networks' busy
//      periods shaded and our frames placed where the chosen mode sent them,
//      plus an arrivals row on top. EMLSR's lead-in (initial control frame,
//      padding delay, the client's answer) and NSTR's padding to a common
//      end are drawn hollow in the link's hue, so the student can see what
//      each mode spends besides the frame.
//   2. Latency: one histogram per compared mode on a shared log axis, with
//      the mean and the 99th percentile marked.
// It knows nothing about the controls, so a screen can stack it above them
// (phone) or put it beside them (the presenter layout, spec 00). Time runs
// left to right and nothing is drawn as a wave, so nothing here can imply a
// frequency.
//
// COLOR: links take their Wi-Fi Classroom family hue (GL-003 §8.15.2, see
// mlo_simulator_parts.dart), always beside the band name. Busy periods and
// histogram bars are the neutral stack. Lime (text accent) marks the mean,
// the one number the lesson is about. Amber appears only as the "worse than
// the best single link" verdict, with its word and icon (§8.13).
//
// PRESENTER (spec 00): inside a PresenterLayout the verdict line (does MLO
// beat the best single link here, and by how much) sits over the lanes, the
// lanes and the histograms share the stage height with no scroll, each
// histogram leads with its mean in the accent, and painters read
// PresenterMode.scaleOf.
//
// ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mlo_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'mlo_simulator_controls.dart' show mloVerdict;
import 'mlo_simulator_parts.dart';
import 'mlo_simulator_state.dart';

class MloSimulatorStage extends StatelessWidget {
  const MloSimulatorStage({super.key, required this.state});

  final MloSimulatorState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _VerdictStrip(state: state),
              const SizedBox(height: AppSpacing.xs),
              Expanded(flex: 6, child: _LanesCard(state: state, fill: true)),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                flex: 5,
                child: _HistogramCard(state: state, fill: true),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LanesCard(state: state),
            const SizedBox(height: AppSpacing.sm),
            _HistogramCard(state: state),
          ],
        );
      },
    );
  }
}

/// What a mode's lanes show, in one sentence.
String mloLaneCaption(MloSimulatorState s) {
  final MloRun run = s.run;
  final MloModeResult r = s.laneResult;
  final List<MloLinkConfig> links = run.config.links;
  switch (s.laneMode) {
    case MloMode.single:
      return 'Single link on ${links[r.singleLink!].band.label}, the best of '
          'the single links here. Every frame waits for this one link.';
    case MloMode.str:
      if (r.fellBackToSingle) return _oneLink(links);
      return 'STR: each link sends on its own. A frame goes on whichever link '
          'is free first.';
    case MloMode.nstr:
      if (r.fellBackToSingle) return _oneLink(links);
      return 'NSTR: frames on two links start together and end together; the '
          'shorter one is padded (hollow). Nothing else starts until both end.';
    case MloMode.emlsr:
      if (run.config.emlsrDisabledByDriver && links.length > 1) {
        return 'EMLSR disabled by driver: the client falls back to one link, '
            '${links[r.singleLink!].band.label} (the least busy here).';
      }
      if (r.fellBackToSingle) return _oneLink(links);
      return 'EMLSR: one exchange at a time. Each opens with the initial '
          'control frame and padding delay (hollow), and the next waits out '
          'the transition delay.';
  }
}

String _oneLink(List<MloLinkConfig> links) =>
    'Only one link (${links.first.band.label}) is on, so every mode is the '
    'single link.';

// ── Lanes ───────────────────────────────────────────────────────────────────

class _LanesCard extends StatelessWidget {
  const _LanesCard({required this.state, this.fill = false});

  final MloSimulatorState state;

  /// Presenter: fill a bounded box; the lane-mode select sits in the header
  /// and the time controls share one row.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final MloSimulatorState s = state;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final TextStyle rowLabel =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final MloLanesStyle style = MloLanesStyle(
      sc: sc,
      colors: colors,
      busy: colors.textTertiary.withValues(alpha: colors.isLight ? 0.30 : 0.35),
      grid: colors.border,
      tick: colors.textSecondary,
      // Painted labels do not see MediaQuery's text scale.
      labelStyle: mono.inlineCode.copyWith(
        fontSize: sc.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
      rowLabelStyle: rowLabel.copyWith(
        fontSize: sc.paintFont(rowLabel.fontSize ?? AppTextSize.caption),
      ),
    );
    final List<MloLinkConfig> links = s.run.config.links;
    final Widget lanes = Semantics(
      label: _lanesSemantics(s),
      excludeSemantics: true,
      child: SizedBox(
        height: fill ? null : 34.0 * (links.length + 1) + 22,
        child: CustomPaint(
          painter: MloLanesPainter(
            links: links,
            result: s.laneResult,
            arrivalsUs: s.run.arrivalsUs,
            t0: s.windowStartUs,
            t1: s.windowEndUs,
            style: style,
          ),
          size: Size.infinite,
        ),
      ),
    );
    final AppSelect<MloMode> laneSelect = AppSelect<MloMode>(
      value: s.laneMode,
      semanticLabel: 'Show the lanes for',
      items: <AppSelectItem<MloMode>>[
        (MloMode.single, 'Best single link'),
        for (final MloMode m in kMloComparableModes) (m, m.label),
      ],
      onChanged: (MloMode m) => s.laneMode = m,
    );
    final MloSlider viewSlider = MloSlider(
      label: 'View starts at',
      valueText: mloFmtUs(s.windowStartUs),
      value: s.windowStartUs,
      min: 0,
      max: math.max(1, s.windowStartMaxUs),
      divisions: 200,
      onChanged: (double v) => s.windowStartUs = v,
      semanticValue: (double v) => mloFmtUs(v),
    );
    if (fill) {
      return MloCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: MloSectionLabel('Links over time')),
                SizedBox(width: 260, child: laneSelect),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              mloLaneCaption(s),
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(child: lanes),
            const SizedBox(height: AppSpacing.xxs),
            _LanesLegend(links: links, mode: s.laneMode),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                AppToggle<MloWindow>(
                  semanticLabel: 'Time shown in the lanes',
                  value: s.window,
                  items: <AppToggleItem<MloWindow>>[
                    for (final MloWindow w in MloWindow.values) (w, w.label),
                  ],
                  onChanged: (MloWindow w) => s.window = w,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: viewSlider),
              ],
            ),
          ],
        ),
      );
    }
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Links over time'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(label: 'Show the lanes for', field: laneSelect),
          const SizedBox(height: AppSpacing.xs),
          Text(
            mloLaneCaption(s),
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          lanes,
          const SizedBox(height: AppSpacing.xs),
          _LanesLegend(links: links, mode: s.laneMode),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<MloWindow>(
            label: 'Time shown',
            semanticLabel: 'Time shown in the lanes',
            value: s.window,
            expand: true,
            items: <AppToggleItem<MloWindow>>[
              for (final MloWindow w in MloWindow.values) (w, w.label),
            ],
            onChanged: (MloWindow w) => s.window = w,
          ),
          const SizedBox(height: AppSpacing.xs),
          viewSlider,
        ],
      ),
    );
  }

  static String _lanesSemantics(MloSimulatorState s) {
    final MloModeResult r = s.laneResult;
    final List<MloLinkConfig> links = s.run.config.links;
    final double t0 = s.windowStartUs;
    final double t1 = s.windowEndUs;
    final List<MloTx> shown = r.txsIn(t0, t1).toList();
    final List<int> per = List<int>.filled(links.length, 0);
    for (final MloTx t in shown) {
      per[t.link]++;
    }
    final int arrived = s.run.arrivalsUs
        .where((double a) => a >= t0 && a < t1)
        .length;
    final StringBuffer b = StringBuffer(
      'Lanes for ${s.laneMode == MloMode.single ? 'the best single link' : s.laneMode.label}, '
      'from ${mloFmtUs(t0)} to ${mloFmtUs(t1)}. $arrived frames arrived. ',
    );
    for (int k = 0; k < links.length; k++) {
      final double share = r.timelines[k].busyShare(t0, t1);
      b.write(
        '${links[k].band.label}: ${per[k]} of our frames, other networks '
        'busy ${mloPct(share)} of the time. ',
      );
    }
    return b.toString().trimRight();
  }
}

class _LanesLegend extends StatelessWidget {
  const _LanesLegend({required this.links, required this.mode});

  final List<MloLinkConfig> links;
  final MloMode mode;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? small = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    Widget box({required Color fill, Color? stroke, required String label}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 16,
              height: 10,
              decoration: BoxDecoration(
                color: fill,
                border: stroke == null
                    ? null
                    : Border.all(color: stroke, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(label, style: small),
          ],
        );
    final Color neutralHue = colors.textSecondary;
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final MloLinkConfig l in links)
            MloLinkTag(band: l.band, suffix: 'frame'),
          box(
            fill: colors.textTertiary.withValues(
              alpha: colors.isLight ? 0.30 : 0.35,
            ),
            label: 'Other networks (busy)',
          ),
          if (mode == MloMode.emlsr)
            box(
              fill: neutralHue.withValues(alpha: 0.15),
              stroke: neutralHue,
              label: 'EMLSR lead-in',
            ),
          if (mode == MloMode.nstr)
            box(
              fill: neutralHue.withValues(alpha: 0.15),
              stroke: neutralHue,
              label: 'NSTR padding',
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 2, height: 10, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xxs),
              Text('Frame arrives', style: small),
            ],
          ),
        ],
      ),
    );
  }
}

@immutable
class MloLanesStyle {
  const MloLanesStyle({
    required this.colors,
    required this.busy,
    required this.grid,
    required this.tick,
    required this.labelStyle,
    required this.rowLabelStyle,
    this.sc = PresenterScale.normal,
  });

  final AppColorScheme colors;
  final Color busy;
  final Color grid;
  final Color tick;
  final TextStyle labelStyle;
  final TextStyle rowLabelStyle;

  /// Presenter scale for strokes and margins (identity outside presenter
  /// mode; the label styles already carry the text factor).
  final PresenterScale sc;

  @override
  bool operator ==(Object other) =>
      other is MloLanesStyle &&
      other.colors.isLight == colors.isLight &&
      other.busy == busy &&
      other.labelStyle == labelStyle &&
      other.rowLabelStyle == rowLabelStyle &&
      other.sc == sc;

  @override
  int get hashCode =>
      Object.hash(colors.isLight, busy, labelStyle, rowLabelStyle, sc);
}

class MloLanesPainter extends CustomPainter {
  MloLanesPainter({
    required this.links,
    required this.result,
    required this.arrivalsUs,
    required this.t0,
    required this.t1,
    required this.style,
  });

  final List<MloLinkConfig> links;
  final MloModeResult result;
  final List<double> arrivalsUs;
  final double t0;
  final double t1;
  final MloLanesStyle style;

  double get _labelW => 60 * style.sc.text;
  double get _axisH => 18 * style.sc.text;

  @override
  void paint(Canvas canvas, Size size) {
    final int rows = links.length + 1;
    final double plotH = size.height - _axisH;
    final double rowH = plotH / rows;
    final double left = _labelW;
    final double right = size.width - 2;
    final double span = t1 - t0;
    double x(double t) => left + (t - t0) / span * (right - left);
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = style.sc.strokeWidth(1);

    // Row labels and separators.
    for (int i = 0; i < rows; i++) {
      final double y = i * rowH;
      _text(
        canvas,
        i == 0 ? 'Arrivals' : links[i - 1].band.label,
        style.rowLabelStyle,
        Offset(0, y + rowH / 2),
        maxWidth: _labelW - 4,
      );
      canvas.drawLine(Offset(left, y + rowH), Offset(right, y + rowH), grid);
    }

    // Time grid and labels.
    final double tick = span <= 2000
        ? 500
        : span <= 5000
        ? 1000
        : 5000;
    double lastRight = double.negativeInfinity;
    for (double t = (t0 / tick).ceil() * tick; t <= t1 + 1e-6; t += tick) {
      final double gx = x(t);
      canvas.drawLine(Offset(gx, 0), Offset(gx, plotH), grid);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: mloFmtTick(t), style: style.labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final double lx = (gx - tp.width / 2).clamp(left, right - tp.width);
      if (lx < lastRight + 6) continue;
      tp.paint(canvas, Offset(lx, plotH + 3));
      lastRight = lx + tp.width;
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, 0, right, plotH));

    // Arrivals.
    final Paint arr = Paint()
      ..color = style.tick
      ..strokeWidth = style.sc.strokeWidth(1.5);
    for (final double a in arrivalsUs) {
      if (a < t0) continue;
      if (a > t1) break;
      canvas.drawLine(
        Offset(x(a), rowH * 0.25),
        Offset(x(a), rowH * 0.75),
        arr,
      );
    }

    // Busy periods, per link, as this mode saw them.
    for (int k = 0; k < links.length; k++) {
      final double y = (k + 1) * rowH;
      for (final (double s, double e) in result.timelines[k].busyIn(t0, t1)) {
        canvas.drawRect(
          Rect.fromLTRB(x(s), y + 3, x(e), y + rowH - 3),
          Paint()..color = style.busy,
        );
      }
    }

    // Our frames.
    for (final MloTx t in result.txsIn(t0, t1)) {
      final WifiLabClientStyle ls = mloLinkStyle(
        links[t.link].band,
        style.colors,
      );
      final double y = (t.link + 1) * rowH;
      final double top = y + 6;
      final double bottom = y + rowH - 6;
      void hollow(double a, double b, String label) {
        if (b - a <= 0) return;
        final Rect r = Rect.fromLTRB(x(a), top, x(b), bottom);
        canvas.drawRect(r, Paint()..color = ls.hue.withValues(alpha: 0.18));
        canvas.drawRect(
          r.deflate(0.75),
          Paint()
            ..color = ls.hue
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.sc.strokeWidth(1.5),
        );
        // Label only the part inside the view, so a block cut by the left
        // edge never prints a fragment.
        final double visL = math.max(r.left, left);
        final double visR = math.min(r.right, right);
        if (visR - visL > 30 * style.sc.text) {
          _text(
            canvas,
            label,
            style.labelStyle.copyWith(color: style.colors.textPrimary),
            Offset(visL + 3, r.center.dy),
            maxWidth: visR - visL - 4,
          );
        }
      }

      hollow(t.startUs, t.dataStartUs, 'ICF');
      final Rect data = Rect.fromLTRB(
        x(t.dataStartUs),
        top,
        x(t.dataEndUs),
        bottom,
      );
      canvas.drawRect(data, Paint()..color = ls.hue);
      // A hairline between back-to-back frames.
      canvas.drawLine(
        data.topLeft,
        data.bottomLeft,
        Paint()
          ..color = style.colors.surface1
          ..strokeWidth = style.sc.strokeWidth(1),
      );
      final String n = '${t.frame + 1}';
      final double dl = math.max(data.left, left);
      final double dr = math.min(data.right, right);
      if (dr - dl > (8.0 * n.length + 6) * style.sc.text) {
        _text(
          canvas,
          n,
          style.labelStyle.copyWith(color: ls.onHue),
          Offset(dl + 3, data.center.dy),
          maxWidth: dr - dl - 4,
        );
      }
      hollow(t.dataEndUs, t.endUs, 'pad');
    }
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String s,
    TextStyle ts,
    Offset at, {
    required double maxWidth,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: ts),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: math.max(0, maxWidth));
    tp.paint(canvas, Offset(at.dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(MloLanesPainter old) =>
      old.result != result ||
      old.t0 != t0 ||
      old.t1 != t1 ||
      old.style != style ||
      old.links != links;
}

// ── Histograms ──────────────────────────────────────────────────────────────

const int _kBins = 30;

class _HistogramCard extends StatelessWidget {
  const _HistogramCard({required this.state, this.fill = false});

  final MloSimulatorState state;

  /// Presenter: fill a bounded box, each histogram an equal share.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final MloSimulatorState s = state;
    final MloRun run = s.run;
    final List<MloMode> modes = s.comparedModes;
    final (double lo, double hi) = mloHistogramRange(<List<double>>[
      for (final MloMode m in modes) run.result(m).sortedLatenciesUs,
    ]);
    if (fill) {
      final AppColorScheme colors = context.colors;
      return MloCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: MloSectionLabel(
                    'Latency: frame arrives to frame sent',
                  ),
                ),
                Text(
                  'Same traffic for every mode. Log scale.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
            for (final MloMode m in modes) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: _ModeHistogram(
                  run: run,
                  mode: m,
                  lo: lo,
                  hi: hi,
                  fill: true,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Latency: frame arrives to frame sent'),
          const SizedBox(height: AppSpacing.xxs),
          MloNote(
            icon: Icons.info_outline,
            message:
                'Same random traffic for every mode. Log scale: each step '
                'on the axis is ten times the one before.',
          ),
          for (final MloMode m in modes) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ModeHistogram(run: run, mode: m, lo: lo, hi: hi),
          ],
        ],
      ),
    );
  }
}

class _ModeHistogram extends StatelessWidget {
  const _ModeHistogram({
    required this.run,
    required this.mode,
    required this.lo,
    required this.hi,
    this.fill = false,
  });

  final MloRun run;
  final MloMode mode;
  final double lo;
  final double hi;

  /// Presenter: the plot takes the height left, and the mean leads in the
  /// accent at readout size.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final MloModeResult r = run.result(mode);
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final String name = mode == MloMode.single
        ? 'Best single link (${run.config.links[r.singleLink!].band.label})'
        : r.fellBackToSingle && run.linkCount > 1
        ? '${mode.label} (disabled by driver)'
        : mode.label;
    final bool worse = run.worseThanBestSingle(mode);
    final Widget plot = _plotOf(r, colors, mono, sc);
    final String stats = r.overloaded
        ? 'Overloaded'
        : 'mean ${mloFmtUs(r.meanUs)}  p99 ${mloFmtUs(r.p99Us)}';
    final String semantics =
        '$name. ${r.overloaded ? 'Overloaded: frames arrive faster than it can send them.' : 'Mean ${mloFmtUs(r.meanUs)}, 99th percentile ${mloFmtUs(r.p99Us)}.'}'
        '${worse ? ' Worse than the best single link.' : ''}';
    if (fill) {
      // Presenter: one row per mode, the numbers left of the plot. The
      // numbers scale down as one piece if a short window leaves the row
      // less height than they need.
      final String shortName = mode == MloMode.single
          ? 'Single (${run.config.links[r.singleLink!].band.label})'
          : r.fellBackToSingle && run.linkCount > 1
          ? '${mode.label} (driver off)'
          : mode.label;
      return Semantics(
        container: true,
        label: semantics,
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 240,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          shortName,
                          style: text.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (worse) ...<Widget>[
                          const SizedBox(width: AppSpacing.xxs),
                          Icon(
                            Icons.warning_amber_rounded,
                            size: sc.markerSize(16),
                            color: colors.statusWarning,
                          ),
                          Text(
                            'worse',
                            style: text.bodySmall?.copyWith(
                              color: colors.statusWarning,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (r.overloaded)
                      Text(
                        'Overloaded',
                        style: mono.outputMedium.copyWith(
                          color: colors.statusDanger,
                        ),
                      )
                    else ...<Widget>[
                      Text(
                        'mean ${mloFmtUs(r.meanUs)}',
                        style: mono.outputMedium.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                      Text(
                        'p99 ${mloFmtUs(r.p99Us)}',
                        style: mono.inlineCode.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: plot),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      label:
          '$name. ${r.overloaded ? 'Overloaded: frames arrive faster than it can send them.' : 'Mean ${mloFmtUs(r.meanUs)}, 99th percentile ${mloFmtUs(r.p99Us)}.'}'
          '${worse ? ' Worse than the best single link.' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                name,
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                stats,
                style: mono.inlineCode.copyWith(
                  color: r.overloaded
                      ? colors.statusDanger
                      : colors.textSecondary,
                ),
              ),
              if (worse)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: sc.markerSize(16),
                      color: colors.statusWarning,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Worse than the best single link',
                      style: text.bodySmall?.copyWith(
                        color: colors.statusWarning,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(height: 76, child: plot),
        ],
      ),
    );
  }

  Widget _plotOf(
    MloModeResult r,
    AppColorScheme colors,
    AppMonoText mono,
    PresenterScale sc,
  ) => CustomPaint(
    painter: MloHistogramPainter(
      counts: mloLogHistogram(r.sortedLatenciesUs, lo, hi, _kBins),
      lo: lo,
      hi: hi,
      meanUs: r.meanUs,
      p99Us: r.p99Us,
      bar: colors.textTertiary,
      mean: colors.textAccent,
      p99: colors.textPrimary,
      grid: colors.border,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: sc.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
      sc: sc,
    ),
    size: Size.infinite,
  );
}

class MloHistogramPainter extends CustomPainter {
  MloHistogramPainter({
    required this.counts,
    required this.lo,
    required this.hi,
    required this.meanUs,
    required this.p99Us,
    required this.bar,
    required this.mean,
    required this.p99,
    required this.grid,
    required this.labelStyle,
    this.sc = PresenterScale.normal,
  });

  final List<int> counts;
  final double lo;
  final double hi;
  final double meanUs;
  final double p99Us;
  final Color bar;
  final Color mean;
  final Color p99;
  final Color grid;
  final TextStyle labelStyle;

  /// Presenter scale for strokes and margins (identity outside presenter
  /// mode; labelStyle already carries the text factor).
  final PresenterScale sc;

  double get _axisH => 16 * sc.text;
  double get _markH => 12 * sc.text;

  @override
  void paint(Canvas canvas, Size size) {
    final double plotTop = _markH;
    final double plotH = size.height - _axisH - plotTop;
    final double w = size.width;
    final double l0 = math.log(lo) / math.ln10;
    final double l1 = math.log(hi) / math.ln10;
    double x(double us) =>
        ((math.log(math.max(us, lo)) / math.ln10 - l0) / (l1 - l0) * w).clamp(
          0.0,
          w,
        );

    // Decade grid and labels.
    final Paint gp = Paint()
      ..color = grid
      ..strokeWidth = sc.strokeWidth(1);
    for (int d = l0.round(); d <= l1.round(); d++) {
      final double gx = x(math.pow(10, d).toDouble());
      canvas.drawLine(Offset(gx, plotTop), Offset(gx, plotTop + plotH), gp);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: mloFmtTick(math.pow(10, d).toDouble()),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (gx - tp.width / 2).clamp(0.0, w - tp.width),
          plotTop + plotH + 2,
        ),
      );
    }
    canvas.drawLine(Offset(0, plotTop + plotH), Offset(w, plotTop + plotH), gp);

    // Bars.
    final int maxC = counts.fold<int>(1, math.max);
    final double bw = w / counts.length;
    final Paint bp = Paint()..color = bar;
    for (int i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final double h = math.max(2, counts[i] / maxC * plotH);
      canvas.drawRect(
        Rect.fromLTWH(i * bw + 1, plotTop + plotH - h, bw - 2, h),
        bp,
      );
    }

    // Mean (solid, accent) and 99th percentile (dashed).
    void marker(double us, Color c, String label, {required bool dashed}) {
      final double mx = x(us);
      final Paint p = Paint()
        ..color = c
        ..strokeWidth = sc.strokeWidth(2);
      if (dashed) {
        for (double y = plotTop; y < plotTop + plotH; y += 6) {
          canvas.drawLine(
            Offset(mx, y),
            Offset(mx, math.min(y + 3, plotTop + plotH)),
            p,
          );
        }
      } else {
        canvas.drawLine(Offset(mx, plotTop), Offset(mx, plotTop + plotH), p);
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: c),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      tp.paint(canvas, Offset((mx - tp.width / 2).clamp(0.0, w - tp.width), 0));
    }

    marker(meanUs, mean, 'mean', dashed: false);
    if (x(p99Us) - x(meanUs) > 34 * sc.text) {
      marker(p99Us, p99, 'p99', dashed: true);
    } else {
      // Too close to label both: draw the line, skip the word.
      final double mx = x(p99Us);
      final Paint p = Paint()
        ..color = p99
        ..strokeWidth = sc.strokeWidth(2);
      for (double y = plotTop; y < plotTop + plotH; y += 6) {
        canvas.drawLine(
          Offset(mx, y),
          Offset(mx, math.min(y + 3, plotTop + plotH)),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MloHistogramPainter old) =>
      old.counts != counts ||
      old.lo != lo ||
      old.hi != hi ||
      old.meanUs != meanUs ||
      old.p99Us != p99Us ||
      old.bar != bar ||
      old.mean != mean ||
      old.sc != sc;
}

// ── Presenter verdict ───────────────────────────────────────────────────────

/// Presenter only: the verdict line, over the lanes where the class looks:
/// whether MLO beats the best single link here, and by how much.
class _VerdictStrip extends StatelessWidget {
  const _VerdictStrip({required this.state});

  final MloSimulatorState state;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final MloSimulatorState s = state;
    final bool anyWorse = s.shownModes.any(s.run.worseThanBestSingle);
    final Color color = anyWorse ? colors.statusWarning : colors.textPrimary;
    return MloCard(
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              anyWorse
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color: anyWorse ? colors.statusWarning : colors.textAccent,
              size: PresenterMode.scaleOf(context).markerSize(22),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                mloVerdict(s),
                style: text.titleMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
