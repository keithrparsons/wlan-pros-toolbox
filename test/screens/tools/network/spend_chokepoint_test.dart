// THE `spendData` CHOKEPOINT ITSELF. THIS FILE EXISTS BECAUSE IT HAD NO GUARD.
//
// ============================================================================
// HOW I FOUND OUT: I MUTATED IT AND NOTHING DIED.
// ============================================================================
//
// After the round-5 fix, `vera_seven_exploits_test.dart` was green on all 7 shapes.
// Then I hand-mutated the chokepoint BACK to the broken rule:
//
//     spendData = includeThroughput && (!_needsConsent || _throughputConsented)
//              -> includeThroughput && (!_notOnWifi   || _throughputConsented)
//
// ...and ALL 38 TESTS STILL PASSED.
//
// Because the screens have TWO gates, and my tests only proved the FIRST one:
//
//   1. `_autoStart` REFUSES TO RUN on a link that is not proven free.
//   2. `spendData` DOWNGRADES a run that asks for throughput without consent.
//
// Every exploit test asserted `measureCalls == 0` — which gate (1) satisfies ALL BY
// ITSELF. Gate (2), the actual chokepoint, the line every future caller passes
// through, was never executed by a single test. "The fix is covered" and "the LINE
// is covered" are different claims and only one of them had been checked. That is
// the identical mistake that produced DO-NOT-SHIP in rounds 1, 2 and 3.
//
// ============================================================================
// SO: REACH THE CHOKEPOINT. BYPASS THE AUTO-START.
// ============================================================================
//
// The chokepoint is reachable exactly when a caller asks for throughput while the
// user has NOT consented. That is not a hypothetical — it is the F-2 bypass, and it
// is an entirely ordinary thing to do:
//
//   MOUNT THE SCREEN ON WI-FI, THEN WALK OUT OF WI-FI RANGE, THEN TAP RUN.
//
// On mount the link is Wi-Fi: no warning renders, the button carries its free label,
// and nothing sets `_throughputConsented`. By the time the user taps, the phone is on
// cellular. `_run` re-settles the probe (that await is the F-2 fix) and the
// CHOKEPOINT is the only thing standing between that tap and 573 MB of their money.
//
// The other reachable path is "Run again" on a result the user DECLINED — the tear-off
// passes `includeThroughput: true` and consent was never given.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_transport_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// THE PHONE WALKS OUT OF WI-FI RANGE. Wi-Fi until [walkOut] is called, then
/// whatever the link has become. A real, ordinary, thirty-second event.
///
/// The transition is an EXPLICIT EVENT, not a read counter: the screens probe an
/// unspecified number of times while mounting, and a counter would make the test's
/// meaning depend on that count. The test says WHEN the user moved.
class _WalksOutOfRange implements NetworkTransportProbe {
  _WalksOutOfRange(this._after);

  /// What the link becomes once the user has moved.
  final NetworkTransportFacts _after;
  bool _moved = false;

  void walkOut() => _moved = true;

  static const NetworkTransportFacts onWifi = NetworkTransportFacts(
    cellular: false,
    wifi: true,
    ethernet: false,
    vpn: false,
  );

  @override
  Future<NetworkTransportFacts?> read() async => _moved ? _after : onWifi;
}

/// MEASURED cellular — the link is now definitively metered.
const NetworkTransportFacts _cellular = NetworkTransportFacts(
  cellular: true,
  wifi: false,
  ethernet: false,
  vpn: false,
);

/// AMBIGUOUS — a VPN that hides its underlying transport. This is the row the OLD
/// rule (`!_notOnWifi`) reads as "safe to spend", because `notOnWifi` is false.
/// It is Vera's exploit #1, arriving through the chokepoint instead of the
/// auto-start.
const NetworkTransportFacts _vpnOpaque = NetworkTransportFacts(
  cellular: false,
  wifi: false,
  ethernet: false,
  vpn: true,
);

class _PathSilent implements WifiPathProbe {
  const _PathSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

class _NoWifiAddress implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoSites extends ReachabilityProbe {
  @override
  Future<List<SiteReachability>> measure() async => <SiteReachability>[];
}

LiveQualityMonitor _fakeMonitor() => LiveQualityMonitor(
      sampler: () async => const LatencyStats(
        avgMs: 20,
        minMs: 18,
        maxMs: 24,
        jitterMs: 2,
        lossPct: 0,
        sent: 5,
        received: 5,
      ),
    );

class _NoWifiAdapter implements WifiInfoAdapter {
  @override
  Future<ConnectedAp> fetch() async => throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'no Wi-Fi link',
      );
  @override
  String get platformLabel => 'fake';
  @override
  bool get gatesNameBehindPermission => false;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDns implements DnsProbeService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeNetDetails implements NetworkDetailsService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeIpGeo implements IpGeoService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WifiConnectionService _android(NetworkTransportProbe t) => WifiConnectionService(
      networkInfo: _NoWifiAddress(),
      platformOverride: TargetPlatform.android,
      pathProbe: const _PathSilent(),
      transportProbe: t,
    );

void main() {
  group('NETWORK QUALITY: the chokepoint, reached by walking out of range', () {
    Future<({MockQualityClient quality, _WalksOutOfRange link})> pump(
      WidgetTester tester,
      NetworkTransportFacts after,
    ) async {
      final MockQualityClient quality = MockQualityClient();
      final _WalksOutOfRange link = _WalksOutOfRange(after);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetQualityScreen(
            client: quality,
            reachabilityProbe: _NoSites(),
            monitor: _fakeMonitor(),
            connectionService: _android(link),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (quality: quality, link: link);
    }

    testWidgets('MEASURED CELLULAR: the tap that thought it was free spends nothing',
        (WidgetTester tester) async {
      final ({MockQualityClient quality, _WalksOutOfRange link}) r =
          await pump(tester, _cellular);
      final MockQualityClient quality = r.quality;

      // On mount we are on Wi-Fi: the free label, no warning, NO CONSENT RECORDED.
      expect(find.text('Run test'), findsOneWidget);
      expect(find.text('Run without the speed test'), findsNothing);

      // The user walks out of range, then taps. `_run` re-settles the probe and the
      // CHOKEPOINT is the only thing between this tap and their money.
      r.link.walkOut();
      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 1, reason: 'the run itself still happens');
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason: 'THE CHOKEPOINT. The caller asked for throughput; the user never '
            'consented; the link is now metered. Not one byte.',
      );
      expect(quality.lastIncludeResponsiveness, isFalse);
    });

    testWidgets('AMBIGUOUS (VPN): the shape the OLD rule read as safe',
        (WidgetTester tester) async {
      // THE MUTATION-KILLER. Under the old `!_notOnWifi` rule this row evaluates
      // TRUE (an opaque VPN is `unknown`, not `notOnWifi`) and the app spends. The
      // fail-closed rule refuses, without ever CLAIMING the user is on cellular.
      final ({MockQualityClient quality, _WalksOutOfRange link}) r =
          await pump(tester, _vpnOpaque);
      final MockQualityClient quality = r.quality;

      expect(find.text('Run test'), findsOneWidget);
      r.link.walkOut();
      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 1);
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason: 'an ambiguous link is not permission to spend a stranger\'s money',
      );
      expect(quality.lastIncludeResponsiveness, isFalse);
    });
  });

  group('TEST MY CONNECTION: the chokepoint, reached the same way', () {
    Future<
        ({
          MockQualityClient quality,
          WifiSignalSampler sampler,
          _WalksOutOfRange link
        })> pump(
      WidgetTester tester,
      NetworkTransportFacts after,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final MockQualityClient quality = MockQualityClient();
      final _WalksOutOfRange link = _WalksOutOfRange(after);
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: _android(link),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            // autoStart FALSE: gate (1) must not be allowed to answer for gate (2).
            // That conflation is exactly what left the chokepoint unguarded.
            autoStart: false,
            sourceOverride: WifiInfoSource.androidWifiManager,
            sampler: sampler,
            macAdapter: _NoWifiAdapter(),
            dnsProbeService: _FakeDns(),
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            enableCloudApps: false,
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
            qualityClient: quality,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (quality: quality, sampler: sampler, link: link);
    }

    Future<void> teardown(WidgetTester tester, WifiSignalSampler s) async {
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
      await tester.pump();
    }

    testWidgets('MEASURED CELLULAR: the free-labelled tap spends nothing',
        (WidgetTester tester) async {
      final ({
        MockQualityClient quality,
        WifiSignalSampler sampler,
        _WalksOutOfRange link
      }) r = await pump(tester, _cellular);

      // Mounted on Wi-Fi: the free label, and no consent was ever recorded.
      expect(find.text('Check My Connection'), findsOneWidget);

      r.link.walkOut();
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(
        r.quality.lastIncludeThroughput,
        isFalse,
        reason: 'THE CHOKEPOINT. This is the tap that used to cost 573 MB.',
      );
      expect(r.quality.lastIncludeResponsiveness, isFalse);

      await teardown(tester, r.sampler);
    });

    testWidgets('AMBIGUOUS (VPN): the shape the OLD rule read as safe',
        (WidgetTester tester) async {
      final ({
        MockQualityClient quality,
        WifiSignalSampler sampler,
        _WalksOutOfRange link
      }) r = await pump(tester, _vpnOpaque);

      r.link.walkOut();
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(
        r.quality.lastIncludeThroughput,
        isFalse,
        reason: 'the VPN row: `notOnWifi` is FALSE here, so the old rule spent. The '
            'fail-closed rule refuses — and still never claims the link is cellular.',
      );
      expect(r.quality.lastIncludeResponsiveness, isFalse);

      await teardown(tester, r.sampler);
    });

    testWidgets('and a phone that STAYS on Wi-Fi still spends, in full',
        (WidgetTester tester) async {
      // THE CONTROL. A chokepoint that refuses everything is not a chokepoint, it is
      // a wall — and it would look identical to a working one in every test above.
      const NetworkTransportFacts stillWifi = NetworkTransportFacts(
        cellular: false,
        wifi: true,
        ethernet: false,
        vpn: false,
      );
      final ({
        MockQualityClient quality,
        WifiSignalSampler sampler,
        _WalksOutOfRange link
      }) r = await pump(tester, stillWifi);

      r.link.walkOut(); // ...and it is STILL Wi-Fi. Nothing changes.
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(r.quality.lastIncludeThroughput, isTrue);
      expect(r.quality.lastIncludeResponsiveness, isTrue);

      await teardown(tester, r.sampler);
    });
  });
}
