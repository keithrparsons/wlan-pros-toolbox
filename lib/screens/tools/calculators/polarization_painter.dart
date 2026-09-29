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
// keeps the perspective mild. The drawing is recomputed per frame from a few
// hundred points; only the fit (see _camera) is kept between frames, because
// it does not change with the phase.
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
    this.scale = PresenterScale.normal,
  }) : super(repaint: view);

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

  /// The camera for [size], fitted to what this frame actually draws, seen
  /// from the CURRENT orbit (spec 45 line 49; Vera gate B, 2026-09-29): the
  /// travel axis and its arrowhead, the ellipse the field tip traces (the
  /// same at every point on the axis), the field arrows, the H and V
  /// component extremes when they are shown, and the painted labels, which
  /// keep their pixel size. The fit covers a whole cycle, so the scale does
  /// not breathe as the wave plays; it follows the orbit, so every angle
  /// fills the viewport with nothing clipped.
  ///
  /// The whole viewport is the room, less a small margin, and nothing may run
  /// under the End-on view [inset]: the drawing is tried centered, bottom
  /// center, bottom left and middle left, each at the largest scale that fits and clears
  /// the inset, and the largest wins (centered unless another is clearly
  /// larger). Zoom stays the user's, applied after the fit about the
  /// drawing's center.
  ///
  /// Returns the projector and the canvas shift to draw it with.
  ({Projector cam, Offset shift}) _camera(Size size, Rect inset) {
    // The fit does not depend on the phase, so a playing wave reuses it.
    final Object key = (
      state,
      view.value,
      size,
      inset,
      showComponents,
      scale,
      labelStyle,
    );
    if (key == _fitKey) return _fitValue!;
    final ({Projector cam, Offset shift}) fitted = _fit(size, inset);
    _fitKey = key;
    _fitValue = fitted;
    return fitted;
  }

  static Object? _fitKey;
  static ({Projector cam, Offset shift})? _fitValue;

  ({Projector cam, Offset shift}) _fit(Size size, Rect inset) {
    final double shortSide = math.min(size.width, size.height);
    final OrbitView v = view.value;
    if (shortSide <= 0) return (cam: Projector(v, size), shift: Offset.zero);
    final OrbitView flat = OrbitView(yawDeg: v.yawDeg, pitchDeg: v.pitchDeg);
    // One world unit draws 1 px about (1, 1); u is relative to the center.
    final Projector unit = Projector(flat, const Size(2, 2), fit: 0.5);
    final List<Offset> u = <Offset>[];
    final List<Rect> pad = <Rect>[];
    void add(double x, double y, double z, Rect box) {
      u.add(unit.project(x, y, z) - const Offset(1, 1));
      pad.add(box);
    }

    // Strokes and arrowheads reach this far past the geometry they draw.
    final double r = scale.markerSize(7) * 0.5 + scale.strokeWidth(2);
    final Rect dot = Rect.fromLTRB(-r, -r, r, r);
    // Sampled at every arrow, where the curves' vertices sit, so a crossing
    // of the inset's corner is caught.
    const int slices = kArrowCount;
    for (int i = 0; i < slices; i++) {
      add(
        -_halfLen - 0.12 + (2 * _halfLen + 0.42) * i / (slices - 1),
        0,
        0,
        dot,
      );
    }
    final TextPainter travel = _layout('Travel');
    add(
      _halfLen + 0.3,
      0,
      0,
      Rect.fromLTWH(
        -travel.width,
        6 * scale.marker,
        travel.width,
        travel.height,
      ),
    );
    if (state.hasField) {
      // The tip's ellipse over a cycle at each slice, and the arrow shafts'
      // midpoints; the component extremes.
      const int m = 24;
      final List<FieldVector> ring = <FieldVector>[
        for (int k = 0; k < m; k++) state.fieldAt(0, 2 * math.pi * k / m),
      ];
      for (int i = 0; i < slices; i++) {
        final double x = _xAt(i, slices);
        for (final FieldVector e in ring) {
          add(x, e.h * _amp, e.v * _amp, dot);
          add(x, e.h * _amp * 0.5, e.v * _amp * 0.5, dot);
        }
        if (showComponents) {
          for (final double sgn in <double>[-1, 1]) {
            add(x, sgn * state.ax * _amp, 0, dot);
            add(x, 0, sgn * state.ay * _amp, dot);
          }
        }
      }
      if (showComponents) {
        // The H and V letters ride the component curves at the source end.
        final TextPainter letter = _layout('H');
        final Offset nudge = const Offset(-14, -8) * scale.text;
        final Rect lbox = Rect.fromLTWH(
          nudge.dx,
          nudge.dy - letter.height / 2,
          letter.width + 2,
          letter.height,
        );
        for (final double sgn in <double>[-1, 1]) {
          add(-_halfLen, sgn * state.ax * _amp, 0, lbox);
          add(-_halfLen, 0, sgn * state.ay * _amp, lbox);
        }
      }
    }

    // A small clear margin inside the viewport and around the inset.
    final double margin = math.max(6 * scale.marker, 0.015 * shortSide);
    final Rect room = (Offset.zero & size).deflate(margin);
    final Rect keepOut = inset.inflate(margin * 0.5);
    Rect extentAt(double px) {
      double l = double.infinity, t = double.infinity;
      double rr = -double.infinity, b = -double.infinity;
      for (int i = 0; i < u.length; i++) {
        final double x = u[i].dx * px, y = u[i].dy * px;
        l = math.min(l, x + pad[i].left);
        rr = math.max(rr, x + pad[i].right);
        t = math.min(t, y + pad[i].top);
        b = math.max(b, y + pad[i].bottom);
      }
      return Rect.fromLTRB(l, t, rr, b);
    }

    // Where u = 0 lands for scale [px] with the extent placed at [anchor]
    // (0 = left or top of the slack, 1 = right or bottom), or null if it
    // does not fit the room or runs under the inset.
    Offset? place(double px, Offset anchor) {
      final Rect e = extentAt(px);
      if (e.width > room.width || e.height > room.height) return null;
      final Offset o = Offset(
        room.left + anchor.dx * (room.width - e.width) - e.left,
        room.top + anchor.dy * (room.height - e.height) - e.top,
      );
      for (int i = 0; i < u.length; i++) {
        if (pad[i].shift(o + u[i] * px).overlaps(keepOut)) return null;
      }
      return o;
    }

    double best = 0;
    Offset bestAt = room.center;
    for (final Offset anchor in const <Offset>[
      Offset(0.5, 0.5),
      Offset(0.5, 1),
      Offset(0, 1),
      Offset(0, 0.5),
    ]) {
      // The largest scale that places: bisect (clearing the inset only gets
      // harder as the drawing grows from its anchor).
      double lo = 0, hi = 4 * shortSide;
      for (int i = 0; i < 28; i++) {
        final double mid = (lo + hi) / 2;
        if (place(mid, anchor) != null) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final Offset? o = lo > 0 ? place(lo, anchor) : null;
      // Centered wins ties: another anchor must beat it by 4%.
      if (o != null && lo > best * 1.04) {
        best = lo;
        bestAt = o;
      }
    }
    if (best <= 0) {
      return (cam: Projector(v, size, fit: 0.2), shift: Offset.zero);
    }
    // Zoom scales about the drawing's center at zoom 1.
    final Offset c = (extentAt(best).center) / best;
    final Offset shift =
        bestAt + c * best - c * (best * v.zoom) - size.center(Offset.zero);
    return (cam: Projector(v, size, fit: best / shortSide), shift: shift);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect inset = insetRect(size);
    // The 3D fills the viewport and keeps clear of the inset (see _camera).
    canvas.save();
    final ({Projector cam, Offset shift}) fitted = _camera(size, inset);
    canvas.translate(fitted.shift.dx, fitted.shift.dy);
    final Projector cam = fitted.cam;
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
  Rect insetRect(Size size) {
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
