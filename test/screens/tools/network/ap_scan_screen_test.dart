// Nearby AP Scan screen — widget tests (Android + macOS tool, H3).
//
// The screen reads APs through the `com.wlanpros.toolbox/ap_scan` method
// channel behind the [ApScanService] seam. The tests drive it with an
// [ApScanService] whose `invoke` is a fake and whose `platformOverride` selects
// the supported (android / macos) or unsupported (ios / windows) branch — no
// real channel.
//
// Covers the SOP-007 §5 state matrix plus the load-bearing honesty rules:
//   * list renders (SSID / BSSID / channel / band / RSSI) on BOTH wired
//     platforms, from ONE payload shape and ONE model.
//   * channel-occupancy bars render for 2.4 and 5 GHz.
//   * CLEAN fields only — no Noise / SNR / MCS column ever appears.
//   * on an unwired platform the screen shows the honest per-platform
//     unavailable state and never scans; Windows copy says the path isn't wired
//     yet (not an Apple block).
//   * TWO KINDS OF NULL: an unauthorized scan says the scan could not run and
//     never claims an empty RF environment; a scan that RAN and found nothing
//     says exactly that. The two states must not be confusable.
//   * sort control reorders the list.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ap_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Builds a native-shaped scan payload (the map the Kotlin channel returns).
Map<String, Object?> _payload({
  List<Map<String, Object?>>? aps,
  bool poweredOn = true,
  bool locationAuthorized = true,
  bool scanThrottled = false,
}) {
  return <String, Object?>{
    'poweredOn': poweredOn,
    'locationAuthorized': locationAuthorized,
    'scanThrottled': scanThrottled,
    'accessPoints': aps ??
        <Map<String, Object?>>[
          <String, Object?>{
            'ssid': 'KeithNet',
            'bssid': 'a4:83:e7:00:11:22',
            'rssiDbm': -42,
            'channel': 36,
            'band': '5 GHz',
            'frequencyMhz': 5180,
          },
          <String, Object?>{
            'ssid': 'Neighbor-2G',
            'bssid': 'b8:27:eb:aa:bb:cc',
            'rssiDbm': -71,
            'channel': 6,
            'band': '2.4 GHz',
            'frequencyMhz': 2437,
          },
          <String, Object?>{
            'ssid': null, // hidden network
            'bssid': 'c0:ff:ee:00:00:01',
            'rssiDbm': -80,
            'channel': 6,
            'band': '2.4 GHz',
            'frequencyMhz': 2437,
          },
        ],
  };
}

/// An [ApScanService] backed by a fake invoke that always returns [payload] for
/// scan/lastResults and reports Location granted. [platform] selects the
/// supported/unsupported branch.
ApScanService _service(
  Map<String, Object?> payload, {
  String platform = 'android',
}) {
  return ApScanService(
    platformOverride: platform,
    invoke: (String method, [dynamic args]) async {
      switch (method) {
        case 'scan':
        case 'lastResults':
          return payload;
        case 'isLocationAuthorized':
          return payload['locationAuthorized'];
        case 'requestLocationPermission':
          return true;
        case 'openLocationSettings':
          return true;
      }
      return null;
    },
  );
}

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  /// One native-shaped scan row, so a test can vary exactly the field under
  /// examination (usually `bssid`) and leave the rest well-formed.
  Map<String, Object?> row({
    String? ssid,
    String? bssid,
    int channel = 6,
    int rssi = -70,
  }) =>
      <String, Object?>{
        'ssid': ssid,
        'bssid': bssid,
        'rssiDbm': rssi,
        'channel': channel,
        'band': '2.4 GHz',
        'frequencyMhz': 2437,
      };

  group('ApScanScreen — Android (supported)', () {
    testWidgets('renders the AP list with SSID / BSSID / channel / band / RSSI',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
      expect(find.text('-42 dBm'), findsOneWidget);
      expect(find.text('ch 36 · 5 GHz'), findsOneWidget);
      // Hidden network renders an honest label, never a blank.
      expect(find.text('(hidden network)'), findsOneWidget);
    });

    testWidgets('renders channel-occupancy bars for 2.4 and 5 GHz',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.text('2.4 GHz channel occupancy'), findsOneWidget);
      expect(find.text('5 GHz channel occupancy'), findsOneWidget);
      // Channel 6 has two APs (Neighbor-2G + hidden) → "2 APs".
      expect(find.text('2 APs'), findsOneWidget);
      // Channel 36 has one AP → "1 AP".
      expect(find.text('1 AP'), findsWidgets);
    });

    testWidgets('CLEAN fields only — no Noise / SNR / MCS anywhere',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Noise'), findsNothing);
      expect(find.textContaining('SNR'), findsNothing);
      expect(find.textContaining('MCS'), findsNothing);
    });

    testWidgets('sort control reorders the list (Channel asc)',
        (tester) async {
      await tester.pumpWidget(host(ApScanScreen(service: _service(_payload()))));
      await tester.pumpAndSettle();

      // Tap the "Channel" sort segment.
      await tester.tap(find.text('Channel'));
      await tester.pumpAndSettle();

      // Channel-asc puts the ch-6 APs above the ch-36 AP. Find their row
      // vertical positions and assert the order.
      final double neighborY =
          tester.getTopLeft(find.text('Neighbor-2G')).dy;
      final double keithY = tester.getTopLeft(find.text('KeithNet')).dy;
      expect(neighborY, lessThan(keithY));
    });

    testWidgets('Wi-Fi off shows the off card and no list', (tester) async {
      final Map<String, Object?> off = _payload(
        aps: const <Map<String, Object?>>[],
        poweredOn: false,
      );
      await tester.pumpWidget(host(ApScanScreen(service: _service(off))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Wi-Fi is off'), findsOneWidget);
    });

    testWidgets('Location not granted shows the Location-gate card',
        (tester) async {
      final Map<String, Object?> gated = _payload(
        aps: const <Map<String, Object?>>[],
        locationAuthorized: false,
      );
      await tester.pumpWidget(host(ApScanScreen(service: _service(gated))));
      await tester.pumpAndSettle();

      expect(find.text('Grant Location'), findsOneWidget);
      expect(
        find.textContaining('Location permission to read Wi-Fi scan'),
        findsOneWidget,
      );
    });

    testWidgets('throttled fresh scan surfaces the "last scan" note',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(scanThrottled: true)))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Android throttled'), findsOneWidget);
      // The list still renders from the cached scan.
      expect(find.text('KeithNet'), findsOneWidget);
    });
  });

  group('ApScanScreen — macOS (supported, same model as Android)', () {
    // The macOS CoreWLAN channel returns the SAME payload shape as the Android
    // channel, so the SAME fixture drives both. If macOS ever needed its own
    // fixture, the "one model" contract would already be broken.
    testWidgets('renders the AP list from the identical native payload',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('a4:83:e7:00:11:22'), findsOneWidget);
      expect(find.text('-42 dBm'), findsOneWidget);
      expect(find.text('(hidden network)'), findsOneWidget);
      // The unwired-platform card must NOT appear on a wired platform.
      expect(find.textContaining('Not wired'), findsNothing);
    });

    testWidgets('CLEAN fields only — no Noise / SNR / MCS on macOS either',
        (tester) async {
      // CoreWLAN exposes no per-neighbour noise floor. Nothing may be derived
      // from the connected interface's noise to fill the gap.
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Noise'), findsNothing);
      expect(find.textContaining('SNR'), findsNothing);
      expect(find.textContaining('MCS'), findsNothing);
    });

    testWidgets('throttle note names the macOS reason, not Android throttling',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(
          service: _service(_payload(scanThrottled: true), platform: 'macos'),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('A fresh scan ran moments ago'), findsOneWidget);
      expect(find.textContaining('Android'), findsNothing);
    });

    testWidgets('Location gate names the macOS reason (Location Services)',
        (tester) async {
      final Map<String, Object?> gated = _payload(
        aps: const <Map<String, Object?>>[],
        locationAuthorized: false,
      );
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(gated, platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('macOS requires Location Services'),
        findsOneWidget,
      );
      // Android's wording must not leak onto macOS.
      expect(find.textContaining('Android requires'), findsNothing);
    });

    testWidgets('wide window renders the desktop column layout',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      // Desktop-only column headings appear, and the list still renders.
      expect(find.text('NETWORK'), findsOneWidget);
      expect(find.text('BSSID'), findsOneWidget);
      expect(find.text('SIGNAL'), findsOneWidget);
      expect(find.text('CHANNEL'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ApScanScreen — the two kinds of null', () {
    // The load-bearing distinction. An empty list under a missing Location
    // grant means "the app measured nothing". An empty list from a scan that
    // RAN means "there is nothing on the air". Rendering them the same way
    // would state a verdict the app never took
    // ([[feedback_app_blames_the_wifi]]).
    for (final String os in const <String>['android', 'macos']) {
      testWidgets('$os: unauthorized says the scan could NOT run, and never '
          'claims an empty RF environment', (tester) async {
        final Map<String, Object?> gated = _payload(
          aps: const <Map<String, Object?>>[],
          locationAuthorized: false,
        );
        await tester.pumpWidget(
          host(ApScanScreen(service: _service(gated, platform: os))),
        );
        await tester.pumpAndSettle();

        // Says the scan did not run, and offers the way to fix it.
        expect(find.textContaining('scan could not run'), findsOneWidget);
        expect(find.text('Grant Location'), findsOneWidget);
        // Must NOT show the genuinely-empty copy.
        expect(find.textContaining('The scan ran and found no'), findsNothing);
        expect(find.textContaining('found no access points'), findsNothing);
      });

      testWidgets('$os: authorized + powered + zero APs says the scan RAN and '
          'found nothing, with no Location card', (tester) async {
        final Map<String, Object?> empty = _payload(
          aps: const <Map<String, Object?>>[],
        );
        await tester.pumpWidget(
          host(ApScanScreen(service: _service(empty, platform: os))),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('The scan ran and found no'), findsOneWidget);
        // No gate card, because nothing gated it.
        expect(find.text('Grant Location'), findsNothing);
        expect(find.textContaining('scan could not run'), findsNothing);
      });

      testWidgets('$os: Wi-Fi off says the scan could NOT run, not "no networks"',
          (tester) async {
        final Map<String, Object?> off = _payload(
          aps: const <Map<String, Object?>>[],
          poweredOn: false,
        );
        await tester.pumpWidget(
          host(ApScanScreen(service: _service(off, platform: os))),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('could not run'), findsWidgets);
        expect(find.textContaining('The scan ran and found no'), findsNothing);
      });
    }
  });

  group('ApScanScreen — unwired platforms', () {
    testWidgets('iOS shows the honest OS-block copy (iOS only, not macOS)',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'ios'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Runs on Android and macOS'), findsOneWidget);
      expect(
        find.textContaining('iOS blocks nearby-AP scanning'),
        findsOneWidget,
      );
      // The OS-block claim is iOS-scoped; macOS must not be blamed.
      expect(find.textContaining('macOS block'), findsNothing);
      // No list, no AP names on an unwired platform.
      expect(find.text('KeithNet'), findsNothing);
    });

    testWidgets('Windows says the scan path is not wired yet (never an Apple '
        'block, never "can\'t")', (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'windows'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not wired for Windows yet'), findsOneWidget);
      expect(
        find.textContaining('Windows can list nearby access points'),
        findsOneWidget,
      );
      // Must NOT blame Apple or claim Windows fundamentally can't scan.
      expect(find.textContaining('Apple'), findsNothing);
      expect(find.textContaining('block'), findsNothing);
      expect(find.text('KeithNet'), findsNothing);
    });

    testWidgets('an unwired platform never touches the scan channel',
        (tester) async {
      bool touched = false;
      final ApScanService svc = ApScanService(
        platformOverride: 'windows',
        invoke: (String method, [dynamic args]) async {
          if (method == 'scan' || method == 'lastResults') touched = true;
          return _payload();
        },
      );
      await tester.pumpWidget(host(ApScanScreen(service: svc)));
      await tester.pumpAndSettle();

      expect(touched, isFalse);
      expect(find.text('Not wired for Windows yet'), findsOneWidget);
    });

    testWidgets('Windows stays DARK: it is not a supported platform',
        (tester) async {
      // Keith's explicit call. The Windows Native Wifi enumeration path exists
      // in the codebase but is unverified on real hardware, so the UI must not
      // treat Windows as wired. This test is the guard on that decision.
      final ApScanService svc = ApScanService(
        platformOverride: 'windows',
        invoke: (String method, [dynamic args]) async => _payload(),
      );
      expect(svc.isSupportedPlatform, isFalse);
      expect(svc.platformStatus, ApScanPlatformStatus.windowsNotWired);
    });
  });

  group('ApScanScreen — channel error', () {
    testWidgets('channel error shows the error card + Retry', (tester) async {
      final ApScanService svc = ApScanService(
        platformOverride: 'android',
        invoke: (String method, [dynamic args]) async {
          if (method == 'scan' || method == 'lastResults') {
            throw PlatformException(code: 'ERR', message: 'scan failed');
          }
          return true;
        },
      );
      await tester.pumpWidget(host(ApScanScreen(service: svc)));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('scan failed'), findsOneWidget);
    });
  });

  group('ApScanService.platformStatus — honest per-platform mapping', () {
    ApScanService svc(String os) => ApScanService(
          platformOverride: os,
          invoke: (String method, [dynamic args]) async => _payload(),
        );

    test('android is a supported (wired) status', () {
      expect(svc('android').platformStatus, ApScanPlatformStatus.supported);
      expect(svc('android').isSupportedPlatform, isTrue);
      expect(svc('android').platformName, 'Android');
    });

    test('iOS is a true OS-level Apple restriction (no scan API)', () {
      expect(svc('ios').platformStatus, ApScanPlatformStatus.appleRestricted);
    });

    test('macOS is a supported (wired) status via CoreWLAN', () {
      expect(svc('macos').platformStatus, ApScanPlatformStatus.supported);
      expect(svc('macos').isSupportedPlatform, isTrue);
      expect(svc('macos').platformName, 'macOS');
    });

    test('windows maps to not-wired-yet, NOT an OS block', () {
      expect(
        svc('windows').platformStatus,
        ApScanPlatformStatus.windowsNotWired,
      );
    });

    test('other native platforms map to generic unavailable', () {
      expect(svc('linux').platformStatus, ApScanPlatformStatus.unavailable);
    });
  });

  // -------------------------------------------------------------------------
  // A WITHHELD IDENTITY IS NOT A HIDDEN NETWORK
  //
  // macOS strips the SSID *and* the BSSID of every scanned BSS when Location is
  // revoked. Those rows used to survive to the UI, where a null SSID renders
  // "(hidden network)" — a permission fact told as an RF claim that the AP is
  // cloaking. An engineer acts on a cloaked SSID; they would be chasing an RF
  // problem that does not exist ([[feedback_app_blames_the_wifi]]).
  //
  // The discriminator that must survive: a GENUINELY hidden BSS still has a
  // BSSID. That is the only thing separating the two, so it is what the model
  // keys on.
  // -------------------------------------------------------------------------
  group('withheld identity vs hidden network', () {
    test('a row with no BSSID is DROPPED, not modeled', () {
      // Both fields stripped by the OS = identity withheld.
      expect(ScannedAp.fromMap(row(ssid: null, bssid: null)), isNull);
      expect(ScannedAp.fromMap(row(ssid: null, bssid: '')), isNull);
    });

    test('a genuinely hidden BSS keeps its BSSID and SURVIVES', () {
      final ScannedAp? ap =
          ScannedAp.fromMap(row(ssid: null, bssid: 'c0:ff:ee:00:00:01'));
      expect(ap, isNotNull);
      expect(ap!.ssid, isNull, reason: 'still hidden');
      expect(ap.bssid, 'c0:ff:ee:00:00:01');
    });

    testWidgets(
        'withheld rows never render as "(hidden network)" or as an AP count',
        (tester) async {
      // The exact state the gate reproduced: two rows whose SSID and BSSID were
      // both stripped mid-scan, delivered with the stale pre-scan grant.
      final Map<String, Object?> payload = _payload(
        aps: <Map<String, Object?>>[
          row(ssid: null, bssid: null, channel: 6),
          row(ssid: null, bssid: null, channel: 36),
        ],
      );
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(payload, platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      // No fabricated RF claim: neither AP is cloaking, we simply lost the
      // grant that names them.
      expect(find.text('(hidden network)'), findsNothing);
      // No confident "2 access points" list-card title over rows that carry no
      // identity, and no occupancy charts built from them.
      expect(find.text('2 access points'), findsNothing);
      expect(find.textContaining('channel occupancy'), findsNothing);
      expect(find.textContaining('BSSID unavailable'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // GATE CARD + AP LIST IS SELF-CONTRADICTORY
  //
  // Every pre-existing two-kinds-of-null test used `aps: []`, so the state
  // where rows arrive ALONGSIDE locationAuthorized:false was entirely
  // unguarded. It rendered "The scan could not run…" directly above a populated
  // AP list and two occupancy charts. The list wins that argument visually, so
  // the gate card became a lie.
  // -------------------------------------------------------------------------
  group('rows + revoked grant cannot render both', () {
    testWidgets('locationAuthorized:false with rows shows the gate card ONLY',
        (tester) async {
      final Map<String, Object?> payload =
          _payload(locationAuthorized: false); // default 3 well-formed rows
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(payload, platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      // The gate card is the verdict.
      expect(find.textContaining('scan could not run'), findsOneWidget);
      // Nothing measured renders beneath it.
      expect(find.text('KeithNet'), findsNothing);
      expect(find.text('a4:83:e7:00:11:22'), findsNothing);
      expect(find.textContaining('channel occupancy'), findsNothing);
      expect(find.text('3 access points'), findsNothing);
      // And it still must not claim an empty RF environment on top of the gate.
      expect(find.textContaining('found no access points'), findsNothing);
    });

    testWidgets('radio off with rows shows the Wi-Fi-off card ONLY',
        (tester) async {
      final Map<String, Object?> payload = _payload(poweredOn: false);
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(payload, platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsNothing);
      expect(find.textContaining('channel occupancy'), findsNothing);
    });

    // -----------------------------------------------------------------------
    // A PLACEHOLDER BSSID GATES THE SNAPSHOT — it does not delete the row.
    //
    // The first fix tested only null-or-empty, a NARROWER rule than the six
    // other places in this codebase that reject "no BSSID" (MainActivity.kt
    // sanitizeBssid, arp_ndp_service, windows_arp_ffi, windows_wifi_ffi). All
    // of them also reject the zero-MAC and 02:00:00:00:00:00, and feeding a
    // placeholder through reproduced the original defect exactly: two
    // "(hidden network)" rows under a confident "2 access points".
    //
    // Dropping the placeholder rows would have been the wrong fix. On Android
    // they genuinely occur, so a drop would shrink the list silently and
    // under-report the RF environment. MainActivity.kt:641 names what a
    // placeholder actually means — "the 'no permission' placeholder BSSID" — so
    // it is evidence the grant is compromised, and that is the Location card.
    // -----------------------------------------------------------------------
    for (final String placeholder in <String>[
      '02:00:00:00:00:00', // Android's no-permission placeholder
      '00:00:00:00:00:00', // all-zero MAC
      '02-00-00-00-00-00', // separator variant must not slip past
      '02:00:00:00:00:00'.toUpperCase(), // case variant must not slip past
    ]) {
      test('placeholder BSSID $placeholder revokes the grant, keeps no rows',
          () {
        final ApScanSnapshot snap = ApScanSnapshot.fromMap(_payload(
          aps: <Map<String, Object?>>[
            row(ssid: null, bssid: placeholder),
            row(ssid: 'RealNet', bssid: 'a4:83:e7:00:11:22'),
          ],
        ));
        expect(snap.locationAuthorized, isFalse,
            reason: 'a placeholder is a permission signal, not a bad row');
        expect(snap.accessPoints, isEmpty);
        // Crucially NOT reported as an unreadable-row discard: nothing was
        // undescribable here, we lost the right to name them.
        expect(snap.unreadableCount, 0);
      });
    }

    testWidgets('placeholder rows render the Location gate, never a hidden AP',
        (tester) async {
      final Map<String, Object?> payload = _payload(
        aps: <Map<String, Object?>>[
          row(ssid: null, bssid: '02:00:00:00:00:00', channel: 6),
          row(ssid: null, bssid: '02:00:00:00:00:00', channel: 36),
        ],
      );
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(payload, platform: 'android'))),
      );
      await tester.pumpAndSettle();

      // The three lines the gate's repro printed, now inverted.
      expect(find.text('(hidden network)'), findsNothing);
      expect(find.text('2 access points'), findsNothing);
      expect(find.textContaining('scan could not run'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // ANDROID, NAMED. The shared fromMap tests pinned this behaviour without
    // ever asserting it on the platform it actually ships to.
    // -----------------------------------------------------------------------
    testWidgets('Android: a real scan with real BSSIDs still lists normally',
        (tester) async {
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(_payload(), platform: 'android'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.text('3 access points'), findsOneWidget);
      // The one genuinely cloaked BSS in the fixture keeps its honest label,
      // because it kept its BSSID.
      expect(find.text('(hidden network)'), findsOneWidget);
      expect(find.textContaining('scan could not run'), findsNothing);
    });

    test('Android: sanitizeBssid placeholders are rejected by the Dart side too',
        () {
      // Kotlin sanitizes before the payload is built, but ScanResult.BSSID is a
      // bare public field with no nullness annotation
      // ($ANDROID_HOME/sources/android-36.1/android/net/wifi/ScanResult.java:98),
      // so Kotlin sees a platform type. Dart does not assume it was sanitized.
      expect(isWithheldBssid('02:00:00:00:00:00'), isTrue);
      expect(isWithheldBssid('00:00:00:00:00:00'), isTrue);
      expect(isWithheldBssid(null), isTrue);
      expect(isWithheldBssid(''), isTrue);
      expect(isWithheldBssid('a4:83:e7:00:11:22'), isFalse);
      // A real MAC that merely STARTS with 02 is locally-administered, not a
      // placeholder, and must survive.
      expect(isWithheldBssid('02:00:00:00:00:01'), isFalse);
    });

    // -----------------------------------------------------------------------
    // NEW-2: the drop must not be silent. False identity became false COUNT.
    // -----------------------------------------------------------------------
    test('unparseable rows are counted, not silently swallowed', () {
      final ApScanSnapshot snap = ApScanSnapshot.fromMap(_payload(
        aps: <Map<String, Object?>>[
          row(ssid: 'Good', bssid: 'a4:83:e7:00:11:22'),
          <String, Object?>{'ssid': 'NoChannel', 'bssid': 'aa:bb:cc:dd:ee:ff'},
          <String, Object?>{'ssid': 'AlsoBad', 'bssid': 'aa:bb:cc:dd:ee:00'},
        ],
      ));
      expect(snap.accessPoints, hasLength(1));
      expect(snap.unreadableCount, 2);
    });

    testWidgets('the screen SAYS how many rows it could not read',
        (tester) async {
      final Map<String, Object?> payload = _payload(
        aps: <Map<String, Object?>>[
          row(ssid: 'Good', bssid: 'a4:83:e7:00:11:22'),
          <String, Object?>{'ssid': 'NoChannel', 'bssid': 'aa:bb:cc:dd:ee:ff'},
        ],
      );
      await tester.pumpWidget(
        host(ApScanScreen(service: _service(payload, platform: 'macos'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 access point'), findsOneWidget);
      expect(find.textContaining('could not be read'), findsOneWidget);
    });

    test('the model refuses to carry rows without the grant', () {
      // Any channel returning rows with the flag false: the flag wins, because
      // it is what the gate cards speak from.
      final ApScanSnapshot snap =
          ApScanSnapshot.fromMap(_payload(locationAuthorized: false));
      expect(snap.locationAuthorized, isFalse);
      expect(snap.accessPoints, isEmpty);
    });
  });
}
