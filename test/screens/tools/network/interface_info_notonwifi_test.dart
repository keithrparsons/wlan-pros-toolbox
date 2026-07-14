// INTERFACE INFORMATION, OFF WI-FI — the guard on the three SCREEN branches.
//
// WHY THIS FILE EXISTS (round-4 cold-eyes HIGH, 2026-07-13). The not-on-Wi-Fi work
// added three branches to `interface_info_screen.dart` — the copy report's status
// line (:303), the copy report's field-block skip (:317), and the Wi-Fi card's
// honest-state branch (:516) — 56 lines of new rendering with ZERO tests.
// `interface_info_screen_test.dart` did not contain the string `notOnWifi` at all.
//
// The SERVICE gate was covered (`interface_info_service`'s `_isNotOnWifi`). The
// SCREEN that renders its result was not. That is the same shape as the round-3
// blocker and the same shape as the original bug: a tested value reached through
// an untested wire is an untested value.
//
// THE WORST OF THE THREE is :317. Mutate `if (!w.notOnWifi)` to `if (true)` and the
// copy report emits:
//
//     MAC type: Not available — Apple blocks apps from reading the device Wi-Fi MAC
//
// ...a Wi-Fi hardware note SYNTHESIZED FROM A NULL ADDRESS, on a device with no
// Wi-Fi link at all. `MacRandomizationClassifier.label(null)` returns a non-null
// string, so `line()` does not skip it. That is precisely the wrong-kind-of-null
// this whole body of work exists to delete — a claim about a failed READ, on a
// thing that was never THERE — and it would have shipped with a green suite.
//
// So these tests drive the REAL screen over a probe that says "no Wi-Fi", with a
// STALE cached identity sitting in the cache (KeithNet), and assert on what a user
// would SEE and COPY.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/interface_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

const MethodChannel _networkInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/network_info');

/// The cellular-only iPhone as iOS itself reports it: NWPathMonitor sees no Wi-Fi
/// interface on the path, and no satisfiable Wi-Fi route. The only native shape
/// permitted to assert `notOnWifi`.
class _NoWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: false,
      );
}

/// The device IS on Wi-Fi — the control case, so every assertion below is proven
/// to be driven by the probe and not by something incidental to the harness.
class _OnWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

/// No Wi-Fi addresses in either family (the address-probe fallback's view).
class _NoAddresses implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PublicIpService _fakePublicIp() =>
    PublicIpService(fetcher: (String url, Duration t) async => '203.0.113.7');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final Map<Object?, Object?> args =
            call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkInfoChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// The screen over a real [InterfaceInfoService], with a WARM cached Wi-Fi
  /// identity (KeithNet) that the connectivity gate must suppress. The cache is
  /// deliberately fresh (1 minute old, well inside the 5-minute staleness
  /// ceiling) — a timer is not a connectivity check, and that is the point.
  Widget buildScreen({required WifiPathProbe path}) {
    final cache = ConnectedApCache();
    cache.update(const ConnectedAp(
      ssid: 'KeithNet',
      bssid: 'a4:83:e7:00:11:22',
    ));
    final DateTime cachedMoment = cache.updatedAt ?? DateTime.now();

    final service = InterfaceInfoService(
      networkInfo: _NoAddresses(),
      interfaceLister: () async => const [],
      connectedApReader: () async => (
        ap: const ConnectedAp(ssid: 'KeithNet', bssid: 'a4:83:e7:00:11:22'),
        authorized: true,
      ),
      connectedApCache: cache,
      now: () => cachedMoment.add(const Duration(minutes: 1)),
      connectionService: WifiConnectionService(
        networkInfo: _NoAddresses(),
        platformOverride: TargetPlatform.iOS,
        pathProbe: path,
      ),
    );

    return MaterialApp(
      theme: AppTheme.dark(),
      home: InterfaceInfoScreen(
        service: service,
        publicIpService: _fakePublicIp(),
        wifiSourceOverride: WifiInfoSource.iosShortcuts,
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, WifiPathProbe path) async {
    await tester.pumpWidget(buildScreen(path: path));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<String> copyReport(WidgetTester tester) async {
    final Finder copyBtn = find.byType(AppCopyAction);
    await tester.ensureVisible(copyBtn);
    await tester.pumpAndSettle();
    await tester.tap(copyBtn);
    await tester.pumpAndSettle();
    // Drain AppCopyAction's 1.5s "Copied" confirmation timer.
    await tester.pump(const Duration(seconds: 2));
    expect(clipboardWrites, isNotEmpty,
        reason: 'sanity: the copy report must have been produced, or every '
            'assertion about its contents below is vacuous');
    return clipboardWrites.last;
  }

  // ==========================================================================
  // :516 — the Wi-Fi CARD branch.
  // ==========================================================================
  group('the Wi-Fi card, off Wi-Fi', () {
    testWidgets('names the real state instead of rows of "Not available"',
        (WidgetTester tester) async {
      await pumpScreen(tester, _NoWifiPath());

      expect(
        find.textContaining('not connected to Wi-Fi'),
        findsWidgets,
        reason: 'the card must NAME the state. Every row it would otherwise '
            'render says "Not available on this platform" — a claim about the '
            'PLATFORM, and it is false: the platform is fine, there is simply no '
            'Wi-Fi link (GL-005, the two kinds of null).',
      );
      expect(
        find.textContaining('no Wi-Fi link to report'),
        findsOneWidget,
      );
    });

    testWidgets('does NOT render the remembered SSID/BSSID as the current link',
        (WidgetTester tester) async {
      // THE BUG. A warm cache (1 minute old) held the PREVIOUS network's identity,
      // and the screen presented it as the link you are on NOW — on the iOS path
      // with `cachedAt: null`, so it did not even get the "as of HH:MM" disclosure.
      await pumpScreen(tester, _NoWifiPath());

      expect(find.text('KeithNet'), findsNothing,
          reason: 'a remembered SSID must never be served as the current network '
              'on a device that is demonstrably off Wi-Fi');
      expect(find.text('a4:83:e7:00:11:22'), findsNothing);
    });

    testWidgets('CONTROL: on Wi-Fi, the same cached identity DOES render',
        (WidgetTester tester) async {
      // Proves the suppression above is caused by the PROBE, not by the harness
      // failing to seed the cache. Without this, both assertions above would pass
      // against a screen that simply renders nothing.
      await pumpScreen(tester, _OnWifiPath());

      expect(find.text('KeithNet'), findsOneWidget,
          reason: 'the gate must suppress ONLY on a positive not-on-Wi-Fi signal; '
              'a device on Wi-Fi keeps its identity');
      expect(find.textContaining('no Wi-Fi link to report'), findsNothing);
    });
  });

  // ==========================================================================
  // :303 and :317 — the COPY REPORT branches.
  //
  // [[feedback_screenshot_text_match]]: the copy report must say what the screen
  // says. A help desk reading eight "Unavailable" rows would start debugging a
  // Wi-Fi link that is not there.
  // ==========================================================================
  group('the copy report, off Wi-Fi', () {
    testWidgets(':303 — the Wi-Fi section states the real status',
        (WidgetTester tester) async {
      await pumpScreen(tester, _NoWifiPath());
      final String report = await copyReport(tester);

      expect(
        report,
        contains('Not connected to Wi-Fi (no Wi-Fi link on this device)'),
        reason: 'the report must say WHY the Wi-Fi rows are empty: there was no '
            'link, not a failed read',
      );
      expect(report, isNot(contains('KeithNet')),
          reason: 'and it must not paste a remembered SSID to a help desk as the '
              'current network');
    });

    testWidgets(
        ':317 — NO "MAC type" line synthesized from a null hardware address',
        (WidgetTester tester) async {
      // THE WORST OF THE THREE. `MacRandomizationClassifier.label(null)` returns a
      // non-null string ("Not available — Apple blocks apps from reading..."), so
      // `line()` does NOT skip it. Mutating this guard to `if (true)` prints a
      // Wi-Fi HARDWARE note for a device with no Wi-Fi link — a claim about a
      // failed read, about a thing that was never there.
      await pumpScreen(tester, _NoWifiPath());
      final String report = await copyReport(tester);

      expect(report, isNot(contains('MAC type')),
          reason: 'a MAC-type verdict computed from a null address, on a device '
              'with no Wi-Fi link, is the exact wrong-kind-of-null this work '
              'exists to delete');
      // The rest of the field block must be skipped with it.
      expect(report, isNot(contains('Hardware Address')));
      expect(report, isNot(contains('Subnet mask')));
      expect(report, isNot(contains('Gateway')));
    });

    testWidgets('CONTROL: on Wi-Fi, the field block (incl. MAC type) IS emitted',
        (WidgetTester tester) async {
      // The other half of :317. Without this, the assertions above would also pass
      // against a report that never emits those rows under ANY condition — a test
      // that cannot fail. This proves the block is genuinely gated on the probe.
      await pumpScreen(tester, _OnWifiPath());
      final String report = await copyReport(tester);

      expect(report, contains('MAC type'),
          reason: 'on a device WITH a Wi-Fi link the MAC-type row is legitimate '
              'and must still be reported');
      expect(report, contains('KeithNet'));
      expect(
        report,
        isNot(contains('Not connected to Wi-Fi (no Wi-Fi link on this device)')),
      );
    });
  });
}
