// The 3D field painter for the Wi-Fi Classroom "Polarization" tool
// (polarization).
//
// What it draws, in the shared orbit camera (wifi_lab_orbit.dart):
//   - the direction of travel: world x, from the source end to the front end,
//     with an arrowhead and a "Travel" label;
//   - [kArrowCount] field arrows from the axis, the resultant E at that point,
//     in lime, with the curve through their tips;
//   - optionally the horizontal and vertical component waves, thinner, in
//     their own hues, each labelled H or V in paint;
//   - an inset in the top corner, flat and face-on whatever the camera does:
//     the view from the front end looking back toward the source, with H and
//     V axes, the shape the tip traces (line, circle, ellipse) and the tip
//     now as a dot. In 3D that shape is edge-on from most angles, so it gets
//     its own square.
//
// World mapping: travel along +x; horizontal field along +y; vertical along
// +z. Two wavelengths are drawn. The world is kept small (the axis spans
// 2 units) because the shared camera's eye sits 5 units out: a small world
// keeps the perspective mild. Everything is recomputed per frame from a few
// hundred points, so no caching is needed.
//
// Presenter: strokes, arrowheads, dots and labels scale with
// PresenterMode.scaleOf (passed in as [scale]).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/polarization_model.dart';
import '../../../theme/app_gain_ramp.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'wifi_lab_orbit.dart';

/// Field arrows along the drawn two wavelengths (one every 1/16 wavelength).
const int kArrowCount = 33;

/// Wavelengths drawn along the axis.
const double kDrawnWavelengths = 2;

class PolarizationPainter extends CustomPainter {
  PolarizationPainter({
    required this.state,
    required this.phase,
    required this.view,
    required this.showComponents,
    required this.lead,
    required this.hHue,
    required this.vHue,
    required this.labelStyle,
    required this.fitView,
    this.scale = PresenterScale.normal,
  }) : super(repaint: view);

  /// The camera the scale is fitted to (the tool's opening view).
  final OrbitView fitView;

  final PolarizationState state;
  final double phase;
  final ValueNotifier<OrbitView> view;
  final bool showComponents;

  /// The resultant's color (lime).
  final Color lead;
  final Color hHue;
  final Color vHue;
  final TextStyle labelStyle;
  final PresenterScale scale;

  // World lengths.
  static const double _halfLen = 1.0; // the wave runs x = -1 .. 1
  static const double _amp = 0.56; // an amplitude of 1 draws this long

  static double _xAt(int i, int n) => -_halfLen + 2 * _halfLen * i / (n - 1);

  /// The camera for [size]. The scale is fitted once, to the wave's box as
  /// the OPENING camera sees it ([fitView]), then used for every angle: a
  /// drag turns the wave without rescaling it, and zoom stays the user's.
  Projector _camera(Size size) {
    final double shortSide = math.min(size.width, size.height);
    if (shortSide <= 0) return Projector(view.value, size);
    final Projector unit = Projector(fitView, const Size(2, 2), fit: 0.5);
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final double x in <double>[-_halfLen - 0.12, _halfLen + 0.3]) {
      for (final double y in <double>[-_amp, _amp]) {
        for (final double z in <double>[-_amp, _amp]) {
          final Offset o = unit.project(x, y, z);
          minX = math.min(minX, o.dx);
          maxX = math.max(maxX, o.dx);
          minY = math.min(minY, o.dy);
          maxY = math.max(maxY, o.dy);
        }
      }
    }
    // unit draws 1 world unit as 1 px; fill 96% of the width, 80% of the
    // height, whichever is tighter.
    final double px = math.min(
      0.96 * size.width / (maxX - minX),
      0.80 * size.height / (maxY - minY),
    );
    return Projector(view.value, size, fit: px / shortSide);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect inset = _insetRect(size);
    // The 3D is centered in the space left of and below the inset's corner.
    // On a narrow view (a phone) the inset would squeeze the wave, so the
    // wave keeps the full width and sits lower instead.
    final bool narrow = size.width < 520;
    final Size room = narrow
        ? Size(size.width, size.height - inset.height * 0.6)
        : Size(size.width - inset.width * 0.5, size.height);
    canvas.save();
    if (narrow) canvas.translate(0, inset.height * 0.6);
    final Projector cam = _camera(room);
    Offset p(double x, double y, double z) => cam.project(x, y, z);

    final double stroke = scale.strokeWidth(1);
    final Paint rule = Paint()
      ..color = AppGainRamp.viewportRuleStrong
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    // ── The travel axis ──────────────────────────────────────────────────
    final Offset a0 = p(-_halfLen - 0.12, 0, 0);
    final Offset a1 = p(_halfLen + 0.3, 0, 0);
    canvas.drawLine(a0, a1, rule..strokeWidth = scale.strokeWidth(1.5));
    _arrowHead(
      canvas,
      p(_halfLen + 0.15, 0, 0),
      a1,
      AppGainRamp.viewportRuleStrong,
      scale.markerSize(9),
    );
    // Right edge at the arrow tip, under the axis, so it never leaves the
    // fitted box.
    final TextPainter travel = _layout('Travel');
    travel.paint(
      canvas,
      Offset(a1.dx - travel.width, a1.dy + 6 * scale.marker),
    );

    if (!state.hasField) {
      canvas.restore();
      _inset(canvas, inset, null);
      return;
    }

    final int n = kArrowCount;
    final List<FieldVector> f = <FieldVector>[
      for (int i = 0; i < n; i++)
        state.fieldAt(kDrawnWavelengths * i / (n - 1), phase),
    ];
    // Distance along the axis in wavelengths runs with x, so the far (+x)
    // end is further along: it holds the field that left the source earlier.

    // ── Components (under the resultant) ─────────────────────────────────
    if (showComponents) {
      _component(canvas, cam, f, horizontal: true);
      _component(canvas, cam, f, horizontal: false);
    }

    // ── The resultant: arrows far to near, then the tip curve ────────────
    final Paint arrow = Paint()
      ..color = lead
      ..strokeWidth = scale.strokeWidth(2)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final List<int> order = List<int>.generate(n, (int i) => i)
      ..sort(
        (int a, int b) =>
            cam.depth(_xAt(a, n), 0, 0).compareTo(cam.depth(_xAt(b, n), 0, 0)),
      );
    for (final int i in order) {
      final double x = _xAt(i, n);
      final Offset base = p(x, 0, 0);
      final Offset tip = p(x, f[i].h * _amp, f[i].v * _amp);
      if ((tip - base).distance < 0.5) continue;
      canvas.drawLine(base, tip, arrow);
      _arrowHead(canvas, base, tip, lead, scale.markerSize(7));
    }
    final Path tips = Path();
    for (int i = 0; i < n; i++) {
      final Offset o = p(_xAt(i, n), f[i].h * _amp, f[i].v * _amp);
      i == 0 ? tips.moveTo(o.dx, o.dy) : tips.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      tips,
      Paint()
        ..color = lead.withValues(alpha: 0.55)
        ..strokeWidth = scale.strokeWidth(1.25)
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();
    _inset(canvas, inset, f[n - 1]);
  }

  /// The inset's square: the top-right corner, a fixed share of the view.
  Rect _insetRect(Size size) {
    final double side = math.min(size.height * 0.36, size.width * 0.34);
    final double m = 10 * scale.marker;
    return Rect.fromLTWH(size.width - side - m, m, side, side);
  }

  /// The face-on view from the front end, looking back toward the source:
  /// +H to the right, +V up (the side the 3D camera shows them on at its
  /// opening angle). [tip] is the field at the front end now, or null when
  /// there is no field.
  void _inset(Canvas canvas, Rect r, FieldVector? tip) {
    final Paint edge = Paint()
      ..color = AppGainRamp.viewportRuleStrong
      ..strokeWidth = scale.strokeWidth(1)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(r, Paint()..color = AppGainRamp.viewport);
    canvas.drawRect(r, edge);
    // The title wraps inside the square rather than clipping (phone widths).
    final TextPainter title = TextPainter(
      text: TextSpan(text: 'End-on view', style: labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: math.max(1, r.width - 6 * scale.marker));
    final double top = r.top + 4 * scale.marker + title.height;
    title.paint(
      canvas,
      Offset(r.left + (r.width - title.width) / 2, r.top + 3 * scale.marker),
    );
    // The plot area under the title.
    final Rect plot = Rect.fromLTRB(
      r.left + 8 * scale.marker,
      top + 2 * scale.marker,
      r.right - 8 * scale.marker,
      r.bottom - 8 * scale.marker,
    );
    final Offset c = plot.center;
    final double half = math.min(plot.width, plot.height) / 2;
    final double rad = half * 0.82;
    final Paint axis = Paint()
      ..color = AppGainRamp.viewportRule
      ..strokeWidth = scale.strokeWidth(1)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(c - Offset(half, 0), c + Offset(half, 0), axis);
    canvas.drawLine(c - Offset(0, half), c + Offset(0, half), axis);
    final TextPainter hl = _layout('H');
    hl.paint(canvas, c + Offset(half - hl.width, 2 * scale.marker));
    final TextPainter vl = _layout('V');
    vl.paint(canvas, c + Offset(3 * scale.marker, -half));
    if (tip == null) return;

    Offset at(FieldVector v) => c + Offset(v.h * rad, -v.v * rad);
    final Path trace = Path();
    const int m = 96;
    for (int k = 0; k <= m; k++) {
      final Offset o = at(
        state.fieldAt(kDrawnWavelengths, 2 * math.pi * k / m),
      );
      k == 0 ? trace.moveTo(o.dx, o.dy) : trace.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      trace,
      Paint()
        ..color = lead.withValues(alpha: 0.6)
        ..strokeWidth = scale.strokeWidth(2)
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    if (showComponents) {
      canvas.drawCircle(
        c + Offset(tip.h * rad, 0),
        scale.markerSize(3.5),
        Paint()..color = hHue,
      );
      canvas.drawCircle(
        c + Offset(0, -tip.v * rad),
        scale.markerSize(3.5),
        Paint()..color = vHue,
      );
    }
    final Offset t = at(tip);
    if ((t - c).distance > 0.5) {
      canvas.drawLine(
        c,
        t,
        Paint()
          ..color = lead
          ..strokeWidth = scale.strokeWidth(2.5)
          ..strokeCap = StrokeCap.round,
      );
      _arrowHead(canvas, c, t, lead, scale.markerSize(8));
    }
    canvas.drawCircle(t, scale.markerSize(3), Paint()..color = lead);
  }

  void _component(
    Canvas canvas,
    Projector cam,
    List<FieldVector> f, {
    required bool horizontal,
  }) {
    final int n = f.length;
    final Color hue = horizontal ? hHue : vHue;
    final Path curve = Path();
    for (int i = 0; i < n; i++) {
      final double x = _xAt(i, n);
      final double a = (horizontal ? f[i].h : f[i].v) * _amp;
      final Offset tip = horizontal
          ? cam.project(x, a, 0)
          : cam.project(x, 0, a);
      i == 0 ? curve.moveTo(tip.dx, tip.dy) : curve.lineTo(tip.dx, tip.dy);
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = hue
        ..strokeWidth = scale.strokeWidth(1.5)
        ..style = PaintingStyle.stroke,
    );
    // The letter at the source end, where the curve starts.
    final Offset start = horizontal
        ? cam.project(-_halfLen, (f.first.h) * _amp, 0)
        : cam.project(-_halfLen, 0, (f.first.v) * _amp);
    _label(
      canvas,
      horizontal ? 'H' : 'V',
      start,
      const Offset(-14, -8),
      color: hue,
    );
  }

  void _arrowHead(Canvas c, Offset from, Offset to, Color color, double len) {
    final Offset d = to - from;
    final double dist = d.distance;
    if (dist < 1) return;
    final double l = math.min(len, dist * 0.45);
    final Offset u = d / dist;
    final Offset nrm = Offset(-u.dy, u.dx);
    final Path head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - u.dx * l + nrm.dx * l * 0.45,
        to.dy - u.dy * l + nrm.dy * l * 0.45,
      )
      ..lineTo(
        to.dx - u.dx * l - nrm.dx * l * 0.45,
        to.dy - u.dy * l - nrm.dy * l * 0.45,
      )
      ..close();
    c.drawPath(head, Paint()..color = color);
  }

  TextPainter _layout(String text, {Color? color}) => TextPainter(
    text: TextSpan(
      text: text,
      style: color == null ? labelStyle : labelStyle.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _label(Canvas c, String text, Offset at, Offset nudge, {Color? color}) {
    final TextPainter tp = _layout(text, color: color);
    final Offset o = at + nudge * scale.text;
    tp.paint(c, Offset(o.dx, o.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(PolarizationPainter old) =>
      old.state != state ||
      old.phase != phase ||
      old.view != view ||
      old.showComponents != showComponents ||
      old.lead != lead ||
      old.labelStyle != labelStyle ||
      old.scale != scale;
}
