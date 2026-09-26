// Widget, model and mesh tests for the Antenna Pattern screen (Wi-Fi Classroom,
// antenna-pattern).
//
// The math and the file formats have their own tests
// (test/services/wifi_lab/antenna_pattern_*_test.dart). These check that the
// screen drives them: the lab state, the 3D mesh and its per-frame cost, the
// catalog registration, rotation by drag and by keyboard, the import states,
// and the layout at phone width in both themes with no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_mesh.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/antenna_pattern_math.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({
  ThemeData? theme,
  AntennaModelKind kind = AntennaModelKind.omni,
}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: AntennaPatternScreen(initialKind: kind),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickFromSelect(
  WidgetTester tester,
  String current,
  String option,
) async {
  await tester.ensureVisible(find.text(current).first);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

AntennaPatternLab _labOf(WidgetTester tester) =>
    tester.widget<AntennaPatternStage>(find.byType(AntennaPatternStage)).lab;

void main() {
  group('registration', () {
    test('catalog entry in the Wi-Fi Classroom subgroup, with route and help id', () {
      final ToolEntry t = kToolCategories
          .expand((ToolCategory c) => c.tools)
          .firstWhere((ToolEntry e) => e.id == 'antenna-pattern');
      expect(t.title, 'Antenna Pattern');
      expect(t.routeName, '/tools/antenna-pattern');
      expect(t.subgroup, 'Wi-Fi Classroom');
      expect(t.isLive, isTrue);
      expect(kAntennaPatternToolId, t.id);
      expect(AppRouter.routes.containsKey(t.routeName), isTrue);
      expect(kToolKeywords['antenna-pattern'], contains('msi'));
    });
  });

  group('lab', () {
    test('a pattern change bumps the revision; the camera does not', () {
      final AntennaPatternLab lab = AntennaPatternLab();
      final int r0 = lab.revision;
      lab.view.value = lab.view.value.rotated(30, 10);
      expect(lab.revision, r0);
      lab.setPolarization(45);
      expect(lab.revision, r0);
      lab.setOmniGain(12);
      expect(lab.revision, r0 + 1);
      lab.dispose();
    });

    test('the grid and mesh are rebuilt once per change, not per read', () {
      final AntennaPatternLab lab = AntennaPatternLab();
      final PatternMesh? m1 = lab.mesh;
      expect(identical(lab.mesh, m1), isTrue);
      expect(identical(lab.result, lab.result), isTrue);
      lab.setOmniGain(10);
      expect(identical(lab.mesh, m1), isFalse);
      lab.dispose();
    });

    test('the omni gain slider really moves the peak', () {
      final AntennaPatternLab lab = AntennaPatternLab()..setOmniGain(12);
      expect(lab.result!.grid.peakDbi, closeTo(12, 0.5));
      lab.setOmniGain(5);
      expect(lab.result!.grid.peakDbi, closeTo(5, 0.5));
      lab.dispose();
    });

    test('the directional gain slider sets both beamwidths by 31,000', () {
      final AntennaPatternLab lab = AntennaPatternLab(
        initialKind: AntennaModelKind.directional,
      )..setDirectionalGain(15);
      expect(lab.directionalBeamwidthGainDbi, closeTo(15, 0.2));
      expect(lab.hBeamDeg, lab.vBeamDeg); // the 65:65 ratio is kept
      lab.dispose();
    });

    test('mounting turns an omni on a wall and a directional on a ceiling', () {
      final AntennaPatternLab lab = AntennaPatternLab();
      expect(lab.rotatedForMount, isFalse); // omni, ceiling
      lab.setMount(AntennaMount.wall);
      expect(lab.rotatedForMount, isTrue);
      lab.setKind(AntennaModelKind.directional);
      expect(lab.rotatedForMount, isFalse); // directional, wall
      lab.setMount(AntennaMount.ceiling);
      expect(lab.rotatedForMount, isTrue);
      // Directional on the ceiling: the front points straight down.
      final PatternMesh m = lab.mesh!;
      final (double x, double y, double z) = m.vertex(
        (90 ~/ kMeshStepDeg) * kMeshCols, // theta 90, phi 0
      );
      expect(z, lessThan(-0.5));
      expect(x.abs(), lessThan(1e-6));
      expect(y.abs(), lessThan(1e-6));
      lab.dispose();
    });

    test('imported: empty, then error keeps nothing, then an example gives '
        'both rebuild errors', () {
      final AntennaPatternLab lab = AntennaPatternLab(
        initialKind: AntennaModelKind.imported,
      );
      expect(lab.result, isNull);
      lab.importPattern('this is not a pattern file');
      expect(lab.importError, isNotNull);
      expect(lab.result, isNull);
      lab.loadExample(PatternExample.tiltedSector);
      expect(lab.importError, isNull);
      expect(lab.hasTruth, isTrue);
      final PatternResult r = lab.result!;
      expect(r.estimated, isTrue);
      expect(r.errors, isNotNull);
      expect(r.errors!.summing.rmsDb, greaterThan(0.1));
      // Editing the text drops the known truth.
      lab.importPattern('${lab.importText}\nCOMMENT edited');
      expect(lab.hasTruth, isFalse);
      expect(lab.result!.errors, isNull);
      lab.dispose();
    });

    test('an error after a good file keeps the good pattern on screen', () {
      final AntennaPatternLab lab = AntennaPatternLab(
        initialKind: AntennaModelKind.imported,
      )..loadExample(PatternExample.dipole);
      final double peak = lab.result!.grid.peakDbi;
      lab.importPattern('NAME broken\nHORIZONTAL 2\n0 0\n');
      expect(lab.importError, isNotNull);
      expect(lab.result!.grid.peakDbi, peak);
      lab.dispose();
    });

    test('rebuild from two cuts: a separable sector comes back exactly', () {
      final AntennaPatternLab lab = AntennaPatternLab(
        initialKind: AntennaModelKind.directional,
      )..rebuildFromTwoCuts();
      expect(lab.kind, AntennaModelKind.imported);
      expect(lab.result!.errors!.summing.rmsDb, lessThan(0.02));
      lab.dispose();
    });

    test('the NSMA example reads as the same antenna as the MSI one', () {
      final AntennaPatternLab a = AntennaPatternLab()
        ..loadExample(PatternExample.tiltedSector);
      final AntennaPatternLab b = AntennaPatternLab()
        ..loadExample(PatternExample.tiltedSectorNsma);
      expect(b.parsed!.format.name, 'nsma');
      expect(
        b.result!.grid.peakTheta,
        a.result!.grid.peakTheta,
        reason: 'the downtilted peak must stay below the horizon',
      );
      expect(b.result!.grid.peakDbi, closeTo(a.result!.grid.peakDbi, 0.01));
      a.dispose();
      b.dispose();
    });
  });

  group('mesh', () {
    final PatternMesh mesh = PatternMesh.build(
      GainGrid.fromShape(
        const SectorShape(
          hBeamwidthDeg: 65,
          vBeamwidthDeg: 65,
          frontToBackDb: 30,
          sideLobeDb: 30,
          tiltDeg: 0,
        ),
      ),
      rotated: false,
    );

    test('91 x 180 vertices, 16,200 quads, within Uint16 indexing', () {
      expect(kMeshRows, 91);
      expect(kMeshCols, 180);
      expect(kMeshVertices, 16380);
      expect(kMeshQuads, 16200);
      expect(kMeshQuads * 4, lessThan(65536));
    });

    test('quads are drawn back to front', () {
      mesh.project(Projector(OrbitView.initial, const Size(390, 320)));
      final List<int> order = mesh.drawOrder;
      double prev = -double.infinity;
      // Bucketed, so allow one bucket (2/2047) of slack.
      for (final int q in order) {
        expect(mesh.quadDepth(q), greaterThanOrEqualTo(prev - 0.002));
        prev = mesh.quadDepth(q);
      }
      expect(order.toSet().length, kMeshQuads);
    });

    test('a frame of rotation (project + sort) is cheap', () {
      // Host JIT under flutter test, not a phone; the number is reported in
      // the build log. The bound only catches an accidental O(n^2).
      final Stopwatch sw = Stopwatch()..start();
      const int frames = 60;
      for (int f = 0; f < frames; f++) {
        mesh.project(
          Projector(
            OrbitView(yawDeg: f * 6.0, pitchDeg: 20),
            const Size(390, 320),
          ),
        );
      }
      final double perFrameMs = sw.elapsedMicroseconds / 1000 / frames;
      // ignore: avoid_print
      print(
        'antenna-pattern mesh: project+sort ${perFrameMs.toStringAsFixed(2)} '
        'ms per frame over $frames frames',
      );
      expect(perFrameMs, lessThan(40));
    });
  });

  group('screen', () {
    testWidgets('dragging the 3D view rotates it; the pattern is untouched', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(390, 2400));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final AntennaPatternLab lab = _labOf(tester);
      final int rev = lab.revision;
      final OrbitView before = lab.view.value;
      await tester.drag(
        find
            .bySemanticsLabel(RegExp(r'^3D antenna pattern'))
            .hitTestable()
            .first,
        const Offset(120, 40),
      );
      await tester.pump();
      expect(lab.view.value, isNot(before));
      expect(lab.revision, rev);
      await tester.tap(find.text('Reset view'));
      await tester.pump();
      expect(lab.view.value, OrbitView.initial);
    });

    testWidgets('arrow keys rotate the focused 3D view', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 2400));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final AntennaPatternLab lab = _labOf(tester);
      await tester.tap(
        find
            .bySemanticsLabel(RegExp(r'^3D antenna pattern'))
            .hitTestable()
            .first,
      );
      await tester.pump();
      final double yaw = lab.view.value.yawDeg;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(lab.view.value.yawDeg, closeTo((yaw + 10) % 360, 1e-9));
    });

    testWidgets('switching models updates the readouts', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 3000));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _pickFromSelect(tester, 'Omni, set by gain', 'Half-wave dipole');
      expect(find.textContaining('2.2 dBi  (0.0 dBd)'), findsOneWidget);
      await _pickFromSelect(
        tester,
        'Half-wave dipole',
        'Directional (patch or sector)',
      );
      expect(find.textContaining('worst in the rear 120°'), findsWidgets);
      expect(find.textContaining('by 31,000'), findsOneWidget);
    });

    testWidgets('imported: empty state, bad paste error, then an example', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 3600));
      await tester.pumpWidget(_host(kind: AntennaModelKind.imported));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pattern loaded yet'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.text('Read pattern'));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not start with a key'), findsNothing);
      expect(find.textContaining('No HORIZONTAL section'), findsOneWidget);
      expect(find.textContaining('No pattern loaded yet'), findsOneWidget);
      await _pickFromSelect(
        tester,
        'Pick one to load it',
        PatternExample.tiltedSector.label,
      );
      expect(find.textContaining('No pattern loaded yet'), findsNothing);
      expect(find.text('Rebuild error, against the exact 3D'), findsOneWidget);
      expect(find.textContaining('estimated from two cuts'), findsOneWidget);
    });

    for (final (String, ThemeData Function()) theme
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final AntennaModelKind kind in AntennaModelKind.values) {
        testWidgets('390 px, ${theme.$1}, ${kind.label}: no overflow, no '
            'sideways scroll', (WidgetTester tester) async {
          await _setSize(tester, const Size(390, 900));
          await tester.pumpWidget(_host(theme: theme.$2(), kind: kind));
          await tester.pumpAndSettle();
          if (kind == AntennaModelKind.imported) {
            _labOf(tester).loadExample(PatternExample.tiltedSectorNsma);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          expect(find.byType(AntennaPatternControls), findsOneWidget);
          for (final ScrollableState each in tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          )) {
            if (each.position.axis == Axis.horizontal) {
              expect(each.position.maxScrollExtent, 0);
            }
          }
        });
      }
    }
  });
}
