// Widget tests for Antenna Pattern's Floor coverage view (spec 46): the view
// switch, the presets, the height slider and the readouts, the link into
// Uplink vs Downlink, the empty state, and the layout at phone, tablet and
// desktop widths in both themes with no overflow and no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FloorCoverageController _floorOf(WidgetTester tester) =>
    tester.widget<FloorCoverageStage>(find.byType(FloorCoverageStage)).floor;

void _noSideways(WidgetTester tester) {
  for (final ScrollableState each in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    if (each.position.axis == Axis.horizontal) {
      expect(each.position.maxScrollExtent, 0);
    }
  }
}

void main() {
  testWidgets('the view switch swaps the 3D stage for the floor and back', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(1280, 1600));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AntennaPatternScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AntennaPatternStage), findsOneWidget);
    expect(find.byType(FloorCoverageStage), findsNothing);

    await tester.tap(find.text('Floor coverage'));
    await tester.pumpAndSettle();
    expect(find.byType(FloorCoverageStage), findsOneWidget);
    expect(find.byType(AntennaPatternStage), findsNothing);
    expect(find.text('Directly below'), findsWidgets);
    // The antenna controls stay: one antenna, two views.
    expect(find.text('Antenna'), findsWidgets);

    await tester.tap(find.text('3D pattern'));
    await tester.pumpAndSettle();
    expect(find.byType(AntennaPatternStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset sets the antenna, height and power; moving a slider '
      'leaves it as your own settings', (WidgetTester tester) async {
    await _setSize(tester, const Size(1280, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    );
    await tester.pumpAndSettle();
    final FloorCoverageController f = _floorOf(tester);

    await tester.tap(find.text('Your own settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warehouse, dipole').last);
    await tester.pumpAndSettle();
    expect(f.preset, FloorPreset.warehouseDipole);
    expect(f.lab.kind, AntennaModelKind.dipole);
    expect(f.heightM, 9);
    expect(find.text('9.0 m (29.5 ft)'), findsWidgets);
    // The dipole's hole under the AP shows in words.
    expect(find.textContaining('out to 2.6 m'), findsOneWidget);

    f.nextPreset();
    await tester.pumpAndSettle();
    expect(f.preset, FloorPreset.warehouseHighGainOmni);
    expect(f.lab.omniGainDbi, 8);
    expect(find.textContaining('None: no floor'), findsOneWidget);

    f.setHeight(9.5);
    await tester.pumpAndSettle();
    expect(f.preset, isNull);
    expect(find.text('Your own settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the height slider moves by 0.5 m and the floor redraws', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(1280, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    );
    await tester.pumpAndSettle();
    final FloorCoverageController f = _floorOf(tester);
    f.applyPreset(FloorPreset.office);
    await tester.pumpAndSettle();
    final int before = f.revision;
    final double below3 = f.link!.at(0).downlinkDbm;

    final Finder slider = find.byWidgetPredicate(
      (Widget w) => w is Slider && w.min == kMountHeightMinM,
    );
    expect(slider, findsOneWidget);
    await tester.ensureVisible(slider);
    expect(tester.widget<Slider>(slider).divisions, 24);
    // A position between notches lands on the nearest 0.5 m.
    tester.widget<Slider>(slider).onChanged!(9.3);
    await tester.pumpAndSettle();
    expect(f.heightM, 9.5);
    expect(f.revision, greaterThan(before));

    f.setHeight(15);
    await tester.pumpAndSettle();
    expect(f.link!.at(0).downlinkDbm, lessThan(below3));
    expect(find.text('15.0 m (49.2 ft)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Open in Uplink vs Downlink carries the client\'s link', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(1280, 2600));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        // The real route table, without its home entry (the test supplies
        // the screen), so the push goes through the router's builder.
        routes: <String, WidgetBuilder>{
          AppRouter.uplinkDownlink: AppRouter.routes[AppRouter.uplinkDownlink]!,
        },
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    );
    await tester.pumpAndSettle();
    final FloorCoverageController f = _floorOf(tester);
    f.applyPreset(FloorPreset.warehouseDipole);
    f.setBand(WifiBand.band6);
    f.setClientTx(12);
    f.setExponent(2.5);
    f.setClientX(20);
    await tester.pumpAndSettle();
    final FloorPoint p = f.client!;
    expect(f.carriedGainClamped, isFalse);

    final Finder open = find.text('Open in Uplink vs Downlink');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    final UplinkDownlinkStage stage = tester.widget<UplinkDownlinkStage>(
      find.byType(UplinkDownlinkStage).first,
    );
    final c = stage.controller.config;
    expect(c.band, WifiBand.band6);
    expect(c.apTxDbm, 20);
    expect(c.clientTxDbm, 12);
    expect(c.exponent, 2.5);
    expect(c.apGainDbi, closeTo(p.gainDbi, 1e-9));
    expect(c.clientDistanceM, closeTo(p.slantM, 1e-9));
    // Same path, same gain, same powers: the same downlink number.
    expect(c.downlinkDbmAt(p.slantM), closeTo(p.downlinkDbm, 1e-6));
    expect(tester.takeException(), isNull);
  });

  test('a gain outside Uplink vs Downlink\'s 0 to 8 dBi is clamped and '
      'flagged', () {
    final AntennaPatternLab lab = AntennaPatternLab();
    final FloorCoverageController f = FloorCoverageController(lab: lab);
    addTearDown(() {
      f.dispose();
      lab.dispose();
    });
    f.applyPreset(FloorPreset.warehouseDipole);
    f.setClientX(0);
    expect(f.client!.gainDbi, lessThan(0));
    expect(f.carriedGainClamped, isTrue);
    expect(f.uplinkDownlinkConfig!.apGainDbi, 0);
  });

  testWidgets('an imported antenna with nothing read shows the empty state', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(390, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AntennaPatternScreen(
          initialKind: AntennaModelKind.imported,
          initialView: AntennaStageView.floor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No pattern to put on the floor'),
      findsOneWidget,
    );
    expect(find.textContaining('Waiting for a pattern'), findsOneWidget);
    final FloorCoverageController f = _floorOf(tester);
    f.lab.loadExample(PatternExample.dipole);
    await tester.pumpAndSettle();
    expect(find.textContaining('No pattern to put on the floor'), findsNothing);
    expect(f.link, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging along the floor moves the client', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(1280, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    );
    await tester.pumpAndSettle();
    final FloorCoverageController f = _floorOf(tester);
    final double x0 = f.clientXM;
    final Finder view = find.bySemanticsLabel(RegExp(r'^Side view'));
    await tester.drag(view, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(f.clientXM, greaterThan(x0));
  });

  for (final (String, ThemeData Function()) theme
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 768, 1280]) {
      testWidgets('${width.toInt()} px, ${theme.$1}: every preset, no '
          'overflow, no sideways scroll', (WidgetTester tester) async {
        await _setSize(tester, Size(width, 1000));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.$2(),
            home: const AntennaPatternScreen(
              initialView: AntennaStageView.floor,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final FloorCoverageController f = _floorOf(tester);
        for (final FloorPreset p in FloorPreset.values) {
          f.applyPreset(p);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: p.name);
          _noSideways(tester);
        }
        // A wall mount and the extremes of height draw too.
        f.lab.setMount(AntennaMount.wall);
        f.setHeight(kMountHeightMaxM);
        f.setClientX(kFloorClientMaxM);
        await tester.pumpAndSettle();
        f.setHeight(kMountHeightMinM);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Vera gate B (2026-09-29): under the 9 m dipole the stage showed
  // "-114.2 dBm" in headline type. That is the model holding the dipole's
  // null 60 dB under the peak, not a level any client can read. Readings
  // under kFloorReadableDbm say "below -95 dBm", with "(null)" in the
  // pattern's null; the exact figure stays only in the note in the readouts.
  test('a level under -95 dBm reads as a bound, with (null) in a null', () {
    expect(kFloorReadableDbm, -95);
    expect(fmtFloorLevelDbm(-94.9, inNull: false), '−94.9 dBm');
    expect(fmtFloorLevelDbm(-94.9, inNull: true), '−94.9 dBm');
    expect(fmtFloorLevelDbm(-95.1, inNull: false), 'below −95 dBm');
    expect(fmtFloorLevelDbm(-114.2, inNull: true), 'below −95 dBm (null)');
    expect(fmtFloorLevelDb(-114.2, inNull: true), 'below −95 (null)');
    expect(fmtFloorLevelDb(-80.04, inNull: true), '−80.0');
  });

  testWidgets('the 9 m dipole: the null reads "below -95 dBm (null)", the '
      'exact figure only in the note', (WidgetTester tester) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _setSize(tester, const Size(1280, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    );
    await tester.pumpAndSettle();
    final FloorCoverageController f = _floorOf(tester);
    f.applyPreset(FloorPreset.warehouseDipole);
    f.setClientX(10);
    await tester.pumpAndSettle();
    expect(f.link!.at(0).downlinkDbm, closeTo(-114.2, 0.05));

    // The headline is presenter-only (antenna_floor_presenter_test.dart).
    final Finder stage = find.byType(FloorCoverageStage);
    expect(
      find.descendant(of: stage, matching: find.textContaining('114.2')),
      findsNothing,
    );
    // The stage label no longer quotes the model's 60 dB floor.
    expect(
      find.descendant(of: stage, matching: find.textContaining('60.0 dB')),
      findsNothing,
    );
    // Readouts: both directions directly below are under -95 dBm.
    expect(find.text('below −95 (null)'), findsNWidgets(2));
    // The exact figures, with the caveat, in the note only.
    final Finder note = find.textContaining('−114.2 dBm');
    expect(note, findsOneWidget);
    expect(
      tester.widget<Text>(note).data ?? '',
      allOf(contains('−120.2 dBm'), contains('60 dB under the peak')),
    );

    await tester.tap(find.byTooltip('Copy results'));
    await tester.pump();
    expect(copied, hasLength(1));
    expect(copied.single, contains('below −95 dBm (null)'));
    expect(copied.single, isNot(contains('114.2')));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
