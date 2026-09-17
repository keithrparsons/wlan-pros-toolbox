// The path no other screen test exercises: widget.client == null.
//
// WHY THIS FILE EXISTS. Join a Network shipped to Keith's Mac on 2026-09-17
// showing "Open this from a WLAN Pi" even though macOS had just gained a native
// join. The backend selection was correct; an early-return guard in front of it
// still asked only "is a Pi serving?" and answered no.
//
// EVERY OTHER SCREEN TEST INJECTS A CLIENT, which makes the guard's first
// clause false and skips the block entirely. So the whole suite was green and
// the one path a real user takes was broken. That is the gap this closes.
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/join_network_screen.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend_selector.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

/// A backend that answers without touching a method channel or a Pi.
class _Native implements JoinBackend {
  @override
  bool get joinsThisDevice => true;
  @override
  Future<List<PiScanInterface>> radios() async => const <PiScanInterface>[];
  @override
  Future<List<PiScanNet>> scan({String? interface}) async => const <PiScanNet>[
    PiScanNet(
      ssid: 'Keith-IoT',
      bssid: 'aa:bb:cc:dd:ee:01',
      signalDbm: -42,
      freqMhz: 2462,
      keyMgmt: 'wpa-psk',
    ),
  ];
  @override
  Future<JoinOutcome> join({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async => JoinOutcome(connected: true, ssid: ssid);
  @override
  Future<JoinOutcome> disconnect({String? interface}) async =>
      const JoinOutcome(connected: false, ssid: null);
}

void main() {
  // DECLARE THE PLATFORM RATHER THAN INHERIT IT.
  //
  // These assertions are about macOS. They used to rely on dart:io reading the
  // HOST machine, which happened to be a Mac -- so they would have asserted
  // something different on a Windows dev box, silently. The production code now
  // reads defaultTargetPlatform, which under flutter_test defaults to ANDROID
  // regardless of host, so the platform has to be stated.
  // A widget test checks that foundation debug variables are unset at the end of
  // the TEST BODY, which runs BEFORE tearDown -- so setUp/tearDown cannot carry
  // this and each body sets and clears it itself, in a finally so a failing
  // expect still leaves the global clean for the next test.
  Future<void> asMacOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('with NO client injected, a native platform does not show the '
      'WLAN Pi fallback', (WidgetTester tester) async {
    await asMacOS(() async {
      await tester.pumpWidget(
        MaterialApp(home: JoinNetworkScreen(backend: _Native())),
      );
      await tester.pump();

      expect(
        find.text('Open this from a WLAN Pi'),
        findsNothing,
        reason:
            'this Mac joins with its own radio, so the Pi fallback is a '
            'false statement and the screen must not show it',
      );
      expect(find.textContaining('it needs a WLAN Pi'), findsNothing);
    });
  });

  testWidgets('the network list is reachable on a native platform', (
    WidgetTester tester,
  ) async {
    await asMacOS(() async {
      await tester.pumpWidget(
        MaterialApp(home: JoinNetworkScreen(backend: _Native())),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keith-IoT'),
        findsWidgets,
        reason: 'the scan the native backend returned must reach the screen',
      );
    });
  });

  test('the precondition this whole file depends on', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(
      deviceCanJoinNatively,
      isTrue,
      reason:
          'these assertions only mean something on a platform that can '
          'join for itself; on iOS or Android the fallback IS correct',
    );
  });
}
