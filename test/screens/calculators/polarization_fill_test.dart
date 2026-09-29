// The 3D fills its viewport (spec 45 line 49; Vera gate B, 2026-09-29).
//
// Vera measured the wave at 57% of the viewport's width and 44% of its height
// at 1920x1080, and 25 to 29% of the area at 1470x923 and on the phone: the
// scale was fitted to the corners of a box around the wave, not to the wave.
//
// This test measures the PIXELS, not the painter's own arithmetic: it renders
// the screen, takes the 3D viewport's rectangle, and finds every pixel that
// differs from the viewport's background outside the End-on view inset. That
// box must span at least 80% of the viewport's width or of its height
// (whichever binds), and must not touch the viewport's edge (a clipped wave
// would run into it). Held at the presenter's 1920x1080 and 1470x923, the
// 390 px phone, every preset with the components on, and after orbiting.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_painter.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_lab_orbit.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/polarization_model.dart';
import 'package:wlan_pros_toolbox/theme/app_gain_ramp.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

final GlobalKey _shotKey = GlobalKey();

Future<PolarizationController> _open(
  WidgetTester tester, {
  required Size window,
  required bool present,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const PolarizationScreen(),
      ),
    ),
  );
  await _settle(tester);
  if (present) {
    await tester.tap(find.text('Present'));
    await _settle(tester);
  }
  final PolarizationController c = tester
      .widget<PolarizationStage>(find.byType(PolarizationStage).last)
      .controller;
  c.setPlaying(false);
  c.setShowComponents(true);
  await _settle(tester);
  return c;
}

/// What was measured: the viewport and the box around every drawn pixel.
/// [insetGap] is how close any drawn pixel comes to the End-on inset, and
/// [inset] is the inset's square.
typedef _Fill = ({Rect viewport, Rect drawn, Rect inset, double insetGap});

/// Set `POLARIZATION_FILL_OUT=<dir>` to also write each measured frame as a PNG.
final String? _dumpDir = Platform.environment['POLARIZATION_FILL_OUT'];

Future<_Fill> _measure(WidgetTester tester, [String? slug]) async {
  final Finder paint = find.byWidgetPredicate(
    (Widget w) => w is CustomPaint && w.painter is PolarizationPainter,
  );
  expect(paint, findsOneWidget);
  final Rect viewport = tester.getRect(paint);
  final PolarizationPainter painter =
      tester.widget<CustomPaint>(paint).painter! as PolarizationPainter;
  final Rect inset = painter
      .insetRect(viewport.size)
      .shift(viewport.topLeft)
      .inflate(3);
  final RenderRepaintBoundary boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final (ByteData, int)? shot = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (_dumpDir != null && slug != null) {
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final File out = File('$_dumpDir/$slug.png');
      await out.create(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
    }
    return (bytes!, image.width);
  });
  final ByteData px = shot!.$1;
  final int w = shot.$2;
  const Color bg = AppGainRamp.viewport;
  final int br = (bg.r * 255).round();
  final int bgG = (bg.g * 255).round();
  final int bb = (bg.b * 255).round();
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  double gap = double.infinity;
  // One pixel in from the edge, and not the four corner squares: the
  // viewport's rounded border curves in across the painter's corners.
  final Rect scan = viewport.deflate(1);
  const double corner = AppRadius.control + 2;
  bool inCorner(double x, double y) =>
      (x < viewport.left + corner || x > viewport.right - corner) &&
      (y < viewport.top + corner || y > viewport.bottom - corner);
  for (int y = scan.top.ceil(); y < scan.bottom.floor(); y++) {
    for (int x = scan.left.ceil(); x < scan.right.floor(); x++) {
      if (inset.contains(Offset(x + 0.5, y + 0.5))) continue;
      if (inCorner(x + 0.5, y + 0.5)) continue;
      final int o = (y * w + x) * 4;
      final int d = math3(
        (px.getUint8(o) - br).abs(),
        (px.getUint8(o + 1) - bgG).abs(),
        (px.getUint8(o + 2) - bb).abs(),
      );
      if (d < 24) continue;
      if (x < minX) minX = x.toDouble();
      if (x + 1 > maxX) maxX = x + 1.0;
      if (y < minY) minY = y.toDouble();
      if (y + 1 > maxY) maxY = y + 1.0;
      final double gx = math.max(
        0,
        math.max(inset.left - x - 1, x - inset.right),
      );
      final double gy = math.max(
        0,
        math.max(inset.top - y - 1, y - inset.bottom),
      );
      gap = math.min(gap, math.max(gx, gy));
    }
  }
  expect(minX.isFinite, isTrue, reason: 'nothing drawn');
  return (
    viewport: viewport,
    drawn: Rect.fromLTRB(minX, minY, maxX, maxY),
    inset: inset.deflate(3),
    insetGap: gap,
  );
}

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

int math3(int a, int b, int c) => a > b ? (a > c ? a : c) : (b > c ? b : c);

/// Measures [frames] frames a fraction of a cycle apart (the wave plays
/// between them, then pauses again): every frame must be unclipped, and the
/// union of what they draw must fill. The fit covers a whole cycle so the
/// scale holds still while the wave plays; a linear wave paused with its
/// ends near zero draws less than its cycle does, so the fill is judged on
/// what the stage shows over one cycle.
Future<void> _expectCycleFills(
  WidgetTester tester,
  PolarizationController c,
  String at, {
  int frames = 6,
}) async {
  Rect? union;
  late Rect viewport;
  late Rect inset;
  double insetGap = double.infinity;
  final List<String> single = <String>[];
  for (int k = 0; k < frames; k++) {
    final _Fill f = await _measure(tester, _slug('$at f$k'));
    _expectUnclipped(f, '$at frame $k');
    viewport = f.viewport;
    inset = f.inset;
    insetGap = math.min(insetGap, f.insetGap);
    union = union == null ? f.drawn : union.expandToInclude(f.drawn);
    single.add(_share(f.drawn, f.viewport));
    c.setPlaying(true);
    await tester.pump();
    await tester.pump(
      Duration(
        milliseconds: (kPolarizationSecondsPerCycle * 1000 / frames).round(),
      ),
    );
    c.setPlaying(false);
    await tester.pump();
  }
  final double wShare = union!.width / viewport.width;
  final double hShare = union.height / viewport.height;
  // Where the drawing is stopped by the End-on inset (it may not run under
  // it), the binding dimension is the room beside or below the inset.
  final bool stoppedByInset = insetGap <= 16;
  final double wBeside = union.width / (viewport.width - inset.width);
  final double hBelow = union.height / (viewport.height - inset.height);
  final String got =
      '$at: over a cycle drawn $union in $viewport, '
      '${_share(union, viewport)}; single frames ${single.join(', ')}; '
      'nearest the inset ${insetGap.toStringAsFixed(0)} px'
      '${stoppedByInset ? ', stopped by the inset: '
                '${(wBeside * 100).toStringAsFixed(0)}% of the width beside it, '
                '${(hBelow * 100).toStringAsFixed(0)}% of the height below it' : ''}';
  expect(
    wShare >= 0.80 ||
        hShare >= 0.80 ||
        (stoppedByInset && (wBeside >= 0.80 || hBelow >= 0.80)),
    isTrue,
    reason: 'too small: $got',
  );
  _log.add(got);
}

final List<String> _log = <String>[];

String _share(Rect drawn, Rect viewport) =>
    '${(drawn.width / viewport.width * 100).toStringAsFixed(0)}% x '
    '${(drawn.height / viewport.height * 100).toStringAsFixed(0)}%';

void _expectUnclipped(_Fill f, String at) {
  final String got = '$at: drawn ${f.drawn} in ${f.viewport}';
  // Not clipped: at least 3 px of clear background inside every edge.
  expect(f.drawn.left - f.viewport.left, greaterThanOrEqualTo(3), reason: got);
  expect(f.drawn.top - f.viewport.top, greaterThanOrEqualTo(3), reason: got);
  expect(
    f.viewport.right - f.drawn.right,
    greaterThanOrEqualTo(3),
    reason: got,
  );
  expect(
    f.viewport.bottom - f.drawn.bottom,
    greaterThanOrEqualTo(3),
    reason: got,
  );
}

/// The orbits a presenter might leave it at: the opening view, turned
/// round, from above, from below, end on, and zoom left at 1.
const List<OrbitView> _orbits = <OrbitView>[
  PolarizationController.initialView,
  OrbitView(yawDeg: 148, pitchDeg: 20),
  OrbitView(yawDeg: 238, pitchDeg: 35),
  OrbitView(yawDeg: 20, pitchDeg: 70),
  OrbitView(yawDeg: 300, pitchDeg: -45),
  OrbitView(yawDeg: 0, pitchDeg: 0),
  OrbitView(yawDeg: 90, pitchDeg: 10),
];

void main() {
  tearDownAll(() {
    if (_dumpDir != null) {
      File('$_dumpDir/fill-log.txt').writeAsStringSync(_log.join('\n'));
    }
  });
  for (final (String name, Size window, bool present)
      in const <(String, Size, bool)>[
        ('presenter 1920x1080', Size(1920, 1080), true),
        ('presenter 1470x923', Size(1470, 923), true),
        ('phone 390', Size(390, 1600), false),
      ]) {
    testWidgets('$name: every preset fills the viewport, unclipped', (
      WidgetTester tester,
    ) async {
      final PolarizationController c = await _open(
        tester,
        window: window,
        present: present,
      );
      for (final PolarizationPreset p in PolarizationPreset.named) {
        c.setPreset(p);
        await _settle(tester);
        await _expectCycleFills(tester, c, '$name ${p.label}');
      }
    });

    testWidgets('$name: after orbiting, still fills and nothing clips', (
      WidgetTester tester,
    ) async {
      final PolarizationController c = await _open(
        tester,
        window: window,
        present: present,
      );
      for (final PolarizationPreset p in <PolarizationPreset>[
        PolarizationPreset.circular,
        PolarizationPreset.vertical,
        PolarizationPreset.slant45,
      ]) {
        c.setPreset(p);
        for (final OrbitView v in _orbits) {
          c.view.value = v;
          await _settle(tester);
          await _expectCycleFills(
            tester,
            c,
            '$name ${p.label} yaw ${v.yawDeg} pitch ${v.pitchDeg}',
          );
        }
      }
      // A drag on the viewport, then Reset view.
      final Finder paint = find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is PolarizationPainter,
      );
      await tester.drag(paint, const Offset(-120, 60));
      await _settle(tester);
      await _expectCycleFills(tester, c, '$name after a drag');
    });
  }
}
