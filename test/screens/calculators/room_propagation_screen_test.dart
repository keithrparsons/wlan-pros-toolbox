// Widget and controller tests for the Wi-Fi Classroom "Room Propagation" screen.
//
// The physics is pinned in test/services/wifi_lab/room_propagation_model_test
// .dart; these cover the screen contract: catalog and route registration, the
// stage and controls as separate widgets over one controller, the dBm legend,
// the loading, error and empty states, the thickness error, the edits the
// plan tools make, compute coalescing (the client moving does not recompute
// the average map; EIRP recomputes nothing), and phone and desktop widths in
// both themes without overflow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/room_propagation_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Runs every job on the test thread, and records it.
class _SyncRunner {
  final List<RoomFieldJob> jobs = <RoomFieldJob>[];

  Future<RoomFieldResult> call(RoomFieldJob job) {
    jobs.add(job);
    return Future<RoomFieldResult>.value(
      computeRoomField(
        RoomFieldJob(
          walls: job.walls,
          ap: job.ap,
          radio: job.radio,
          widthM: job.widthM,
          heightM: job.heightM,
          // A coarse grid keeps the widget tests fast; the model tests pin
          // the physics at full resolution.
          cellM: 1,
          rippleCenter: job.rippleCenter,
          rippleCells: 20,
          includeAverage: job.includeAverage,
        ),
      ),
    );
  }
}

Future<_SyncRunner> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  int preset = 0,
  RoomFieldRunner? runner,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final _SyncRunner sync = _SyncRunner();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: RoomPropagationScreen(
        runner: runner ?? sync.call,
        presetIndex: preset,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sync;
}

RoomPropagationController _controllerOf(WidgetTester tester) => tester
    .widget<RoomPropagationStage>(find.byType(RoomPropagationStage))
    .controller;

void main() {
  test('catalog registers room-propagation in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kRoomPropagationToolId,
    );
    expect(e.title, 'Room Propagation');
    expect(e.subgroup, 'RF and Propagation');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/room-propagation');
    expect(AppRouter.roomPropagation, '/tools/room-propagation');
    // The RF Attenuation calculator is a separate, untouched entry.
    expect(
      kToolCategories.any(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'rf-attenuation'),
      ),
      isTrue,
    );
  });

  testWidgets('stage and controls are separate widgets over one controller', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Room Propagation'), findsOneWidget);
    final RoomPropagationController c = _controllerOf(tester);
    expect(
      tester
          .widget<RoomPropagationControls>(find.byType(RoomPropagationControls))
          .controller,
      same(c),
    );
    expect(
      tester
          .widget<RoomPropagationReadouts>(find.byType(RoomPropagationReadouts))
          .controller,
      same(c),
    );
    // The dBm legend is always shown, with its ends labeled.
    expect(find.textContaining('Received power, dBm'), findsOneWidget);
    expect(find.text('<-90'), findsOneWidget);
    expect(find.text('-30'), findsOneWidget);
    // The 2D-of-3D disclaimer is on screen.
    expect(find.textContaining('A 2D plan of a 3D model'), findsOneWidget);
    expect(c.averageGrid, isNotNull);
    expect(c.rippleGrid, isNotNull);
  });

  testWidgets('loading: before the first map the plan says so', (
    WidgetTester tester,
  ) async {
    final Completer<RoomFieldResult> never = Completer<RoomFieldResult>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: RoomPropagationScreen(runner: (RoomFieldJob _) => never.future),
      ),
    );
    await tester.pump();
    expect(find.text('Computing the map'), findsWidgets);
    expect(find.text('Computing'), findsOneWidget);
    // Readouts do not wait for the map: they are one point each.
    expect(find.text('Received here'), findsWidgets);
  });

  testWidgets('error: a failed run says why and offers Try again', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final _SyncRunner ok = _SyncRunner();
    await _pump(
      tester,
      runner: (RoomFieldJob j) {
        calls++;
        if (calls == 1) return Future<RoomFieldResult>.error('isolate died');
        return ok.call(j);
      },
    );
    expect(find.textContaining('could not be computed'), findsOneWidget);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(_controllerOf(tester).averageGrid, isNotNull);
  });

  testWidgets('empty plan: free space, no walls listed', (
    WidgetTester tester,
  ) async {
    await _pump(tester, preset: RoomPropagationController.presets.length - 1);
    final RoomPropagationController c = _controllerOf(tester);
    expect(c.walls, isEmpty);
    expect(find.text('none (clear line)'), findsOneWidget);
    expect(find.text('No walls yet'), findsOneWidget);
    // No walls: received = EIRP - FSPL, 8 m on channel 6.
    final PointReport r = c.clientReport;
    expect(c.clientDbm, closeTo(c.eirpDbm - r.fsplDb, 1e-9));
  });

  testWidgets('thickness error keeps the last valid wall', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final RoomPropagationController c = _controllerOf(tester);
    c.selectWall(4);
    await tester.pumpAndSettle();
    final double before = c.walls[4].thicknessMm;
    final Finder field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Enter a thickness from 0.1 to 50 cm'), findsOneWidget);
    expect(c.walls[4].thicknessMm, before);
    await tester.enterText(field, '2.6');
    await tester.pumpAndSettle();
    expect(find.text('Enter a thickness from 0.1 to 50 cm'), findsNothing);
    expect(c.walls[4].thicknessMm, 26);
  });

  testWidgets('disabled: wall buttons wait for a selection', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    OutlinedButton btn(String label) => tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(btn('Delete wall').onPressed, isNull);
    expect(btn('Add a doorway').onPressed, isNull);
    _controllerOf(tester).selectWall(0);
    await tester.pumpAndSettle();
    expect(btn('Delete wall').onPressed, isNotNull);
    expect(btn('Add a doorway').onPressed, isNotNull);
    // The perimeter wall has no doorway yet.
    expect(btn('Close its doorways').onPressed, isNull);
  });

  testWidgets('band, reflections and diffraction reach the readouts', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final RoomPropagationController c = _controllerOf(tester);
    final double at24 = c.clientAverageDbm;
    c.band = WifiBand.band6;
    await tester.pumpAndSettle();
    expect(c.channel, 117);
    expect(c.freqMHz, 6535);
    expect(c.clientAverageDbm, lessThan(at24));
    c.reflectionOrder = 0;
    c.diffraction = false;
    await tester.pumpAndSettle();
    expect(find.text('off'), findsNWidgets(2));
    // Same spot on all three bands, current band included.
    expect(c.bandRows.map((RoomBandRow r) => r.band), WifiBand.values);
  });

  test(
    'compute: client moves redo only the close-up; EIRP redoes nothing',
    () async {
      final _SyncRunner r = _SyncRunner();
      final RoomPropagationController c = RoomPropagationController(
        runner: r.call,
      );
      await pumpEventQueue();
      expect(r.jobs, hasLength(1));
      expect(r.jobs.last.includeAverage, isTrue);
      c.moveClient(const P2(3, 3));
      await pumpEventQueue();
      expect(r.jobs, hasLength(2));
      expect(r.jobs.last.includeAverage, isFalse);
      expect(r.jobs.last.rippleCenter, const P2(3, 3));
      c.eirpDbm = 25;
      await pumpEventQueue();
      expect(r.jobs, hasLength(2));
      c.band = WifiBand.band5;
      await pumpEventQueue();
      expect(r.jobs.last.includeAverage, isTrue);
      expect(r.jobs.last.radio.freqMHz, 5500);
      c.dispose();
    },
  );

  test('compute: changes during a run coalesce into one follow-up', () async {
    final List<Completer<RoomFieldResult>> pending =
        <Completer<RoomFieldResult>>[];
    final List<RoomFieldJob> jobs = <RoomFieldJob>[];
    final RoomPropagationController c = RoomPropagationController(
      runner: (RoomFieldJob j) {
        jobs.add(j);
        final Completer<RoomFieldResult> done = Completer<RoomFieldResult>();
        pending.add(done);
        return done.future;
      },
    );
    for (int i = 0; i < 10; i++) {
      c.moveAp(P2(2 + i * 0.5, 5));
    }
    expect(jobs, hasLength(1));
    expect(c.computing, isTrue);
    pending.first.complete(computeRoomField(jobs.first));
    await pumpEventQueue();
    expect(jobs, hasLength(2));
    expect(jobs.last.ap, const P2(6.5, 5));
    pending.last.complete(computeRoomField(jobs.last));
    await pumpEventQueue();
    expect(c.computing, isFalse);
    expect(c.averageStale, isFalse);
    c.dispose();
  });

  test('plan tools: draw, too short, doorway, select, delete', () {
    final RoomPropagationController c = RoomPropagationController(
      runner: _SyncRunner().call,
      presetIndex: RoomPropagationController.presets.length - 1,
      autoCompute: false,
    );
    c.tool = RoomTool.wall;
    c.setMaterial(WallMaterial.concrete);
    c.setThicknessMm(150);
    c.startWall(const P2(5.02, 2));
    c.updateWall(const P2(5.04, 2.1));
    c.endWall();
    expect(c.walls, isEmpty);
    expect(c.message, contains('Drag farther'));
    c.startWall(const P2(5.02, 2));
    c.updateWall(const P2(5.04, 9.97));
    c.endWall();
    expect(c.walls, hasLength(1));
    // Snapped to the 10 cm grid.
    expect(c.walls.single.a, const P2(5, 2));
    expect(c.walls.single.b, const P2(5, 10));
    expect(c.walls.single.material, WallMaterial.concrete);
    expect(c.selectedWall, 0);
    // A second wall snaps onto the first wall's end.
    c.startWall(const P2(5.2, 10.1));
    c.updateWall(const P2(12, 10));
    c.endWall();
    expect(c.walls[1].a, const P2(5, 10));
    // Doorway by tap, then an overlapping one is refused.
    c.tool = RoomTool.door;
    c.tapDoor(const P2(5.1, 6), 0.3);
    expect(c.walls[0].doors, hasLength(1));
    c.tapDoor(const P2(5.1, 6.2), 0.3);
    expect(c.walls[0].doors, hasLength(1));
    expect(c.message, contains('already a doorway'));
    c.tapDoor(const P2(9, 3), 0.3);
    expect(c.message, contains('Tap on a wall'));
    // Select and delete.
    c.tool = RoomTool.select;
    c.tapSelect(const P2(8, 10.1), 0.3);
    expect(c.selectedWall, 1);
    c.deleteSelected();
    expect(c.walls, hasLength(1));
    expect(c.selectedWall, isNull);
    c.dispose();
  });

  test('plan tools: the wall limit', () {
    final RoomPropagationController c = RoomPropagationController(
      runner: _SyncRunner().call,
      presetIndex: RoomPropagationController.presets.length - 1,
      autoCompute: false,
    );
    for (int i = 0; i <= kMaxWalls; i++) {
      c.startWall(P2(1, 0.5 + i * 0.8));
      c.updateWall(P2(4, 0.5 + i * 0.8));
      c.endWall();
    }
    expect(c.walls, hasLength(kMaxWalls));
    expect(c.message, contains('up to $kMaxWalls walls'));
    c.dispose();
  });

  for (final bool light in <bool>[false, true]) {
    for (final double width in <double>[390, 1280]) {
      for (
        int preset = 0;
        preset < RoomPropagationController.presets.length;
        preset++
      ) {
        testWidgets(
          'lays out at ${width.toInt()} px, ${light ? 'light' : 'dark'}, '
          'preset $preset',
          (WidgetTester tester) async {
            await _pump(
              tester,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              width: width,
              height: 900,
              preset: preset,
            );
            expect(tester.takeException(), isNull);
            final RoomPropagationController c = _controllerOf(tester);
            c.reflectionOrder = 2;
            c.band = WifiBand.band6;
            await tester.pumpAndSettle();
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -3000),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
