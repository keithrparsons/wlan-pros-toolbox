// Render-proof capture for the shortcut-onboarding work (NOT a golden test).
//
// Writes PNG snapshots of the two new surfaces to the myPKA Deliverables folder
// so Vera (and Keith) can eyeball the not-set-up state and the install sheet
// without a device build:
//   * shortcut-onboarding-01-not-set-up-state.png — the iOS Wi-Fi Information
//     live screen, first-run (never received a payload): the prominent
//     "Set up live Wi-Fi (one-time)" prompt card under the Start bar.
//   * shortcut-onboarding-02-install-sheet.png — the one-time setup sheet with
//     the three crystal-clear steps and the "Add the Shortcut" button.
//
// This is a capture utility, not a regression gate (it does not compare against
// a baseline). Run it explicitly:
//   flutter test test/screens/tools/network/shortcut_onboarding_render.dart
// Renders use the production theme + the bundled typefaces loaded by
// flutter_test_config.dart, so the PNGs reflect shipping pixels.
//
// Note: toImage() is wrapped in tester.runAsync() — the PNG encode is a real
// async task that deadlocks inside the test's fake-async zone otherwise.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/install_shortcut_sheet.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-07-shortcut-onboarding-renders';

/// Fake iOS bridge: never received a payload → the not-set-up prompt shows.
class _FakeBridge implements WiFiDetailsBridge {
  @override
  Future<bool> hasEverReceivedPayload() async => false;

  @override
  Future<WiFiDetails?> readLatest() async => null;

  @override
  Future<bool> isMonitoringActive() async => false;

  @override
  Future<void> setMonitoringActive(bool active) async {}

  @override
  Future<bool> openUrl(String url) async => true;

  @override
  Future<bool> runShortcut(String name) async => true;

  @override
  Future<bool> runShortcutOneShot(String name) async => true;

  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  // The image encode must run on the real event loop, not the fake test zone.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('$_outDir/$filename');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('render: not-set-up state (Wi-Fi Information, iOS first run)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844)); // iPhone-ish
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _FakeBridge(),
          ),
        ),
      ),
    );
    // Bounded pumps (not pumpAndSettle): the iOS live screen mounts a controller
    // and async OUI load; pumpAndSettle can spin on repaints. A few fixed frames
    // let the not-set-up idle state resolve, then we snapshot it.
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Proof the surface is the intended one before we snapshot it. The redesign
    // (2026-06-07) replaced the redundant prompt with the LiveRfLockedCard as the
    // single enable affordance in the pre-payload state.
    expect(find.text('Live signal details'), findsOneWidget);
    expect(find.text('Enable live Wi-Fi'), findsOneWidget);

    await _capture(
      tester,
      boundaryKey,
      'shortcut-onboarding-01-not-set-up-state.png',
    );
  });

  testWidgets('render: install sheet (three steps)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xFF2A2A2A), // surface2 sheet bg
            body: Align(
              alignment: Alignment.bottomCenter,
              child: InstallShortcutSheet(
                openUrl: (String _) async => true,
                onInstalled: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Set up live Wi-Fi'), findsOneWidget);
    expect(find.text('Add the Shortcut'), findsOneWidget);

    await _capture(
      tester,
      boundaryKey,
      'shortcut-onboarding-02-install-sheet.png',
    );
  });
}
