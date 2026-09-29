// The rotatable 3D surface for the Wi-Fi Classroom "Antenna Pattern" tool
// (antenna-pattern).
//
// PERFORMANCE CONTRACT (Larry's brief): the gain grid and the mesh are built
// only when a parameter changes. A frame of rotation does two things:
//   1. project the 91 × 180 = 16,380 mesh vertices through the camera, and
//   2. order the 16,200 quads back to front (painter's algorithm) with a
//      linear-time bucket sort on depth, then write one index buffer.
// The quads' corner positions, colors and index buffer are preallocated and
// reused, and the whole surface is ONE Canvas.drawVertices call. Colors are
// per vertex (the ramp stop of that vertex's gain band), assigned at build
// time, never per frame.
//
// Geometry: radius and color are gain in dBi on a fixed scale (the top of the
// scale moves only in 5 dB steps, so a gain slider visibly reshapes the
// surface instead of rescaling it). World axes: x = the antenna's front, y =
// its left, z = up.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../services/wifi_lab/antenna_pattern_math.dart';
import '../../../theme/app_gain_ramp.dart';
import 'wifi_lab_orbit.dart';

// OrbitView and Projector moved to wifi_lab_orbit.dart (2026-09-29, shared with
// the Polarization tile); re-exported so every existing import still compiles.
export 'wifi_lab_orbit.dart' show OrbitView, Projector;

/// Degrees between mesh rows and columns.
const int kMeshStepDeg = 2;

/// Mesh rows (theta 0..180) and columns (phi 0..358).
const int kMeshRows = 180 ~/ kMeshStepDeg + 1; // 91
const int kMeshCols = 360 ~/ kMeshStepDeg; // 180
const int kMeshVertices = kMeshRows * kMeshCols; // 16,380
const int kMeshQuads = (kMeshRows - 1) * kMeshCols; // 16,200

/// dB from the top of the scale down to the floor: seven 5 dB bands.
const double kScaleSpanDb = AppGainRamp.bandDb * 7; // 35

/// Top of the gain scale for a pattern: 20 dBi, or the peak rounded up to
/// the next 5 dB when it is higher. Fixed across small changes on purpose.
double scaleTopDbi(double peakDbi) =>
    peakDbi <= 20 ? 20 : (peakDbi / 5).ceil() * 5.0;

/// Band index 0..6 for a gain on a scale topping out at [topDbi].
int gainBand(double dbi, double topDbi) =>
    ((dbi - (topDbi - kScaleSpanDb)) / AppGainRamp.bandDb).floor().clamp(0, 6);

/// Radius 0..1 for a gain: linear in dB from the floor (top − 35 dB) to the
/// top. Anything at or below the floor sits at a small minimum radius.
double gainRadius(double dbi, double topDbi) =>
    ((dbi - (topDbi - kScaleSpanDb)) / kScaleSpanDb).clamp(0.015, 1.0);

/// The pattern as a colored surface, ready to be projected every frame.
class PatternMesh {
  PatternMesh._(this._xyz, this._colors, this.topDbi, this.rotated);

  /// Builds the mesh from a 1° gain grid (sampled every [kMeshStepDeg]).
  /// [rotated] turns the antenna 90° about the y axis ((x, y, z) -> (z, y,
  /// −x)): front to straight down, or an omni's axis to the front.
  factory PatternMesh.build(GainGrid grid, {required bool rotated}) {
    final double top = scaleTopDbi(grid.peakDbi);
    final Float32List xyz = Float32List(kMeshVertices * 3);
    final Float64List gain = Float64List(kMeshVertices);
    for (int i = 0; i < kMeshRows; i++) {
      final int theta = i * kMeshStepDeg;
      final double t = theta * math.pi / 180;
      for (int j = 0; j < kMeshCols; j++) {
        final int phi = j * kMeshStepDeg;
        final double p = phi * math.pi / 180;
        final double g = grid.at(theta, phi);
        final double r = gainRadius(g, top);
        double x = r * math.sin(t) * math.cos(p);
        final double y = -r * math.sin(t) * math.sin(p); // MSI: clockwise
        double z = r * math.cos(t);
        if (rotated) {
          final double nx = z;
          z = -x;
          x = nx;
        }
        final int v = i * kMeshCols + j;
        xyz[v * 3] = x;
        xyz[v * 3 + 1] = y;
        xyz[v * 3 + 2] = z;
        gain[v] = g;
      }
    }
    // Each corner takes the band of its own vertex. Inside a band every
    // corner is the same stop, so the quad is flat; only the one 2° quad a
    // band edge crosses blends between two adjacent stops. (Flat per-quad
    // color left stair-steps along tilted band edges: render check,
    // 2026-09-25.)
    final Int32List colors = Int32List(kMeshQuads * 4);
    final List<int> bandArgb = <int>[
      for (final ui.Color c in AppGainRamp.bands) c.toARGB32(),
    ];
    for (int q = 0; q < kMeshQuads; q++) {
      final (int a, int b, int c, int d) = _corners(q);
      colors[q * 4] = bandArgb[gainBand(gain[a], top)];
      colors[q * 4 + 1] = bandArgb[gainBand(gain[b], top)];
      colors[q * 4 + 2] = bandArgb[gainBand(gain[c], top)];
      colors[q * 4 + 3] = bandArgb[gainBand(gain[d], top)];
    }
    return PatternMesh._(xyz, colors, top, rotated);
  }

  final Float32List _xyz;
  final Int32List _colors;

  /// Top of the gain scale this mesh was built on.
  final double topDbi;
  final bool rotated;

  // Per-frame buffers, reused.
  final Float32List _screen = Float32List(kMeshVertices * 2);
  final Float32List _depth = Float32List(kMeshVertices);
  final Float32List _positions = Float32List(kMeshQuads * 4 * 2);
  final Float32List _quadDepth = Float32List(kMeshQuads);
  final Uint16List _indices = Uint16List(kMeshQuads * 6);
  final Uint16List _order = Uint16List(kMeshQuads);
  static const int _buckets = 2048;
  final Int32List _count = Int32List(_buckets + 1);

  /// Vertex indices of quad [q]'s corners.
  static (int, int, int, int) _corners(int q) {
    final int i = q ~/ kMeshCols;
    final int j = q % kMeshCols;
    final int j1 = (j + 1) % kMeshCols;
    return (
      i * kMeshCols + j,
      i * kMeshCols + j1,
      (i + 1) * kMeshCols + j1,
      (i + 1) * kMeshCols + j,
    );
  }

  /// The world position of vertex [v] (for tests).
  (double, double, double) vertex(int v) =>
      (_xyz[v * 3], _xyz[v * 3 + 1], _xyz[v * 3 + 2]);

  /// Projects every vertex and orders the quads back to front. After this,
  /// [drawOrder] lists quads farthest first and [vertices] is ready to draw.
  void project(Projector camera) {
    for (int v = 0; v < kMeshVertices; v++) {
      _depth[v] = camera.projectInto(
        _screen,
        v * 2,
        _xyz[v * 3],
        _xyz[v * 3 + 1],
        _xyz[v * 3 + 2],
      );
    }
    // Corner positions (static order: quad q owns corners 4q..4q+3) and
    // per-quad depth, bucketed over [−1, 1] (every radius is <= 1).
    _count.fillRange(0, _count.length, 0);
    for (int q = 0; q < kMeshQuads; q++) {
      final (int a, int b, int c, int d) = _corners(q);
      final int base = q * 8;
      _positions[base] = _screen[a * 2];
      _positions[base + 1] = _screen[a * 2 + 1];
      _positions[base + 2] = _screen[b * 2];
      _positions[base + 3] = _screen[b * 2 + 1];
      _positions[base + 4] = _screen[c * 2];
      _positions[base + 5] = _screen[c * 2 + 1];
      _positions[base + 6] = _screen[d * 2];
      _positions[base + 7] = _screen[d * 2 + 1];
      final double z = (_depth[a] + _depth[b] + _depth[c] + _depth[d]) / 4;
      _quadDepth[q] = z;
      _count[_bucket(z) + 1]++;
    }
    for (int k = 1; k <= _buckets; k++) {
      _count[k] += _count[k - 1];
    }
    for (int q = 0; q < kMeshQuads; q++) {
      _order[_count[_bucket(_quadDepth[q])]++] = q;
    }
    for (int n = 0; n < kMeshQuads; n++) {
      final int q = _order[n];
      final int c0 = q * 4;
      final int o = n * 6;
      _indices[o] = c0;
      _indices[o + 1] = c0 + 1;
      _indices[o + 2] = c0 + 2;
      _indices[o + 3] = c0;
      _indices[o + 4] = c0 + 2;
      _indices[o + 5] = c0 + 3;
    }
  }

  static int _bucket(double depth) =>
      ((depth + 1) * 0.5 * (_buckets - 1)).round().clamp(0, _buckets - 1);

  /// Quads in draw order (farthest first), valid after [project].
  Uint16List get drawOrder => _order;

  /// Depth of quad [q] from the last [project].
  double quadDepth(int q) => _quadDepth[q];

  /// The projected surface as one triangle list. Dispose after drawing.
  ui.Vertices vertices() => ui.Vertices.raw(
    ui.VertexMode.triangles,
    _positions,
    colors: _colors,
    indices: _indices,
  );
}
