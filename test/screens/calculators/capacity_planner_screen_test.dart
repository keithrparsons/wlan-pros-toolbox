// Tests for the Wi-Fi Capacity Planner calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcCapacity):
//   concurrent  = ceil(users * conc% / 100)
//   totalBW     = concurrent * perUser
//   effectiveAP = apMax * util% / 100
//   apsByTput   = ceil(totalBW / effectiveAP)
//   apsByDens   = (maxCli > 0) ? ceil(concurrent / maxCli) : 0
//   recommended = max(apsByTput, apsByDens, 1)
// Expected values below were computed from that exact formula so the native app
// and PWA agree.
//
// One widget test confirms the screen pumps inside a phone viewport and renders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/capacity_planner_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Capacity math (pure) — matches PWA app.js calcCapacity', () {
    test('typical office plan (200 users, 70%, 5/600/50%, 50 max)', () {
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 200,
        concurrentPct: 70,
        perUserMbps: 5,
        apMaxMbps: 600,
        targetUtilPct: 50,
        maxClients: 50,
      );
      expect(r, isNotNull);
      expect(r!.concurrent, 140); // ceil(200 * 0.70)
      expect(r.totalBwMbps, 700); // 140 * 5
      expect(r.apsByThroughput, 3); // ceil(700 / 300)
      expect(r.apsByDensity, 3); // ceil(140 / 50)
      expect(r.recommended, 3); // max(3, 3, 1)
    });

    test('concurrent count rounds up (ceil)', () {
      // ceil(101 * 0.55) = ceil(55.55) = 56
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 101,
        concurrentPct: 55,
        perUserMbps: 2,
        apMaxMbps: 1000,
        targetUtilPct: 50,
      );
      expect(r!.concurrent, 56);
      expect(r.totalBwMbps, 112); // 56 * 2
      expect(r.apsByThroughput, 1); // ceil(112 / 500)
    });

    test('density check drives the recommendation when it exceeds throughput',
        () {
      // throughput needs few APs, but 300 concurrent at 50/AP forces 6.
      // concurrent = ceil(500 * 0.60) = 300
      // totalBW = 300 * 2 = 600; effectiveAP = 1000 * 0.50 = 500
      // apsByTput = ceil(600/500) = 2; apsByDens = ceil(300/50) = 6
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 500,
        concurrentPct: 60,
        perUserMbps: 2,
        apMaxMbps: 1000,
        targetUtilPct: 50,
        maxClients: 50,
      );
      expect(r!.apsByThroughput, 2);
      expect(r.apsByDensity, 6);
      expect(r.recommended, 6); // max(2, 6, 1)
    });

    test('no max-clients disables the density check (apsByDensity = 0)', () {
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 200,
        concurrentPct: 70,
        perUserMbps: 5,
        apMaxMbps: 600,
        targetUtilPct: 50,
        maxClients: null,
      );
      expect(r!.apsByDensity, 0);
      expect(r.recommended, r.apsByThroughput); // falls back to throughput
    });

    test('recommended never drops below 1', () {
      // Tiny demand: 1 user, 1 Mbps, huge AP. apsByTput = ceil(1/500) = 1.
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 1,
        concurrentPct: 100,
        perUserMbps: 1,
        apMaxMbps: 1000,
        targetUtilPct: 50,
      );
      expect(r!.recommended, 1);
    });
  });

  group('Capacity math — invalid input returns null (PWA showError guards)', () {
    test('missing required field → null', () {
      expect(
        CapacityPlannerScreen.compute(
          users: null,
          concurrentPct: 70,
          perUserMbps: 5,
          apMaxMbps: 600,
          targetUtilPct: 50,
        ),
        isNull,
      );
    });

    test('non-positive required field → null', () {
      expect(
        CapacityPlannerScreen.compute(
          users: 200,
          concurrentPct: 0,
          perUserMbps: 5,
          apMaxMbps: 600,
          targetUtilPct: 50,
        ),
        isNull,
      );
      expect(
        CapacityPlannerScreen.compute(
          users: 200,
          concurrentPct: 70,
          perUserMbps: 5,
          apMaxMbps: -10,
          targetUtilPct: 50,
        ),
        isNull,
      );
    });

    test('non-positive max-clients is treated as no density check', () {
      final CapacityResult? r = CapacityPlannerScreen.compute(
        users: 200,
        concurrentPct: 70,
        perUserMbps: 5,
        apMaxMbps: 600,
        targetUtilPct: 50,
        maxClients: 0,
      );
      expect(r, isNotNull);
      expect(r!.apsByDensity, 0);
    });
  });

  group('CapacityPlannerScreen widget', () {
    testWidgets('renders title, input labels, and headline output', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Capacity Planner'), findsWidgets);
        expect(find.text('Total users'), findsOneWidget);
        expect(find.text('Concurrent usage'), findsOneWidget);
        expect(find.text('AP max throughput'), findsOneWidget);
        expect(find.text('Recommended access points'), findsOneWidget);
        // Six inputs: users, conc, per-user, ap-max, util, max-clients.
        expect(find.byType(TextField), findsNWidgets(6));
      });
    });

    testWidgets('typing a full valid plan renders the recommended AP count', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '200'); // users
        await tester.enterText(fields.at(1), '70'); // conc %
        await tester.enterText(fields.at(2), '5'); // per-user Mbps
        await tester.enterText(fields.at(3), '600'); // AP max Mbps
        await tester.enterText(fields.at(4), '50'); // util %
        await tester.enterText(fields.at(5), '50'); // max clients
        await tester.pump();

        // recommended = 3, concurrent = 140, demand = 700 Mbps.
        expect(find.text('3'), findsWidgets);
        expect(find.text('140'), findsOneWidget);
        expect(find.text('700 Mbps'), findsOneWidget);
      });
    });

    testWidgets('incomplete input keeps the output blank (dash, no crash)', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        // Only one required field filled → still blank.
        await tester.enterText(fields.at(0), '200');
        await tester.pump();

        expect(find.text('—'), findsWidgets);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport`.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
