// Stage for the Wi-Fi Lab Rate Adaptation tool (rate-adaptation).
//
// Three views of one run, top to bottom:
//   1. Attempts, the last 5 ms of air: each attempt drawn to scale as its
//      wait (AIFS + mean backoff, a thin line that grows with every retry),
//      its PPDU (a block in the MCS's hue, the MCS number inside when it
//      fits) and its ACK. A failed attempt is an outlined block with a red
//      "x" under it; a sample attempt has a marker over it.
//   2. The chosen (best-throughput) rate over the last 20 s as a step line in
//      each MCS's hue, against a dashed line for the MCS the SNR supports.
//   3. The per-rate statistics table, updating every 50 ms.
//
// PRESENTER (PresenterMode.isActive): the same three views fill the bounded
// stage box with no scroll. The chosen rate, what the link delivers and what
// its retries cost sit on top at the headline scale (moved from the
// readouts); the attempts strip runs full width under them; the chart
// (growing into the height) and the table share the rest. Painters thicken strokes and grow
// the strip with PresenterMode.scaleOf.
//
// Nothing here draws a wave, so nothing can imply a frequency change (Wi-Fi
// Lab standing rule). Every hue is paired with an MCS number or name
// (GL-003 §8.15.2); failure is red with an "x" and a word (§8.13).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/rate_adaptation_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'rate_adaptation_controller.dart';
import 'rate_adaptation_parts.dart';

/// Width of the attempts strip, microseconds of air.
const double kRaStripWindowUs = 5000;

/// Width of the rate chart, microseconds.
const double kRaChartWindowUs = RaPath.walkPeriodS * 1e6;

class RateAdaptationStage extends StatelessWidget {
  const RateAdaptationStage({
    super.key,
    required this.controller,
    this.chartHeight = 180,
  });

  final RateAdaptationController controller;
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        if (PresenterMode.isActive(context)) {
          return _PresenterStage(engine: controller.engine);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AttemptsCard(engine: controller.engine),
            const SizedBox(height: AppSpacing.sm),
            _RateChartCard(engine: controller.engine, height: chartHeight),
            const SizedBox(height: AppSpacing.sm),
            RaStatsTable(engine: controller.engine),
          ],
        );
      },
    );
  }
}

// ── Presenter arrangement ─────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.engine});
  final RateAdaptationEngine engine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Headline(engine: engine),
        const SizedBox(height: AppSpacing.sm),
        _AttemptsCard(engine: engine),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The chart grows into whatever height is left.
              Expanded(
                flex: 5,
                child: _RateChartCard(engine: engine, height: null),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 4,
                child: LayoutBuilder(
                  // Full size when it fits; on a short window the table
                  // scales down as one piece rather than scroll.
                  builder: (BuildContext context, BoxConstraints box) =>
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: box.maxWidth,
                          child: RaStatsTable(engine: engine),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The chosen rate, large, with what the link delivers and what its retries
/// cost: the numbers the lesson is about.
class _Headline extends StatelessWidget {
  const _Headline({required this.engine});
  final RateAdaptationEngine engine;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final RaWindowStats w = engine.window;
    final int best = engine.ranking.bestThroughput;
    final bool fresh = engine.nowUs == 0;
    final int? sup = RateAdaptationMath.supportedMcs(engine.snrNowDb);

    Widget stat(String label, String value) => Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );

    return RaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Semantics(
            label: 'Chosen rate: ${RaFormat.rate(best)}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  fresh
                      ? 'Chosen rate (press Play or Step)'
                      : 'Chosen rate at ${RaFormat.clock(engine.nowUs)}, '
                            '${RaFormat.n(engine.distanceNowM)} m',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                Text(
                  RaFormat.mcs(best),
                  style: scale
                      .headlineStyle(mono.outputLarge)
                      .copyWith(color: RaPalette.of(best, colors)),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                stat(
                  'Delivered, last second',
                  fresh ? '-' : RaFormat.mbps(w.deliveredMbps),
                ),
                stat(
                  'Retries per frame',
                  fresh ? '-' : RaFormat.n(w.retriesPerFrame, 2),
                ),
                stat(
                  'Airtime on retries',
                  fresh ? '-' : RaFormat.pct(w.retryAirtimeShare),
                ),
                stat(
                  'SNR now, supports',
                  '${RaFormat.n(engine.snrNowDb)} dB, '
                      '${sup == null ? 'no MCS' : RaFormat.mcs(sup)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Style ───────────────────────────────────────────────────────────────────

@immutable
class _Style {
  const _Style({
    required this.colors,
    required this.label,
    required this.onHue,
  });

  final AppColorScheme colors;
  final TextStyle label;

  /// Text drawn on a filled MCS block.
  final Color onHue;

  factory _Style.of(BuildContext context) {
    final AppColorScheme c = context.colors;
    final TextStyle base =
        Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    return _Style(
      colors: c,
      label: base.copyWith(color: c.textSecondary),
      // The dark-theme hues are light and the light-theme hues are dark, so
      // the canvas color reads on every block.
      onHue: c.surface0,
    );
  }
}

TextPainter _text(String s, TextStyle style, TextScaler scaler) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
  textScaler: scaler,
)..layout();

// ── 1. Attempts strip ───────────────────────────────────────────────────────

/// Last frame, in words: what the strip shows for the most recent frame.
String raLastFrameText(RaFrame? f) {
  if (f == null) {
    return 'No frames yet. Press Play or Step one frame.';
  }
  final List<String> parts = <String>[
    for (final RaAttempt a in f.attempts)
      '${RaFormat.mcs(a.mcs)} ${a.delivered ? 'delivered' : 'failed'}',
  ];
  final String head = f.isSample
      ? 'Last frame (a sample frame, trying MCS ${f.sampleMcs})'
      : 'Last frame';
  final String tail = f.delivered
      ? (f.retries == 0 ? '.' : ' on retry ${f.retries}.')
      : ', then dropped at the retry limit.';
  return '$head: ${parts.join(', ')}$tail';
}

class _AttemptsCard extends StatelessWidget {
  const _AttemptsCard({required this.engine});
  final RateAdaptationEngine engine;

  @override
  Widget build(BuildContext context) {
    final _Style style = _Style.of(context);
    final AppColorScheme colors = style.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<RaAttempt> shown = engine.attempts
        .where((RaAttempt a) => a.endUs > engine.nowUs - kRaStripWindowUs)
        .toList();
    final int failed = shown.where((RaAttempt a) => !a.delivered).length;
    final String lastFrame = raLastFrameText(engine.lastFrame);
    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RaSectionLabel('Attempts, the last 5 ms of air'),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                'Attempts in the last 5 ms: ${shown.length}, $failed failed. '
                '$lastFrame',
            excludeSemantics: true,
            child: SizedBox(
              height: _StripPainter.heightFor(PresenterMode.scaleOf(context)),
              child: CustomPaint(
                painter: _StripPainter(
                  attempts: shown,
                  nowUs: engine.nowUs,
                  style: style,
                  scaler: MediaQuery.textScalerOf(context),
                  scale: PresenterMode.scaleOf(context),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                _Key(
                  glyph: _box(colors.textSecondary, filled: true),
                  label: 'delivered (MCS inside)',
                ),
                _Key(
                  glyph: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      _box(colors.textSecondary, filled: false),
                      Icon(Icons.close, size: 12, color: colors.statusDanger),
                    ],
                  ),
                  label: 'failed, no ACK',
                ),
                _Key(
                  glyph: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: colors.textPrimary,
                  ),
                  label: 'sample',
                ),
                _Key(
                  glyph: Container(
                    width: 14,
                    height: 2,
                    color: colors.textTertiary,
                  ),
                  label: 'wait: AIFS + backoff',
                ),
                _Key(
                  glyph: Container(
                    width: 5,
                    height: 10,
                    color: colors.textTertiary,
                  ),
                  label: 'ACK',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _SteadyText(
            text: lastFrame,
            longest: raLongestLastFrameText,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  static Widget _box(Color c, {required bool filled}) => Container(
    width: 14,
    height: 10,
    decoration: BoxDecoration(
      color: filled ? c : null,
      border: Border.all(color: c, width: 1.5),
    ),
  );
}

/// The longest last-frame sentence the model can produce: a sample frame
/// with seven attempts, the last delivered. Its height is reserved so the
/// controls below never move while the link runs.
final String raLongestLastFrameText = raLastFrameText(
  RaFrame(
    attempts: <RaAttempt>[
      for (int k = 0; k < 7; k++)
        RaAttempt(
          startUs: 0,
          cost: const RaAttemptCost(
            aifsUs: 0,
            backoffUs: 0,
            txUs: 0,
            responseUs: 0,
          ),
          mcs: 10,
          delivered: k == 6,
          attemptIndex: k,
          cw: 0,
          isSample: false,
          snrDb: 0,
        ),
    ],
    delivered: true,
    isSample: true,
    sampleMcs: 10,
    chain: const <int>[10, 10, 10, 10],
  ),
);

/// Text that always takes the height [longest] would take at this width, so
/// a changing sentence never moves what sits below it.
class _SteadyText extends StatelessWidget {
  const _SteadyText({
    required this.text,
    required this.longest,
    required this.style,
  });

  final String text;
  final String longest;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextStyle effective = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final TextPainter tp = TextPainter(
          text: TextSpan(text: longest, style: effective),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: c.maxWidth);
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: tp.height),
          child: Text(text, style: style),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.glyph, required this.label});
  final Widget glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 18, height: 18, child: Center(child: glyph)),
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
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.attempts,
    required this.nowUs,
    required this.style,
    required this.scaler,
    this.scale = PresenterScale.normal,
  });

  final List<RaAttempt> attempts;
  final double nowUs;
  final _Style style;
  final TextScaler scaler;

  /// Presenter scale: markers grow the geometry, strokes thicken. Identity
  /// outside presenter mode.
  final PresenterScale scale;

  static const double _height = 92;
  static const double _sampleTopBase = 0;
  static const double _blockTopBase = 12;
  static const double _blockHBase = 34;
  static const double _failTopBase = 50;

  /// Height of the strip at [scale].
  static double heightFor(PresenterScale scale) => scale.markerSize(_height);

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme c = style.colors;
    final double w = size.width;
    final double k = scale.marker;
    final double sampleTop = _sampleTopBase * k;
    final double blockTop = _blockTopBase * k;
    final double blockH = _blockHBase * k;
    final double failTop = _failTopBase * k;
    final double t0 = math.max(0, nowUs - kRaStripWindowUs);
    double x(double t) => (t - t0) / kRaStripWindowUs * w;
    final double waitY = blockTop + blockH / 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final Paint waitPaint = Paint()
      ..color = c.textTertiary
      ..strokeWidth = scale.strokeWidth(2);
    final Paint ackPaint = Paint()..color = c.textTertiary;
    final Paint failPaint = Paint()
      ..color = c.statusDanger
      ..strokeWidth = scale.strokeWidth(2)
      ..strokeCap = StrokeCap.round;

    for (final RaAttempt a in attempts) {
      final Color hue = RaPalette.of(a.mcs, c);
      // Wait: AIFS + mean backoff.
      canvas.drawLine(
        Offset(x(a.startUs), waitY),
        Offset(x(a.txStartUs), waitY),
        waitPaint,
      );
      // PPDU.
      final Rect block = Rect.fromLTRB(
        x(a.txStartUs),
        blockTop,
        math.max(x(a.txEndUs), x(a.txStartUs) + 1),
        blockTop + blockH,
      );
      if (a.delivered) {
        canvas.drawRect(block, Paint()..color = hue);
        // ACK after SIFS.
        final double ackStart = a.txEndUs + RaLink.sifsUs;
        canvas.drawRect(
          Rect.fromLTRB(
            x(ackStart),
            blockTop + blockH - 12 * k,
            math.max(x(ackStart + RaLink.ackUs), x(ackStart) + 1),
            blockTop + blockH,
          ),
          ackPaint,
        );
      } else {
        canvas.drawRect(block, Paint()..color = hue.withValues(alpha: 0.18));
        canvas.drawRect(
          block.deflate(scale.strokeWidth(1)),
          Paint()
            ..color = hue
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale.strokeWidth(2),
        );
        final double cx = block.center.dx;
        final double r = scale.markerSize(4);
        canvas.drawLine(
          Offset(cx - r, failTop),
          Offset(cx + r, failTop + 2 * r),
          failPaint,
        );
        canvas.drawLine(
          Offset(cx + r, failTop),
          Offset(cx - r, failTop + 2 * r),
          failPaint,
        );
      }
      // MCS number inside when it fits.
      final TextPainter tp = _text(
        '${a.mcs}',
        style.label.copyWith(
          color: a.delivered ? style.onHue : c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        scaler,
      );
      if (tp.width + 4 <= block.width) {
        tp.paint(
          canvas,
          Offset(
            block.center.dx - tp.width / 2,
            block.center.dy - tp.height / 2,
          ),
        );
      }
      if (a.isSample) {
        final double cx = block.center.dx;
        final Path tri = Path()
          ..moveTo(cx - 5 * k, sampleTop)
          ..lineTo(cx + 5 * k, sampleTop)
          ..lineTo(cx, sampleTop + 8 * k)
          ..close();
        canvas.drawPath(tri, Paint()..color = c.textPrimary);
      }
    }
    canvas.restore();

    // Axis.
    final double axisY = size.height - 22 * k;
    canvas.drawLine(
      Offset(0, axisY),
      Offset(w, axisY),
      Paint()
        ..color = c.border
        ..strokeWidth = scale.strokeWidth(1),
    );
    final TextPainter left = _text(
      nowUs <= kRaStripWindowUs ? '0 ms' : '-5 ms',
      style.label,
      scaler,
    );
    left.paint(canvas, Offset(0, axisY + 3));
    final String rightLabel = nowUs <= kRaStripWindowUs
        ? '5 ms'
        : 'now, ${RaFormat.clock(nowUs)}';
    final TextPainter right = _text(rightLabel, style.label, scaler);
    right.paint(canvas, Offset(w - right.width, axisY + 3));
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.nowUs != nowUs ||
      old.attempts.length != attempts.length ||
      old.style != style ||
      old.scaler != scaler ||
      old.scale != scale;
}

// ── 2. Rate chart ───────────────────────────────────────────────────────────

class _RateChartCard extends StatelessWidget {
  const _RateChartCard({required this.engine, required this.height});
  final RateAdaptationEngine engine;

  /// Plot height; null fills the card's bounded height (presenter).
  final double? height;

  @override
  Widget build(BuildContext context) {
    final _Style style = _Style.of(context);
    final AppColorScheme colors = style.colors;
    final int best = engine.ranking.bestThroughput;
    final int? sup = RateAdaptationMath.supportedMcs(engine.snrNowDb);
    final Widget plot = Semantics(
      label:
          'Chosen rate now ${RaFormat.mcs(best)}. The SNR now '
          'supports ${sup == null ? 'no MCS' : RaFormat.mcs(sup)}.',
      excludeSemantics: true,
      child: SizedBox(
        height: height ?? double.infinity,
        child: CustomPaint(
          painter: _ChartPainter(
            history: engine.history,
            nowUs: engine.nowUs,
            style: style,
            scaler: MediaQuery.textScalerOf(context),
            scale: PresenterMode.scaleOf(context),
          ),
          size: Size.infinite,
        ),
      ),
    );
    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RaSectionLabel('Chosen rate, the last 20 s'),
          const SizedBox(height: AppSpacing.xs),
          if (height == null) Expanded(child: plot) else plot,
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                _Key(
                  glyph: Container(
                    width: 14,
                    height: 3,
                    color: RaPalette.of(best, colors),
                  ),
                  label: 'chosen: best throughput (hue = MCS)',
                ),
                _Key(
                  glyph: CustomPaint(
                    size: const Size(14, 2),
                    painter: _DashKeyPainter(colors.textTertiary),
                  ),
                  label: 'MCS the SNR supports',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const RaNote(
            'Teaching model: each attempt succeeds with a chance set by a '
            'smooth curve, 90% at the SNR an MCS needs and 10% about 4.4 dB '
            'lower. It is not a measured error curve.',
          ),
        ],
      ),
    );
  }
}

class _DashKeyPainter extends CustomPainter {
  _DashKeyPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, 1), Offset(math.min(x + 3, size.width), 1), p);
    }
  }

  @override
  bool shouldRepaint(_DashKeyPainter old) => old.color != color;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.history,
    required this.nowUs,
    required this.style,
    required this.scaler,
    this.scale = PresenterScale.normal,
  });

  final List<RaUpdate> history;
  final double nowUs;
  final _Style style;
  final TextScaler scaler;

  /// Presenter scale for strokes and the dot; identity elsewhere.
  final PresenterScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme c = style.colors;
    final TextPainter probe = _text('11', style.label, scaler);
    final double left = probe.width + 8;
    final double bottomPad = probe.height + 6;
    final Rect plot = Rect.fromLTRB(
      left,
      probe.height / 2,
      size.width - 6,
      size.height - bottomPad,
    );
    final double t1 = math.max(nowUs, kRaChartWindowUs);
    final double t0 = t1 - kRaChartWindowUs;
    double x(double t) => plot.left + (t - t0) / kRaChartWindowUs * plot.width;
    double y(int m) => plot.bottom - m / RaLink.maxMcs * plot.height;

    // Grid and MCS labels.
    final Paint grid = Paint()
      ..color = c.border
      ..strokeWidth = scale.strokeWidth(1);
    for (int m = 0; m <= RaLink.maxMcs; m++) {
      canvas.drawLine(Offset(plot.left, y(m)), Offset(plot.right, y(m)), grid);
      if (m.isEven || m == RaLink.maxMcs) {
        final TextPainter tp = _text('$m', style.label, scaler);
        tp.paint(canvas, Offset(left - 6 - tp.width, y(m) - tp.height / 2));
      }
    }
    final TextPainter l = _text(
      nowUs <= kRaChartWindowUs ? '0 s' : '-20 s',
      style.label,
      scaler,
    );
    l.paint(canvas, Offset(plot.left, plot.bottom + 4));
    final TextPainter r = _text(
      nowUs <= kRaChartWindowUs ? '20 s' : 'now',
      style.label,
      scaler,
    );
    r.paint(canvas, Offset(plot.right - r.width, plot.bottom + 4));

    final List<RaUpdate> h = history
        .where((RaUpdate u) => u.timeUs >= t0)
        .toList();
    if (h.isEmpty) return;

    // Supported MCS: dashed step line.
    final Paint dash = Paint()
      ..color = c.textTertiary
      ..strokeWidth = scale.strokeWidth(1.5);
    for (int i = 0; i < h.length; i++) {
      final int? m = h[i].supportedMcs;
      if (m == null) continue;
      final double xa = x(h[i].timeUs);
      final double xb = i + 1 < h.length ? x(h[i + 1].timeUs) : x(nowUs);
      for (double xx = xa; xx < xb; xx += 6) {
        canvas.drawLine(
          Offset(xx, y(m)),
          Offset(math.min(xx + 3, xb), y(m)),
          dash,
        );
      }
    }

    // Chosen rate: a step line, each run in its MCS's hue.
    for (int i = 0; i < h.length; i++) {
      final int m = h[i].ranking.bestThroughput;
      final double xa = x(h[i].timeUs);
      final double xb = i + 1 < h.length ? x(h[i + 1].timeUs) : x(nowUs);
      final Paint p = Paint()
        ..color = RaPalette.of(m, c)
        ..strokeWidth = scale.strokeWidth(3)
        ..strokeCap = StrokeCap.butt;
      canvas.drawLine(Offset(xa, y(m)), Offset(xb, y(m)), p);
      if (i + 1 < h.length) {
        final int next = h[i + 1].ranking.bestThroughput;
        if (next != m) {
          canvas.drawLine(
            Offset(xb, y(m)),
            Offset(xb, y(next)),
            Paint()
              ..color = c.textTertiary
              ..strokeWidth = scale.strokeWidth(1),
          );
        }
      }
    }

    // Now: a dot and the MCS.
    final int now = h.last.ranking.bestThroughput;
    final Offset dot = Offset(x(nowUs), y(now));
    final double dotR = scale.markerSize(5);
    canvas.drawCircle(dot, dotR, Paint()..color = RaPalette.of(now, c));
    canvas.drawCircle(
      dot,
      dotR,
      Paint()
        ..color = c.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale.strokeWidth(1.5),
    );
    final TextPainter tag = _text(
      RaFormat.mcs(now),
      style.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
      scaler,
    );
    final double tx = math
        .min(dot.dx - tag.width - 8, plot.right - tag.width)
        .clamp(plot.left, plot.right - tag.width);
    final double ty =
        (now >= RaLink.maxMcs - 1 ? dot.dy + 6 : dot.dy - tag.height - 6).clamp(
          0.0,
          size.height - tag.height,
        );
    final RRect bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(tx - 3, ty - 1, tag.width + 6, tag.height + 2),
      const Radius.circular(AppRadius.control / 2),
    );
    canvas.drawRRect(bg, Paint()..color = c.surface1.withValues(alpha: 0.9));
    tag.paint(canvas, Offset(tx, ty));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.nowUs != nowUs ||
      old.history.length != history.length ||
      old.style != style ||
      old.scaler != scaler ||
      old.scale != scale;
}

// ── 3. Statistics table ─────────────────────────────────────────────────────

/// Roles a rate holds in the current retry chain, short and long.
List<(String, String)> raRoles(RaRanking r, int mcs) => <(String, String)>[
  if (r.bestThroughput == mcs) ('1st', 'best throughput'),
  if (r.secondThroughput == mcs) ('2nd', 'second-best throughput'),
  if (r.bestProbability == mcs) ('P', 'best probability'),
  if (RaLink.lowestMcs == mcs) ('low', 'lowest rate'),
];

class RaStatsTable extends StatelessWidget {
  const RaStatsTable({super.key, required this.engine});
  final RateAdaptationEngine engine;

  static const double _mcsWBase = 44;
  static const double _rateWBase = 44;
  static const double _pctWBase = 38;
  static const double _estWBase = 38;
  static const double _roleWBase = 64;

  @override
  Widget build(BuildContext context) {
    // Fixed columns grow with the presenter's text so the numbers keep one
    // line; outside presenter mode the factor is 1.
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final bool presenting = PresenterMode.isActive(context);
    final double mcsW = scale.paintFont(_mcsWBase);
    final double rateW = scale.paintFont(_rateWBase);
    final double pctW = scale.paintFont(_pctWBase);
    final double estW = scale.paintFont(_estWBase);
    final double roleW = scale.paintFont(_roleWBase);
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle cell = mono.inlineCode.copyWith(
      color: colors.textPrimary,
      fontSize: text.bodySmall?.fontSize,
    );
    final TextStyle head =
        text.labelSmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final RaRanking r = engine.ranking;

    Widget row(RaRateStats st) {
      final double? p = st.ewma;
      final List<(String, String)> roles = raRoles(r, st.mcs);
      final String status = p == null
          ? 'untried'
          : st.ignored
          ? 'ignored, under 10%'
          : '';
      final String sem =
          '${RaFormat.rate(st.mcs)}: '
          '${p == null ? 'untried' : 'smoothed success ${RaFormat.pct(p)}'}'
          '${st.ignored ? ', ignored because under 10%' : ''}, estimate '
          '${RaFormat.mbps(st.throughputEstimateMbps)}'
          '${roles.isEmpty ? '' : ', ${roles.map(((String, String) e) => e.$2).join(', ')}'}.';
      final bool isBest = r.bestThroughput == st.mcs;
      return Semantics(
        label: sem,
        excludeSemantics: true,
        child: Container(
          decoration: BoxDecoration(
            color: isBest ? colors.surface2 : null,
            borderRadius: BorderRadius.circular(AppRadius.control / 2),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: mcsW,
                child: Row(
                  children: <Widget>[
                    RaSwatch(mcs: st.mcs),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        '${st.mcs}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: cell.copyWith(
                          fontWeight: isBest ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: rateW,
                child: Text(
                  RaFormat.n(RaLink.phyRateMbps(st.mcs)),
                  textAlign: TextAlign.right,
                  style: cell.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: status.isNotEmpty && p == null
                    ? Text(
                        status,
                        style: head,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : _Bar(
                        value: p ?? 0,
                        color: RaPalette.of(st.mcs, colors),
                        track: colors.disabledFill,
                        muted: st.ignored,
                      ),
              ),
              SizedBox(
                width: pctW,
                child: Text(
                  p == null ? '-' : RaFormat.pct(p),
                  textAlign: TextAlign.right,
                  style: cell.copyWith(
                    color: st.ignored ? colors.textTertiary : null,
                  ),
                ),
              ),
              SizedBox(
                width: estW,
                child: Text(
                  st.throughputEstimateMbps == 0
                      ? '-'
                      : RaFormat.n(st.throughputEstimateMbps),
                  textAlign: TextAlign.right,
                  style: cell,
                ),
              ),
              SizedBox(
                width: roleW,
                child: Text(
                  roles.map(((String, String) e) => e.$1).join(' '),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cell.copyWith(color: colors.textAccent),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RaSectionLabel('What the radio has learned, per rate'),
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const RaNote('Updated every 50 ms.'),
          ],
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: mcsW,
                  child: Text('Rate', style: head),
                ),
                SizedBox(
                  width: rateW,
                  child: Text('Mbps', textAlign: TextAlign.right, style: head),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text('Success', style: head)),
                SizedBox(
                  width: pctW + estW,
                  child: Text(
                    'Est. Mbps',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                ),
                SizedBox(
                  width: roleW,
                  child: Text('Chain', textAlign: TextAlign.right, style: head),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (int m = RaLink.maxMcs; m >= 0; m--) row(engine.stats[m]),
          const SizedBox(height: AppSpacing.xs),
          // The presenter keeps one short key; the phone explains in full.
          if (presenting)
            const RaNote(
              'Updated every 50 ms. Chain: 1st and 2nd best throughput, P '
              'best probability, low lowest rate. Under 10% is ignored.',
            )
          else
            const RaNote(
              'Chain order: 1st = best throughput, 2nd = second-best '
              'throughput, P = best probability, low = lowest rate. Success is '
              'smoothed (EWMA). The estimate is success, capped at 90%, times '
              'bits over the time of one attempt; rates under 10% are ignored.',
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.color,
    required this.track,
    required this.muted,
  });

  final double value;
  final Color color;
  final Color track;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PresenterMode.scaleOf(context).markerSize(10),
      child: CustomPaint(
        painter: _BarPainter(
          value,
          muted ? color.withValues(alpha: 0.4) : color,
          track,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(bg, Paint()..color = track);
    final double w = size.width * value.clamp(0.0, 1.0);
    if (w <= 0) return;
    canvas.save();
    canvas.clipRRect(bg);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, size.height),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
