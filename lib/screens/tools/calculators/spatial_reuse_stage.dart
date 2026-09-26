// SpatialReuseStage: what the student watches in the Spatial Reuse tool.
//
// Three stacked drawings over one SpatialReuseState:
//   1. The line: AP A, client A, client B and AP B at their distances, each
//      BSS in its own hue with its BSS color number, AP transmit power above
//      each AP and each client's SINR and best MCS below it. Drag a radio to move it.
//   2. The meter: the level AP B hears from AP A on a dBm scale, against
//      -82 (preamble detect), -62 (energy detect) and the OBSS_PD threshold.
//   3. The timeline: do the two frames go one after the other, or together?
// It knows nothing about the controls, so a screen can stack it above them
// (phone), beside them (desktop) or full screen (the presenter layout,
// spec 00). No waves are drawn, so nothing here can imply a frequency.
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box with no
// scroll. The decision and its numbers move onto the stage above the three
// drawings (what the room is asked to predict), the drawings are zoomed as
// one piece to fill the height (strokes and labels included, never below
// the presenter text scale), and the two links sit side by side below them
// with their SINR, best MCS and verdict.
//
// COLOR (GL-003 §8.15.2): each BSS gets one hue from the Wi-Fi Classroom family in
// lib/theme/wifi_lab_client_palette.dart (BSS A the blue, BSS B the violet),
// always beside its name and color number, never color alone. The hue shows
// what AP B can tell apart: with coloring off both BSSs are drawn neutral,
// and with the same color number both take BSS A's hue. Lime marks the
// OBSS_PD threshold, the one quantity the student moves.
//
// INTERACTION: drag a radio along the line. The keyboard and screen-reader
// path is the four position sliders in the controls. No motion, so reduced
// motion needs nothing (§8.8).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/spatial_reuse_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'spatial_reuse_panels.dart';
import 'spatial_reuse_state.dart';

/// Palette slots for the two BSSs: blue and violet, both cool, so neither
/// reads as a §8.13 status hue.
const int _kHueA = 5;
const int _kHueB = 7;

/// Horizontal room left and right of the line for edge labels.
const double _kLinePad = 36;

/// The meter's dBm range, per 20 MHz.
const double _kMeterMin = -100;
const double _kMeterMax = -40;

/// How one BSS is drawn at this moment.
class BssLook {
  const BssLook({required this.hue, required this.onHue, required this.tag});

  final Color hue;
  final Color onHue;

  /// `BSS A, color 6`, or `BSS A, no color`.
  final String tag;

  static BssLook of(
    BuildContext context,
    ReuseScenario s, {
    required bool bssA,
  }) {
    final AppColorScheme colors = context.colors;
    final String name = bssA ? 'BSS A' : 'BSS B';
    if (!s.coloring) {
      return BssLook(
        hue: colors.textSecondary,
        onHue: colors.surface1,
        tag: '$name, no color',
      );
    }
    final bool clash = s.colorA == s.colorB;
    final WifiLabClientStyle st = WifiLabClientPalette.of(
      bssA || clash ? _kHueA : _kHueB,
      colors,
    );
    return BssLook(
      hue: st.hue,
      onHue: st.onHue,
      tag: '$name, color ${bssA ? s.colorA : s.colorB}',
    );
  }
}

class SpatialReuseStage extends StatelessWidget {
  const SpatialReuseStage({super.key, required this.state});

  final SpatialReuseState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) =>
          PresenterMode.isActive(context)
          ? _PresenterStage(state: state)
          : _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ReuseAnalysis a = state.analysis;
    final ReuseScenario s = state.scenario;
    final _Style st = _Style.of(context);
    final BssLook lookA = BssLook.of(context, s, bssA: true);
    final BssLook lookB = BssLook.of(context, s, bssA: false);
    TextStyle caption() =>
        text.bodySmall!.copyWith(color: colors.textSecondary);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Semantics(
        label: semanticsOf(a),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'AP A is sending to client A. AP B has a frame for client B: '
              'wait, or send now? Drag a radio to move it.',
              style: caption(),
            ),
            const SizedBox(height: AppSpacing.xxs),
            _LineGestures(
              state: state,
              child: CustomPaint(
                size: const Size.fromHeight(_LinePainter.height),
                painter: _LinePainter(
                  analysis: a,
                  style: st,
                  lookA: lookA,
                  lookB: lookB,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'What AP B hears from AP A, dBm per 20 MHz',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
            CustomPaint(
              size: const Size.fromHeight(_MeterPainter.height),
              painter: _MeterPainter(analysis: a, style: st, sender: lookA),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Airtime, one frame each',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            CustomPaint(
              size: const Size.fromHeight(_TimelinePainter.height),
              painter: _TimelinePainter(
                analysis: a,
                style: st,
                lookA: lookA,
                lookB: lookB,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The worded description of the whole stage for screen readers.
  static String semanticsOf(ReuseAnalysis a) {
    final ReuseScenario s = a.scenario;
    String db(double v) => v.toStringAsFixed(1);
    return 'Line of four radios. AP A at ${db(s.layout.apA)} metres, client A '
        'at ${db(s.layout.clientA)}, client B at ${db(s.layout.clientB)}, '
        'AP B at ${db(s.layout.apB)}. '
        '${s.coloring ? 'BSS A color ${s.colorA}, BSS B color ${s.colorB}. ' : 'BSS coloring off. '}'
        'AP B hears AP A at ${db(a.heardByBDbm)} dBm. '
        '${a.together ? 'AP B sends at the same time at ${db(a.txPowerBDbm)} dBm.' : 'AP B waits its turn.'} '
        'Client A SINR ${db(a.linkA.sinrDb)} dB, '
        '${a.linkA.bestMcs == null ? 'no MCS' : 'up to MCS ${a.linkA.bestMcs}'}; '
        'client B SINR '
        '${db(a.linkB.sinrDb)} dB, '
        '${a.linkB.bestMcs == null ? 'no MCS' : 'up to MCS ${a.linkB.bestMcs}'}. '
        '${a.frameTimes} frame-time${a.frameTimes == 1 ? '' : 's'} for both frames.';
  }
}

// ── Presenter arrangement ─────────────────────────────────────────────────

/// Drawing heights at zoom 1: line, meter, timeline.
const double _kDrawingsHeight =
    _LinePainter.height + _MeterPainter.height + _TimelinePainter.height;

/// Narrowest the line may be, in its own (unzoomed) units, before its labels
/// crowd: the zoom stops where the drawing would get narrower than this.
const double _kMinLineWidth = 440;

/// The largest zoom worth drawing; past it the labels outgrow the room.
const double _kMaxZoom = 2.4;

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.state});

  final SpatialReuseState state;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final ReuseAnalysis a = state.analysis;
    final ReuseScenario s = state.scenario;
    final _Style st = _Style.of(context);
    final BssLook lookA = BssLook.of(context, s, bssA: true);
    final BssLook lookB = BssLook.of(context, s, bssA: false);
    String db(double v) => v.toStringAsFixed(1);

    Widget stat(String label, String value, {bool accent = false}) =>
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Text(
                value,
                style: scale
                    .headlineStyle(mono.outputMedium)
                    .copyWith(
                      color: accent ? colors.textAccent : colors.textPrimary,
                    ),
              ),
            ],
          ),
        );

    Widget link(String name, ReuseLink k, BssLook look) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Container(
                    width: AppSpacing.sm,
                    height: AppSpacing.sm,
                    decoration: BoxDecoration(
                      color: look.hue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                stat('SINR', '${db(k.sinrDb)} dB'),
                stat(
                  'Best MCS',
                  k.bestMcs == null ? 'none' : 'MCS ${k.bestMcs}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            ReuseVerdict(link: k, style: text.bodyMedium, compact: true),
          ],
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              reuseHeadline(a),
              style: scale
                  .headlineStyle(text.headlineSmall ?? text.titleLarge!)
                  .copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            reuseWhy(a),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              stat('AP B hears AP A', '${db(a.heardByBDbm)} dBm'),
              stat('AP B transmit power', '${db(a.txPowerBDbm)} dBm'),
              stat(
                'Airtime, one frame each',
                '${a.frameTimes} frame-time${a.frameTimes == 1 ? '' : 's'}',
                accent: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: Semantics(
              label: SpatialReuseStage.semanticsOf(a),
              excludeSemantics: true,
              child: _ZoomedDrawings(
                state: state,
                analysis: a,
                style: st,
                lookA: lookA,
                lookB: lookB,
                minZoom: scale.text,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              link('Link A: AP A to client A', a.linkA, lookA),
              const SizedBox(width: AppSpacing.sm),
              link('Link B: AP B to client B', a.linkB, lookB),
            ],
          ),
        ],
      ),
    );
  }
}

/// The line, the meter and the timeline, zoomed as one to fill the box.
class _ZoomedDrawings extends StatelessWidget {
  const _ZoomedDrawings({
    required this.state,
    required this.analysis,
    required this.style,
    required this.lookA,
    required this.lookB,
    required this.minZoom,
  });

  final SpatialReuseState state;
  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook lookA, lookB;

  /// The presenter text scale: the drawings never get smaller than it.
  final double minZoom;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? label = text.labelSmall?.copyWith(
      color: colors.textTertiary,
    );
    // Measured, not estimated: the two captions are laid out exactly as
    // the Text widgets below will lay them out.
    final TextPainter probe = TextPainter(
      text: TextSpan(text: 'Airtime', style: label),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double labelH = probe.height;
    probe.dispose();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // Two caption lines and three gaps sit between the drawings.
        const double gaps = AppSpacing.xs * 2 + AppSpacing.xxs;
        // A pixel of slack for rounding in the painted heights.
        final double room = box.maxHeight - 2 * labelH - gaps - 1;
        final double zoom = math.max(
          1.0,
          math.min(
            math.min(room / _kDrawingsHeight, box.maxWidth / _kMinLineWidth),
            math.max(minZoom, _kMaxZoom),
          ),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LineGestures(
              state: state,
              zoom: zoom,
              child: CustomPaint(
                size: Size.fromHeight(_LinePainter.height * zoom),
                painter: _LinePainter(
                  analysis: analysis,
                  style: style,
                  lookA: lookA,
                  lookB: lookB,
                  zoom: zoom,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('What AP B hears from AP A, dBm per 20 MHz', style: label),
            CustomPaint(
              size: Size.fromHeight(_MeterPainter.height * zoom),
              painter: _MeterPainter(
                analysis: analysis,
                style: style,
                sender: lookA,
                zoom: zoom,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Airtime, one frame each', style: label),
            const SizedBox(height: AppSpacing.xxs),
            CustomPaint(
              size: Size.fromHeight(_TimelinePainter.height * zoom),
              painter: _TimelinePainter(
                analysis: analysis,
                style: style,
                lookA: lookA,
                lookB: lookB,
                zoom: zoom,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Shared style ──────────────────────────────────────────────────────────

class _Style {
  const _Style({
    required this.track,
    required this.tick,
    required this.neutral,
    required this.accent,
    required this.zone,
    required this.label,
    required this.strong,
    required this.surface,
  });

  final Color track, tick, neutral, accent, zone, surface;
  final TextStyle label, strong;

  factory _Style.of(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle small = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
    );
    return _Style(
      track: colors.borderStrong,
      tick: colors.border,
      neutral: colors.textSecondary,
      accent: colors.textAccent,
      zone: colors.surface3,
      surface: colors.surface1,
      label: small.copyWith(color: colors.textSecondary),
      strong: small.copyWith(color: colors.textPrimary),
    );
  }
}

TextPainter _tp(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout();

/// Paint [tp] centered on [x], held inside [0, width].
void _paintCentered(
  Canvas c,
  TextPainter tp,
  double x,
  double y,
  double width,
) {
  final double left = (x - tp.width / 2).clamp(
    0.0,
    math.max(0.0, width - tp.width),
  );
  tp.paint(c, Offset(left, y));
}

/// X pixel for [metres] on the line.
double _lineX(double metres, double width) =>
    _kLinePad + (width - 2 * _kLinePad) * metres / kReuseLineM;

// ── Gestures ──────────────────────────────────────────────────────────────

class _LineGestures extends StatefulWidget {
  const _LineGestures({
    required this.state,
    required this.child,
    this.zoom = 1,
  });

  final SpatialReuseState state;
  final Widget child;

  /// The line painter's zoom, so a touch maps back to its coordinates.
  final double zoom;

  @override
  State<_LineGestures> createState() => _LineGesturesState();
}

class _LineGesturesState extends State<_LineGestures> {
  ReuseNode? _drag;

  ReuseNode? _hit(Offset p, double width) {
    ReuseNode? best;
    double bestD = AppSpacing.minTouchTarget / 2 + AppSpacing.xxs;
    for (final ReuseNode n in ReuseNode.values) {
      final double x = _lineX(widget.state.position(n), width);
      final double y = n.isAp ? _LinePainter.apY : _LinePainter.clientY;
      final double d = (Offset(x, y) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double z = widget.zoom;
        final double w = c.maxWidth / z;
        double toM(double x) =>
            (x / z - _kLinePad) / (w - 2 * _kLinePad) * kReuseLineM;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails d) =>
              _drag = _hit(d.localPosition / z, w),
          onHorizontalDragUpdate: (DragUpdateDetails d) {
            final ReuseNode? n = _drag;
            if (n != null) widget.state.move(n, toM(d.localPosition.dx));
          },
          onHorizontalDragEnd: (_) => _drag = null,
          onHorizontalDragCancel: () => _drag = null,
          child: widget.child,
        );
      },
    );
  }
}

// ── The line ──────────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.analysis,
    required this.style,
    required this.lookA,
    required this.lookB,
    this.zoom = 1,
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook lookA, lookB;

  /// Presenter zoom: the whole drawing, strokes and labels included, is
  /// scaled by this (1 on the phone and desktop layouts).
  final double zoom;

  static const double height = 156;
  static const double apY = 50;
  static const double clientY = 86;
  static const double axisY = 132;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(zoom);
    _paint(canvas, size / zoom);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    final double w = size.width;
    final ReuseLayout l = analysis.scenario.layout;
    final double xa = _lineX(l.apA, w);
    final double xca = _lineX(l.clientA, w);
    final double xcb = _lineX(l.clientB, w);
    final double xb = _lineX(l.apB, w);

    // Axis with a tick every 10 m.
    final Paint axis = Paint()
      ..color = style.track
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_lineX(0, w), axisY),
      Offset(_lineX(kReuseLineM, w), axisY),
      axis,
    );
    for (int m = 0; m <= kReuseLineM; m += 10) {
      final double x = _lineX(m.toDouble(), w);
      canvas.drawLine(Offset(x, axisY - 3), Offset(x, axisY + 3), axis);
      _paintCentered(
        canvas,
        _tp(m == 0 ? '0 m' : '$m', style.label),
        x,
        axisY + 5,
        w,
      );
    }

    // Wanted links: AP to its own client. BSS B's is dashed while it waits.
    _link(
      canvas,
      Offset(xa, apY),
      Offset(xca, clientY),
      lookA.hue,
      dashed: false,
    );
    _link(
      canvas,
      Offset(xb, apY),
      Offset(xcb, clientY),
      lookB.hue,
      dashed: !analysis.together,
    );

    // Clients first, APs on top.
    _client(canvas, xca, lookA, 'a');
    _client(canvas, xcb, lookB, 'b');
    _ap(canvas, xa, lookA, 'A');
    _ap(canvas, xb, lookB, 'B');

    // AP labels above, client SINR below. Labels that would overlap drop to
    // a second line.
    final double tx = analysis.txPowerBDbm;
    final List<(double, String, TextStyle)> top = <(double, String, TextStyle)>[
      (
        xa,
        '${lookA.tag}, AP ${analysis.scenario.apPowerDbm.toStringAsFixed(0)} dBm',
        style.strong,
      ),
      (xb, '${lookB.tag}, AP ${tx.toStringAsFixed(0)} dBm', style.strong),
    ];
    _row(canvas, top, 0, w);
    final List<(double, String, TextStyle)> bottom =
        <(double, String, TextStyle)>[
          (xca, _clientLabel(analysis.linkA), style.label),
          (xcb, _clientLabel(analysis.linkB), style.label),
        ];
    _row(canvas, bottom, clientY + 14, w);
  }

  /// `SINR 26.7, MCS 4`, or `SINR 9.0, no MCS`.
  static String _clientLabel(ReuseLink k) =>
      'SINR ${k.sinrDb.toStringAsFixed(1)}, '
      '${k.bestMcs == null ? 'no MCS' : 'MCS ${k.bestMcs}'}';

  /// Paint labels at [y], left to right. A label that would overlap the one
  /// before it drops to a second line.
  void _row(
    Canvas canvas,
    List<(double, String, TextStyle)> items,
    double y,
    double w,
  ) {
    final List<(double, TextPainter)> sorted =
        <(double, TextPainter)>[
          for (final (double x, String s, TextStyle ts) in items)
            (x, _tp(s, ts)),
        ]..sort(
          ((double, TextPainter) p, (double, TextPainter) q) =>
              p.$1.compareTo(q.$1),
        );
    final List<double> right = <double>[
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    for (final (double x, TextPainter tp) in sorted) {
      final double left = (x - tp.width / 2).clamp(
        0.0,
        math.max(0.0, w - tp.width),
      );
      final int line = left >= right[0] + AppSpacing.sm ? 0 : 1;
      tp.paint(canvas, Offset(left, y + line * (tp.height + 1)));
      right[line] = left + tp.width;
    }
  }

  void _link(
    Canvas canvas,
    Offset a,
    Offset b,
    Color c, {
    required bool dashed,
  }) {
    final Paint p = Paint()
      ..color = c
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(a, b, p);
      return;
    }
    final double len = (b - a).distance;
    if (len == 0) return;
    final Offset dir = (b - a) / len;
    for (double t = 0; t < len; t += 8) {
      canvas.drawLine(a + dir * t, a + dir * math.min(len, t + 4), p);
    }
  }

  void _ap(Canvas canvas, double x, BssLook look, String glyph) {
    final Rect r = Rect.fromCenter(
      center: Offset(x, apY),
      width: 30,
      height: 26,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(AppRadius.control)),
      Paint()..color = look.hue,
    );
    final TextPainter tp = _tp(
      glyph,
      style.strong.copyWith(color: look.onHue, fontWeight: FontWeight.w700),
    );
    tp.paint(canvas, Offset(x - tp.width / 2, apY - tp.height / 2));
  }

  void _client(Canvas canvas, double x, BssLook look, String glyph) {
    canvas.drawCircle(Offset(x, clientY), 12, Paint()..color = style.surface);
    canvas.drawCircle(
      Offset(x, clientY),
      11,
      Paint()
        ..color = look.hue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final TextPainter tp = _tp(
      glyph,
      style.strong.copyWith(color: look.hue, fontWeight: FontWeight.w700),
    );
    tp.paint(canvas, Offset(x - tp.width / 2, clientY - tp.height / 2));
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.zoom != zoom ||
      old.analysis != analysis ||
      old.style.neutral != style.neutral ||
      old.lookA.hue != lookA.hue ||
      old.lookB.hue != lookB.hue;
}

// ── The meter ─────────────────────────────────────────────────────────────

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.analysis,
    required this.style,
    required this.sender,
    this.zoom = 1,
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook sender;
  final double zoom;

  static const double height = 84;
  static const double _barTop = 30;
  static const double _barH = 14;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(zoom);
    _paint(canvas, size / zoom);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    final double w = size.width;
    const double pad = AppSpacing.xs;
    double x(double dbm) =>
        pad +
        (w - 2 * pad) *
            (dbm.clamp(_kMeterMin, _kMeterMax) - _kMeterMin) /
            (_kMeterMax - _kMeterMin);
    final ReuseScenario s = analysis.scenario;
    final bool showPd = s.coloring && s.colorA != s.colorB;
    final double pd = clampObssPd(s.obssPdDbm);

    // Track, with the band AP B may ignore under OBSS_PD shaded and hatched.
    final Rect track = Rect.fromLTWH(pad, _barTop, w - 2 * pad, _barH);
    canvas.drawRect(track, Paint()..color = style.zone);
    if (showPd && pd > kObssPdMinDbm) {
      final Rect ignore = Rect.fromLTRB(
        x(kObssPdMinDbm),
        _barTop,
        x(pd),
        _barTop + _barH,
      );
      canvas.save();
      canvas.clipRect(ignore);
      final Paint hatch = Paint()
        ..color = style.accent
        ..strokeWidth = 1;
      for (double hx = ignore.left - _barH; hx < ignore.right; hx += 5) {
        canvas.drawLine(
          Offset(hx, _barTop + _barH),
          Offset(hx + _barH, _barTop),
          hatch,
        );
      }
      canvas.restore();
    }
    canvas.drawRect(
      track,
      Paint()
        ..color = style.track
        ..style = PaintingStyle.stroke,
    );

    // Scale.
    for (double d = _kMeterMin; d <= _kMeterMax; d += 10) {
      canvas.drawLine(
        Offset(x(d), _barTop + _barH),
        Offset(x(d), _barTop + _barH + 3),
        Paint()..color = style.track,
      );
    }
    _paintCentered(
      canvas,
      _tp('${_kMeterMin.round()}', style.label),
      x(_kMeterMin) + 10,
      _barTop + _barH + 4,
      w,
    );
    _paintCentered(
      canvas,
      _tp('${_kMeterMax.round()}', style.label),
      x(_kMeterMax) - 10,
      _barTop + _barH + 4,
      w,
    );

    // Fixed thresholds below the bar, OBSS_PD in lime on its own line.
    void mark(
      double dbm,
      String label,
      Color c,
      double labelY, {
      double stroke = 1.5,
    }) {
      canvas.drawLine(
        Offset(x(dbm), _barTop - 3),
        Offset(x(dbm), _barTop + _barH + 3),
        Paint()
          ..color = c
          ..strokeWidth = stroke,
      );
      _paintCentered(
        canvas,
        _tp(label, style.label.copyWith(color: c)),
        x(dbm),
        labelY,
        w,
      );
    }

    const double row1 = _barTop + _barH + 4;
    mark(kPreambleDetectDbm, 'PD -82', style.neutral, row1);
    mark(kEnergyDetectDbm, 'ED -62', style.neutral, row1);
    if (showPd) {
      mark(
        pd,
        'OBSS_PD ${pd.toStringAsFixed(0)}',
        style.accent,
        row1 + 17,
        stroke: 2.5,
      );
    }

    // The level AP B hears: a triangle above the bar in the sender's hue.
    final double lx = x(analysis.heardByBDbm);
    final Path tri = Path()
      ..moveTo(lx, _barTop - 1)
      ..lineTo(lx - 6, _barTop - 11)
      ..lineTo(lx + 6, _barTop - 11)
      ..close();
    canvas.drawPath(tri, Paint()..color = sender.hue);
    final String off = analysis.heardByBDbm < _kMeterMin
        ? ' (below scale)'
        : analysis.heardByBDbm > _kMeterMax
        ? ' (above scale)'
        : '';
    _paintCentered(
      canvas,
      _tp('${analysis.heardByBDbm.toStringAsFixed(1)} dBm$off', style.strong),
      lx,
      0,
      w,
    );
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.zoom != zoom ||
      old.analysis != analysis ||
      old.style.neutral != style.neutral ||
      old.sender.hue != sender.hue;
}

// ── The timeline ──────────────────────────────────────────────────────────

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.analysis,
    required this.style,
    required this.lookA,
    required this.lookB,
    this.zoom = 1,
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook lookA, lookB;
  final double zoom;

  static const double height = 88;
  static const double _laneH = 24;
  static const double _gap = AppSpacing.xxs;
  static const double _labelW = 52;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(zoom);
    _paint(canvas, size / zoom);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double x0 = _labelW;
    final double unit = (w - x0 - AppSpacing.xxs) / 2;
    double laneTop(int i) => i * (_laneH + _gap);

    for (int i = 0; i < 2; i++) {
      final TextPainter tp = _tp(i == 0 ? 'BSS A' : 'BSS B', style.label);
      tp.paint(canvas, Offset(0, laneTop(i) + (_laneH - tp.height) / 2));
      canvas.drawRect(
        Rect.fromLTWH(x0, laneTop(i), unit * 2, _laneH),
        Paint()..color = style.zone,
      );
    }

    void bar(
      int lane,
      double from,
      String label,
      BssLook look, {
      String? short,
    }) {
      final Rect r = Rect.fromLTWH(
        x0 + from * unit + 1,
        laneTop(lane) + 1,
        unit - 2,
        _laneH - 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(AppSpacing.xxs)),
        Paint()..color = look.hue,
      );
      final TextStyle on = style.strong.copyWith(color: look.onHue);
      TextPainter tp = _tp(label, on);
      if (tp.width >= r.width - 4 && short != null) tp = _tp(short, on);
      if (tp.width < r.width - 4) {
        tp.paint(
          canvas,
          Offset(
            r.left + (r.width - tp.width) / 2,
            r.top + (r.height - tp.height) / 2,
          ),
        );
      }
    }

    bar(0, 0, 'to client a', lookA);
    if (analysis.together) {
      bar(
        1,
        0,
        'to client b, ${analysis.txPowerBDbm.toStringAsFixed(0)} dBm',
        lookB,
        short: 'b, ${analysis.txPowerBDbm.toStringAsFixed(0)} dBm',
      );
    } else {
      // Waiting: hatched neutral while AP A holds the air.
      final Rect wait = Rect.fromLTWH(
        x0 + 1,
        laneTop(1) + 1,
        unit - 2,
        _laneH - 2,
      );
      canvas.save();
      canvas.clipRect(wait);
      final Paint hatch = Paint()
        ..color = style.neutral
        ..strokeWidth = 1;
      for (double hx = wait.left - _laneH; hx < wait.right; hx += 6) {
        canvas.drawLine(
          Offset(hx, wait.bottom),
          Offset(hx + _laneH, wait.top),
          hatch,
        );
      }
      canvas.restore();
      final TextPainter tp = _tp('waits', style.strong);
      canvas.drawRect(
        Rect.fromCenter(
          center: wait.center,
          width: tp.width + 8,
          height: tp.height,
        ),
        Paint()..color = style.zone,
      );
      tp.paint(canvas, wait.center - Offset(tp.width / 2, tp.height / 2));
      bar(1, 1, 'to client b', lookB);
    }

    // Axis in frame-times.
    final double ay = laneTop(2);
    final Paint axis = Paint()..color = style.track;
    canvas.drawLine(Offset(x0, ay), Offset(x0 + 2 * unit, ay), axis);
    for (int t = 0; t <= 2; t++) {
      final double x = x0 + t * unit;
      canvas.drawLine(Offset(x, ay), Offset(x, ay + 3), axis);
    }
    final String total = analysis.together
        ? 'Together: 1 frame-time for both'
        : 'In turn: 2 frame-times for both';
    final TextPainter tp = _tp(total, style.strong);
    tp.paint(canvas, Offset(x0, ay + 6));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.zoom != zoom ||
      old.analysis != analysis ||
      old.style.neutral != style.neutral ||
      old.lookA.hue != lookA.hue ||
      old.lookB.hue != lookB.hue;
}
