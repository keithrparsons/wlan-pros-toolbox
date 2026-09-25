// Painters for the Wi-Fi Lab "Antenna Pattern" tool (antenna-pattern).
//
//   OrbitPainter     the rotatable 3D surface on its dark viewport, with the
//                    floor and the mounting surface drawn as thin reference
//                    lines. Repaints on the camera notifier only.
//   PolarCutPainter  one 2D cut (horizontal: top view; vertical: side view),
//                    on the same dBi scale as the 3D, with the 0 dBi
//                    isotropic ring dashed for reference.
//
// Colors arrive from AppGainRamp (the §8.15.2 gain ramp and its viewport) or
// in a style object built from context.colors, so these files hold no hex
// values. Lime marks the measured quantity on the polar cuts.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/app_gain_ramp.dart';
import 'antenna_pattern_mesh.dart';

void _text(
  Canvas canvas,
  String s,
  TextStyle style,
  Offset at, {
  bool center = true,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double dx = center ? at.dx - tp.width / 2 : at.dx;
  tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  tp.dispose();
}

// ── 3D ──────────────────────────────────────────────────────────────────────

/// Where the antenna is mounted, for the reference lines.
enum MountSurface { ceiling, wall }

class OrbitPainter extends CustomPainter {
  OrbitPainter({
    required this.mesh,
    required this.view,
    required this.surface,
    required this.labelStyle,
    required this.frontLabel,
  }) : super(repaint: view);

  final PatternMesh mesh;
  final ValueNotifier<OrbitView> view;
  final MountSurface surface;
  final TextStyle labelStyle;
  final String frontLabel;

  static const double _room = 1.15;

  void _poly(Canvas c, Projector cam, List<List<double>> pts, Paint p) {
    final Path path = Path();
    for (int k = 0; k < pts.length; k++) {
      final Offset o = cam.project(pts[k][0], pts[k][1], pts[k][2]);
      k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    c.drawPath(path, p);
  }

  void _floor(Canvas c, Projector cam) {
    final Paint grid = Paint()
      ..color = AppGainRamp.viewportRule
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Paint edge = Paint()
      ..color = AppGainRamp.viewportRuleStrong
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double z = -_room;
    for (int k = -2; k <= 2; k++) {
      final double t = _room * k / 2;
      _poly(c, cam, <List<double>>[
        <double>[t, -_room, z],
        <double>[t, _room, z],
      ], k.abs() == 2 ? edge : grid);
      _poly(c, cam, <List<double>>[
        <double>[-_room, t, z],
        <double>[_room, t, z],
      ], k.abs() == 2 ? edge : grid);
    }
  }

  void _mountSurface(Canvas c, Projector cam) {
    final Paint edge = Paint()
      ..color = AppGainRamp.viewportRuleStrong
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double r = _room;
    const double off = 0.05;
    final List<List<double>> square = surface == MountSurface.ceiling
        ? <List<double>>[
            <double>[-r, -r, off],
            <double>[r, -r, off],
            <double>[r, r, off],
            <double>[-r, r, off],
            <double>[-r, -r, off],
          ]
        : <List<double>>[
            <double>[-off, -r, -r],
            <double>[-off, r, -r],
            <double>[-off, r, r],
            <double>[-off, -r, r],
            <double>[-off, -r, -r],
          ];
    _poly(c, cam, square, edge);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final Projector cam = Projector(view.value, size);
    final bool fromBelow = view.value.pitchDeg < 0;
    if (!fromBelow) _floor(canvas, cam);
    _mountSurface(canvas, cam);

    mesh.project(cam);
    final ui.Vertices v = mesh.vertices();
    canvas.drawVertices(v, BlendMode.dst, Paint());
    v.dispose();

    if (fromBelow) _floor(canvas, cam);

    // The antenna's front, after mounting.
    final (double, double, double) f = mesh.rotated
        ? (0.0, 0.0, -1.1)
        : (1.1, 0.0, 0.0);
    final Offset at = cam.project(f.$1, f.$2, f.$3);
    _text(canvas, frontLabel, labelStyle, at);
    // Label the floor at its nearest corner, kept inside the viewport.
    final Offset floor = cam.project(_room, _room, -_room);
    _text(
      canvas,
      'Floor',
      labelStyle,
      Offset(
        floor.dx.clamp(24, size.width - 24).toDouble(),
        floor.dy.clamp(10, size.height - 10).toDouble(),
      ),
    );
  }

  @override
  bool shouldRepaint(OrbitPainter old) =>
      old.mesh != mesh ||
      old.surface != surface ||
      old.frontLabel != frontLabel ||
      old.labelStyle != labelStyle;
}

// ── 2D cuts ─────────────────────────────────────────────────────────────────

enum CutKind { horizontal, vertical }

class PolarStyle {
  const PolarStyle({
    required this.trace,
    required this.ring,
    required this.axis,
    required this.isotropic,
    required this.labelStyle,
  });

  /// The cut itself (lime: the measured quantity).
  final Color trace;
  final Color ring;
  final Color axis;

  /// The dashed 0 dBi reference ring.
  final Color isotropic;
  final TextStyle labelStyle;
}

class PolarCutPainter extends CustomPainter {
  PolarCutPainter({
    required this.lossDb,
    required this.peakDbi,
    required this.topDbi,
    required this.kind,
    required this.style,
    required this.revision,
  });

  /// 360 losses at 1° (MSI angles).
  final List<double> lossDb;
  final double peakDbi;
  final double topDbi;
  final CutKind kind;
  final PolarStyle style;

  /// Bumped by the model on every change; repaint on it.
  final int revision;

  /// Screen direction of cut angle [a] (degrees): horizontal cuts put the
  /// front at the top and run clockwise (a top view); vertical cuts put the
  /// front horizon at the right with down at the bottom (a side view).
  Offset _dir(double a) {
    final double r = a * math.pi / 180;
    return kind == CutKind.horizontal
        ? Offset(math.sin(r), -math.cos(r))
        : Offset(math.cos(r), math.sin(r));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle ls = style.labelStyle;
    final double pad = (ls.fontSize ?? 11) * 1.4;
    final Offset c = size.center(Offset.zero);
    final double rMax = math.min(size.width, size.height) / 2 - pad;
    if (rMax <= 4) return;

    final Paint ring = Paint()
      ..color = style.ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint axis = Paint()
      ..color = style.axis
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int k = 0; k <= 3; k++) {
      final double g = topDbi - 10 * k;
      canvas.drawCircle(c, rMax * gainRadius(g, topDbi), ring);
    }
    for (int a = 0; a < 360; a += 30) {
      canvas.drawLine(c, c + _dir(a.toDouble()) * rMax, ring);
    }
    canvas.drawLine(c + _dir(0) * rMax, c + _dir(180) * rMax, axis);
    canvas.drawLine(c + _dir(90) * rMax, c + _dir(270) * rMax, axis);

    // Isotropic reference, 0 dBi, dashed.
    final double ri = rMax * gainRadius(0, topDbi);
    final Paint iso = Paint()
      ..color = style.isotropic
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int a = 0; a < 360; a += 12) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: ri),
        a * math.pi / 180,
        6 * math.pi / 180,
        false,
        iso,
      );
    }

    // The cut.
    final Path path = Path();
    for (int a = 0; a <= 360; a++) {
      final double g = peakDbi - lossDb[a % 360];
      final Offset p = c + _dir(a.toDouble()) * (rMax * gainRadius(g, topDbi));
      a == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = style.trace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Direction words just outside the rings.
    final double lr = rMax + pad * 0.55;
    if (kind == CutKind.horizontal) {
      _text(canvas, 'Front', ls, c + _dir(0) * lr);
      _text(canvas, 'Back', ls, c + _dir(180) * lr);
    } else {
      _text(canvas, 'Up', ls, c + _dir(270) * lr);
      _text(canvas, 'Down', ls, c + _dir(90) * lr);
    }
    // Ring values along the upper-left spoke.
    for (int k = 0; k <= 2; k++) {
      final double g = topDbi - 10 * k;
      final Offset p =
          c + const Offset(-0.62, -0.62) * (rMax * gainRadius(g, topDbi));
      _text(canvas, g.toStringAsFixed(0), ls, p);
    }
  }

  @override
  bool shouldRepaint(PolarCutPainter old) =>
      old.revision != revision ||
      old.kind != kind ||
      old.style.trace != style.trace ||
      old.style.labelStyle != style.labelStyle;
}
