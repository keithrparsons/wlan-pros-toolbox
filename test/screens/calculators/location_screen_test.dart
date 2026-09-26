// Widget tests for the Wi-Fi Classroom "Where Am I?" screen
// (location-rssi-ftm, spec 33).
//
// The math is pinned in test/services/wifi_lab/location_engine_test.dart;
// these cover the screen contract: catalog, route and icon, the stage and
// controls as separate widgets, dragging the device, the three methods, the
// blocked-path chips, the "impossible" note, the lesson, the copy text, the
// help entry (acronyms spelled out first, the vendor-document caution, the
// keys), no vendor or product named anywhere in the tool, illustrative values
// labeled, and phone and desktop widths in both themes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/location_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<LocationController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1024,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final LocationController c = LocationController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LocationScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// The floors' paint areas.
Finder _floors() => find.descendant(
  of: find.byType(LocationStage),
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == 'LocFloorPainter',
  ),
);

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kLocationToolId]
        as Map<String, dynamic>;

/// Every string of the help entry, in the order the help sheet shows them.
String _helpText() {
  final Map<String, dynamic> h = _help();
  final StringBuffer b = StringBuffer()
    ..writeln(h['name'])
    ..writeln(h['purpose'])
    ..writeln(h['whyHere']);
  for (final dynamic s in h['howToUse'] as List<dynamic>) {
    b.writeln(s);
  }
  for (final dynamic i in h['inputs'] as List<dynamic>) {
    final Map<String, dynamic> m = i as Map<String, dynamic>;
    b.writeln('${m['name']} ${m['unit']} ${m['range']}');
  }
  b
    ..writeln(h['algorithm'])
    ..writeln(h['example']);
  for (final dynamic s in h['fieldNotes'] as List<dynamic>) {
    b.writeln(s);
  }
  b.writeln(h['source']);
  return b.toString();
}

/// Every source file of the tool.
List<File> _toolSources() => <File>[
  File('lib/services/wifi_lab/location_engine.dart'),
  for (final FileSystemEntity e in Directory(
    'lib/screens/tools/calculators',
  ).listSync())
    if (e is File && e.path.split('/').last.startsWith('location_')) e,
];

void main() {
  test('catalog registers location-rssi-ftm in the Wi-Fi Classroom, with a '
      'route and an icon', () {
    final ToolCategory cls = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = cls.tools.firstWhere(
      (ToolEntry t) => t.id == kLocationToolId,
    );
    expect(e.title, 'Where Am I? Signal Strength vs Round-Trip Timing');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/location-rssi-ftm');
    expect(AppRouter.routes.containsKey(e.routeName), isTrue);
    expect(
      File('assets/tool-icons/location-rssi-ftm.svg').existsSync(),
      isTrue,
    );
    // The catalog description spells FTM out.
    expect(e.description, contains('fine timing measurement (FTM)'));
  });

  test('the id was not already taken by another tool', () {
    final int uses = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .where((ToolEntry t) => t.id == kLocationToolId)
        .length;
    expect(uses, 1);
  });

  testWidgets('opens on Both with stage and controls as separate widgets', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    expect(find.byType(LocationStage), findsOneWidget);
    expect(find.byType(LocationControls), findsOneWidget);
    expect(c.view, LocView.both);
    expect(_floors(), findsNWidgets(2));
    expect(
      find.text('Fine timing measurement (FTM): distance from the round trip'),
      findsOneWidget,
    );
    expect(find.textContaining('Position error'), findsWidgets);
  });

  testWidgets('the method toggle shows one floor or both', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    await _tap(tester, find.text('Signal strength').first);
    expect(c.view, LocView.signal);
    expect(_floors(), findsOneWidget);
    await _tap(tester, find.text('Timing'));
    expect(c.view, LocView.ftm);
    expect(_floors(), findsOneWidget);
  });

  testWidgets('a drag on the floor moves the device', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    final LocPoint before = c.device;
    await tester.ensureVisible(_floors().first);
    await tester.pumpAndSettle();
    await tester.drag(_floors().first, const Offset(120, 60));
    await tester.pumpAndSettle();
    expect(c.device, isNot(before));
    expect(c.device.x, inInclusiveRange(0, kLocFloorWidthM));
    expect(c.device.y, inInclusiveRange(0, kLocFloorDepthM));
  });

  testWidgets('blocking an AP reads long and draws "blocked"', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    c.ftmErrorM = 0.5;
    await tester.pump();
    final double before = c.run.drawn[1].ftmDistanceM;
    await _tap(tester, find.widgetWithText(FilterChip, 'AP 2'));
    expect(c.isBlocked(1), isTrue);
    expect(
      c.run.drawn[1].ftmDistanceM,
      closeTo(before + kLocDefaultBlockedBiasM, 1e-9),
    );
    expect(find.textContaining('AP 2, true'), findsOneWidget);
    expect(find.textContaining(', blocked'), findsOneWidget);
  });

  testWidgets('circles that cannot meet are called impossible, in words', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    c.view = LocView.ftm;
    c.ftmErrorM = 0.5;
    c.blockedBiasM = 10;
    c.toggleBlocked(0);
    c.toggleBlocked(1);
    c.toggleBlocked(2);
    c.toggleBlocked(3);
    // A device right beside AP 1: every other circle is long, AP 1's too.
    c.device = (x: 3.5, y: 3.5);
    await tester.pumpAndSettle();
    final bool any = c.run.ftm.nonMeetingPairs.isNotEmpty;
    expect(
      find.textContaining('Impossible: circles of APs'),
      any ? findsOneWidget : findsNothing,
    );
  });

  testWidgets('the impossible note shows for a known bad set of distances', (
    WidgetTester tester,
  ) async {
    final LocationController c = await _pump(tester);
    c.view = LocView.signal;
    c.sigmaDb = 10;
    await tester.pumpAndSettle();
    // Walk seeds until trial 0 has circles that cannot meet (sigma 10 dB
    // makes that common); the note must follow the flag.
    for (int i = 0; i < 40 && c.run.signal.nonMeetingPairs.isEmpty; i++) {
      c.resample();
    }
    await tester.pumpAndSettle();
    expect(c.run.signal.nonMeetingPairs, isNotEmpty);
    expect(find.textContaining('Impossible: circles of APs'), findsOneWidget);
  });

  testWidgets('predict, then reveal: -70 dBm', (WidgetTester tester) async {
    final LocationController c = await _pump(tester);
    await _tap(tester, find.text('Ask: -70 dBm, how far?'));
    expect(c.lesson, LocLessonStep.predict);
    expect(
      find.textContaining('How far away is it? Say a number'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Reveal the answer'));
    expect(c.lesson, LocLessonStep.revealed);
    // n = 3, 17 dBm, 5.5 GHz: 21.1 m, one sigma 13.3 m to 33.5 m.
    expect(find.textContaining('says 21.1 m'), findsOneWidget);
    expect(find.textContaining('from 13.3 m to 33.5 m'), findsOneWidget);
    expect(find.textContaining('illustrative'), findsWidgets);
  });

  testWidgets('the worked example reads x1.585, 6.3 m and 15.8 m', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('x1.585'), findsWidgets);
    expect(find.text('6.3 m'), findsOneWidget);
    expect(find.text('15.8 m'), findsOneWidget);
  });

  testWidgets('illustrative values are labeled; the timing figure names its '
      'source', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('Shadowing sigma (illustrative)'), findsOneWidget);
    expect(find.text('Each AP radiates (illustrative)'), findsOneWidget);
    expect(
      find.text('Blocked-path extra distance (illustrative)'),
      findsOneWidget,
    );
    expect(find.textContaining('vendor-documented 1 to 2 m'), findsOneWidget);
  });

  test('copy text spells out FTM and says what is illustrative', () {
    final LocationController c = LocationController();
    addTearDown(c.dispose);
    final String t = c.copyText();
    expect(t, contains('FTM (fine timing measurement)'));
    expect(t, contains('(illustrative)'));
    expect(t, contains('vendor-documented 1 to 2 m'));
    expect(t, contains('x1.585'));
    expect(t, contains('6.3 m to 15.8 m'));
  });

  group('help entry (spec 33)', () {
    test('mentions Present, the keys and the vendor-document caution', () {
      final String t = _helpText();
      expect(t, contains('Present'));
      for (final String key in <String>['Space', 'Tab', ' R ', 'Esc']) {
        expect(t, contains(key), reason: key);
      }
      expect(t, contains('vendor developer document'));
      expect(t, contains('designed for tablets and computers'));
    });

    test('FTM and RTT are spelled out before their short forms are used '
        'alone', () {
      final String t = _helpText();
      for (final (String short, String long) in <(String, String)>[
        ('FTM', 'fine timing measurement (FTM)'),
        ('RTT', 'round-trip time (RTT)'),
      ]) {
        final int first = RegExp('\\b$short\\b').firstMatch(t)!.start;
        final int spelled = t.toLowerCase().indexOf(long.toLowerCase());
        expect(spelled, greaterThanOrEqualTo(0), reason: long);
        expect(
          first,
          spelled + long.length - short.length - 1,
          reason: '$short is used before it is spelled out',
        );
      }
    });

    test('keywords from the spec are all there', () {
      const List<String> spec = <String>[
        'location',
        'positioning',
        'ftm',
        '802.11mc',
        'round trip time',
        'rtt',
        'trilateration',
        'rssi distance',
        'indoor location',
      ];
      final String src = File('lib/data/tool_keywords.dart').readAsStringSync();
      final int at = src.indexOf("'location-rssi-ftm': <String>[");
      expect(at, greaterThan(0));
      final String block = src.substring(at, src.indexOf('],', at));
      for (final String k in spec) {
        expect(block, contains("'$k'"), reason: k);
      }
    });
  });

  test('no string in the tool names a vendor or product', () {
    final StringBuffer all = StringBuffer(_helpText());
    for (final File f in _toolSources()) {
      all.writeln(f.readAsStringSync());
    }
    final String src = File('lib/data/tool_catalog.dart').readAsStringSync();
    final int at = src.indexOf("id: 'location-rssi-ftm'");
    all.writeln(src.substring(at, src.indexOf('),', at)));
    final String kw = File('lib/data/tool_keywords.dart').readAsStringSync();
    final int k = kw.indexOf("'location-rssi-ftm': <String>[");
    all.writeln(kw.substring(k, kw.indexOf('],', k)));
    final String t = all.toString().toLowerCase();
    expect(_toolSources().length, greaterThanOrEqualTo(7));
    for (final String banned in <String>[
      'android',
      'google',
      'apple',
      'ios',
      'iphone',
      'ipad',
      'macos',
      'microsoft',
      'pixel',
      'samsung',
      'galaxy',
      'qualcomm',
      'broadcom',
      'intel',
      'mediatek',
      'cisco',
      'aruba',
      'juniper',
      'mist',
      'meraki',
      'ruckus',
      'ubiquiti',
      'unifi',
      'ekahau',
      'hamina',
      'wifirttmanager',
      'wi-fi rtt',
      'wi-fi location',
      'wi-fi alliance',
    ]) {
      expect(
        RegExp('\\b${RegExp.escape(banned)}\\b').hasMatch(t),
        isFalse,
        reason: banned,
      );
    }
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
      testWidgets(
        '$name ${size.width.toInt()} wide: lays out with both floors, '
        'blocked APs, 6 APs and the lesson, no exception',
        (WidgetTester tester) async {
          final LocationController c = await _pump(
            tester,
            theme: theme(),
            width: size.width,
            height: size.height,
          );
          c.apCount = 6;
          c.toggleBlocked(0);
          c.toggleBlocked(4);
          c.sigmaDb = 10;
          c.nextReveal();
          c.nextReveal();
          c.device = (x: 29, y: 1);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(c.apCount, 6);
          expect(find.widgetWithText(FilterChip, 'AP 6'), findsOneWidget);
        },
      );
    }
  }
}
