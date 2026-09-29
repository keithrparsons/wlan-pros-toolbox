// Tests for the shared orbit camera (wifi_lab_orbit.dart), promoted from
// Antenna Pattern on 2026-09-29. They hold the promotion to "unchanged": the
// old import path still resolves, and the default fit is the old scale.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_mesh.dart'
    as legacy;
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_lab_orbit.dart';

void main() {
  test('the Antenna Pattern import path re-exports the same classes', () {
    expect(legacy.OrbitView.initial, OrbitView.initial);
    final legacy.Projector p = Projector(OrbitView.initial, const Size(10, 10));
    expect(p, isA<Projector>());
  });

  test('OrbitView clamps pitch to +/-85 and zoom to 0.6..2.5, wraps yaw', () {
    const OrbitView v = OrbitView();
    expect(v.rotated(0, 200).pitchDeg, 85);
    expect(v.rotated(0, -200).pitchDeg, -85);
    expect(v.zoomed(100).zoom, OrbitView.maxZoom);
    expect(v.zoomed(0.001).zoom, OrbitView.minZoom);
    expect(v.rotated(400, 0).yawDeg, closeTo((50 + 400) % 360, 1e-9));
  });

  test('Projector: origin at the center; default fit is the old 0.40', () {
    const Size size = Size(400, 300);
    final Projector p = Projector(OrbitView.initial, size);
    expect(p.project(0, 0, 0), const Offset(200, 150));
    expect(p.pixelsPerUnit, closeTo(300 * 0.40, 1e-9));
    expect(Projector.defaultFit, 0.40);
    final Projector wide = Projector(OrbitView.initial, size, fit: 0.2);
    expect(wide.pixelsPerUnit, closeTo(60, 1e-9));
  });

  test('Projector: up is up, and nearer points draw larger', () {
    const Size size = Size(400, 400);
    final Projector p = Projector(
      const OrbitView(yawDeg: 0, pitchDeg: 0),
      size,
    );
    expect(p.project(0, 0, 1).dy, lessThan(200));
    // At yaw 0 and pitch 0, +x points at the viewer.
    expect(p.depth(1, 0, 0), greaterThan(p.depth(-1, 0, 0)));
    final double near = (p.project(1, 0, 1) - p.project(1, 0, 0)).distance;
    final double far = (p.project(-1, 0, 1) - p.project(-1, 0, 0)).distance;
    expect(near, greaterThan(far));
  });

  test('projectInto matches project', () {
    final Projector p = Projector(
      const OrbitView(yawDeg: 33, pitchDeg: -12, zoom: 1.3),
      const Size(640, 360),
    );
    final Float32List out = Float32List(2);
    for (final List<double> v in <List<double>>[
      <double>[0.3, -0.7, 0.2],
      <double>[-1, 1, -1],
      <double>[math.sqrt1_2, 0, math.sqrt1_2],
    ]) {
      final double d = p.projectInto(out, 0, v[0], v[1], v[2]);
      final Offset o = p.project(v[0], v[1], v[2]);
      expect(out[0], closeTo(o.dx, 1e-3));
      expect(out[1], closeTo(o.dy, 1e-3));
      expect(d, closeTo(p.depth(v[0], v[1], v[2]), 1e-12));
    }
  });
}
