// SpatialReuseStage: what the student watches in the Spatial Reuse tool.
//
// Three stacked drawings over one SpatialReuseState:
//   1. The line: AP A, client A, client B and AP B at their distances, each
//      BSS in its own hue with its BSS color number, AP transmit power above
//      each AP and each client's SINR below it. Drag a radio to move it.
//   2. The meter: the level AP B hears from AP A on a dBm scale, against
//      -82 (preamble detect), -62 (energy detect) and the OBSS_PD threshold.
//   3. The timeline: do the two frames go one after the other, or together?
// It knows nothing about the controls, so a screen can stack it above them
// (phone), beside them (desktop) or full screen (the presenter layout,
// spec 00). No waves are drawn, so nothing here can imply a frequency.
//
// COLOR (GL-003 §8.15.2): each BSS gets one hue from the Wi-Fi Lab family in
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
      builder: (BuildContext context, Widget? _) => _build(context),
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
        label: _semantics(a),
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

  String _semantics(ReuseAnalysis a) {
    final ReuseScenario s = a.scenario;
    String db(double v) => v.toStringAsFixed(1);
    return 'Line of four radios. AP A at ${db(s.layout.apA)} metres, client A '
        'at ${db(s.layout.clientA)}, client B at ${db(s.layout.clientB)}, '
        'AP B at ${db(s.layout.apB)}. '
        '${s.coloring ? 'BSS A color ${s.colorA}, BSS B color ${s.colorB}. ' : 'BSS coloring off. '}'
        'AP B hears AP A at ${db(a.heardByBDbm)} dBm. '
        '${a.together ? 'AP B sends at the same time at ${db(a.txPowerBDbm)} dBm.' : 'AP B waits its turn.'} '
        'Client A SINR ${db(a.linkA.sinrDb)} dB, client B SINR '
        '${db(a.linkB.sinrDb)} dB. '
        '${a.frameTimes} frame-time${a.frameTimes == 1 ? '' : 's'} for both frames.';
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
  const _LineGestures({required this.state, required this.child});

  final SpatialReuseState state;
  final Widget child;

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
        final double w = c.maxWidth;
        double toM(double x) =>
            (x - _kLinePad) / (w - 2 * _kLinePad) * kReuseLineM;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails d) =>
              _drag = _hit(d.localPosition, w),
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
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook lookA, lookB;

  static const double height = 156;
  static const double apY = 50;
  static const double clientY = 86;
  static const double axisY = 132;

  @override
  void paint(Canvas canvas, Size size) {
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
    final List<(double, String, TextStyle)>
    bottom = <(double, String, TextStyle)>[
      (xca, 'SINR ${analysis.linkA.sinrDb.toStringAsFixed(1)}', style.label),
      (xcb, 'SINR ${analysis.linkB.sinrDb.toStringAsFixed(1)}', style.label),
    ];
    _row(canvas, bottom, clientY + 14, w);
  }

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
      final int line = left >= right[0] + AppSpacing.xxs ? 0 : 1;
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
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook sender;

  static const double height = 84;
  static const double _barTop = 30;
  static const double _barH = 14;

  @override
  void paint(Canvas canvas, Size size) {
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
  });

  final ReuseAnalysis analysis;
  final _Style style;
  final BssLook lookA, lookB;

  static const double height = 88;
  static const double _laneH = 24;
  static const double _gap = AppSpacing.xxs;
  static const double _labelW = 52;

  @override
  void paint(Canvas canvas, Size size) {
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
      old.analysis != analysis ||
      old.style.neutral != style.neutral ||
      old.lookA.hue != lookA.hue ||
      old.lookB.hue != lookB.hue;
}
