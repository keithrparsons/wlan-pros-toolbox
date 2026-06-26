// Render-proof capture for the iOS live-Wi-Fi onboarding redesign (2026-06-07).
//
// NOT a regression gate — a capture utility that writes PNG snapshots of the
// redesigned surfaces to the myPKA Deliverables folder so Vera (and Keith) can
// eyeball them without a device build. Run it explicitly:
//   flutter test test/screens/tools/network/ios_onboarding_render.dart
//
// Captures (dark + light each, where it adds signal):
//   01 native-first: real SSID/BSSID/security identity + LiveRfLockedCard (dark)
//   02 native-first (light)
//   03 locked card only, no native identity yet — single "Enable live Wi-Fi" CTA
//   04 the one-time onboarding / install sheet (3 steps, no-Location trust note)
//   05 the Test My Connection front door idle state (the mandatory-onboarding
//      entry point)
//
// Renders use the production theme + bundled typefaces (flutter_test_config.dart)
// so the PNGs reflect shipping pixels. toImage() runs inside tester.runAsync()
// because the PNG encode is a real async task.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:net_quality/net_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/install_shortcut_sheet.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus;
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-07-ios-onboarding-renders';

/// iOS bridge: never received a payload → the pre-payload onboarding state.
class _FreshBridge implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
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

/// A security service returning the real native NEHotspotNetwork identity.
WifiSecurityService _availableSecurity() => WifiSecurityService(
      invoke: (String method, [dynamic args]) async {
        switch (method) {
          case 'getSecurityInfo':
            return <String, dynamic>{
              'available': true,
              'securityToken': 'personal',
              'bssid': 'a4:83:e7:00:11:22',
              'ssid': 'KeithNet',
              'locationAuthorized': true,
            };
          case 'isLocationAuthorized':
            return true;
          default:
            return null;
        }
      },
    );

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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

Future<void> _pumpFrames(WidgetTester tester, [int n = 10]) async {
  for (int i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> renderWifiInfo(
    WidgetTester tester, {
    required ThemeData theme,
    required bool withNativeIdentity,
    required String filename,
    required Finder proof,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: theme,
          home: WifiInfoScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _FreshBridge(),
            securityService: withNativeIdentity ? _availableSecurity() : null,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(proof, findsWidgets);
    await _capture(tester, boundaryKey, filename);
  }

  testWidgets('01 native-first identity + locked card (dark)', (tester) async {
    await renderWifiInfo(
      tester,
      theme: AppTheme.dark(),
      withNativeIdentity: true,
      filename: '01-native-first-dark.png',
      proof: find.text('Live signal details'),
    );
  });

  testWidgets('02 native-first identity + locked card (light)', (tester) async {
    await renderWifiInfo(
      tester,
      theme: AppTheme.light(),
      withNativeIdentity: true,
      filename: '02-native-first-light.png',
      proof: find.text('Live signal details'),
    );
  });

  testWidgets('03 locked card only — single Enable CTA (dark)', (tester) async {
    await renderWifiInfo(
      tester,
      theme: AppTheme.dark(),
      withNativeIdentity: false,
      filename: '03-locked-card-no-identity-dark.png',
      proof: find.text('Enable live Wi-Fi'),
    );
  });

  testWidgets('04 onboarding / install sheet (dark)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xFF2A2A2A),
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
    await _pumpFrames(tester, 4);
    expect(find.text('Set up live Wi-Fi'), findsOneWidget);
    await _capture(tester, boundaryKey, '04-onboarding-sheet-dark.png');
  });

  testWidgets('05 Test My Connection front door idle (dark)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            enableLiveSampling: false,
            // macOS source so the idle front door renders without the iOS
            // onboarding sheet auto-covering it (the sheet is captured in 04).
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _NoopMacAdapter(),
            qualityClient: MockQualityClient(),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('Check My Connection'), findsOneWidget);
    await _capture(tester, boundaryKey, '05-tmc-front-door-dark.png');
  });
}

/// A no-op macOS adapter so the TMC front door renders its idle state.
class _NoopMacAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() => throw UnimplementedError();
  @override
  Future<bool> requestNamePermission() async => false;
  @override
  Future<bool> currentNameAuthorization() async => false;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.notDetermined;
  @override
  Future<bool> openNamePermissionSettings() async => false;
}
