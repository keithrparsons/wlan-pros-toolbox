// The orbit camera shared by the Wi-Fi Classroom's rotatable 3D views: Antenna
// Pattern (antenna-pattern) and Polarization (polarization).
//
// Promoted from antenna_pattern_mesh.dart on 2026-09-29 (PLAN.md "Shared
// work", Feature 5b). The code is unchanged apart from [Projector]'s optional
// fit argument, whose default is the old constant, so Antenna Pattern draws
// exactly as before. antenna_pattern_mesh.dart re-exports both classes.
//
// World axes: at yaw 0 and pitch 0, +x points at the viewer, +y to the right
// of the canvas and +z up (Antenna Pattern calls x the antenna's front and y
// its left, the antenna facing the viewer).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The camera: yaw about the vertical, pitch above the horizon, zoom.
class OrbitView {
  const OrbitView({this.yawDeg = 50, this.pitchDeg = 22, this.zoom = 1});

  final double yawDeg;

  /// Positive looks down from above; clamped to ±85°.
  final double pitchDeg;
  final double zoom;

  static const OrbitView initial = OrbitView();
  static const double minZoom = 0.6;
  static const double maxZoom = 2.5;

  OrbitView rotated(double dYaw, double dPitch) => OrbitView(
    yawDeg: (yawDeg + dYaw) % 360,
    pitchDeg: (pitchDeg + dPitch).clamp(-85.0, 85.0),
    zoom: zoom,
  );

  OrbitView zoomed(double factor) => OrbitView(
    yawDeg: yawDeg,
    pitchDeg: pitchDeg,
    zoom: (zoom * factor).clamp(minZoom, maxZoom),
  );

  @override
  bool operator ==(Object other) =>
      other is OrbitView &&
      other.yawDeg == yawDeg &&
      other.pitchDeg == pitchDeg &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(yawDeg, pitchDeg, zoom);
}

/// A camera fixed for one frame: projects world points to the canvas.
class Projector {
  /// [fit] is the share of the shorter side one world unit spans at zoom 1
  /// (0.40, Antenna Pattern's pattern radius; a long wave passes less).
  Projector(OrbitView view, ui.Size size, {double fit = defaultFit})
    : _cy = math.cos(view.yawDeg * math.pi / 180),
      _sy = math.sin(view.yawDeg * math.pi / 180),
      _cp = math.cos(view.pitchDeg * math.pi / 180),
      _sp = math.sin(view.pitchDeg * math.pi / 180),
      _ox = size.width / 2,
      _oy = size.height / 2,
      _scale = math.min(size.width, size.height) * fit * view.zoom;

  final double _cy, _sy, _cp, _sp, _ox, _oy, _scale;

  /// The scale Antenna Pattern was built with.
  static const double defaultFit = 0.40;

  /// Canvas pixels per world unit at the origin's depth.
  double get pixelsPerUnit => _scale;

  /// Distance from the eye to the origin, in pattern radii (mild perspective).
  static const double eye = 5;

  /// Depth toward the viewer (larger = nearer).
  double depth(double x, double y, double z) {
    final double x1 = x * _cy - y * _sy;
    return x1 * _cp + z * _sp;
  }

  ui.Offset project(double x, double y, double z) {
    final double x1 = x * _cy - y * _sy;
    final double y1 = x * _sy + y * _cy;
    final double up = -x1 * _sp + z * _cp;
    final double d = x1 * _cp + z * _sp;
    final double s = _scale * eye / (eye - d);
    return ui.Offset(_ox + y1 * s, _oy - up * s);
  }

  /// [project] without allocating: writes the canvas point to out[o] and
  /// out[o + 1] and returns the depth. The per-frame hot path.
  double projectInto(Float32List out, int o, double x, double y, double z) {
    final double x1 = x * _cy - y * _sy;
    final double y1 = x * _sy + y * _cy;
    final double up = -x1 * _sp + z * _cp;
    final double d = x1 * _cp + z * _sp;
    final double s = _scale * eye / (eye - d);
    out[o] = _ox + y1 * s;
    out[o + 1] = _oy - up * s;
    return d;
  }
}
