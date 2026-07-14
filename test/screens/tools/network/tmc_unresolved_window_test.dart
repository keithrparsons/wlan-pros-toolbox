// THE UNRESOLVED WINDOW: the few hundred ms between mounting and the first probe.
//
// The money answer starts at its fail-closed default (`unknown`). That default is
// RIGHT for the GATE — nothing spends until we know — but WRONG for the pre-run
// CARD, because before the first probe returns EVERY device reads `unknown`, and a
// card driven off that would flash a cellular-data warning at every user on their
// home Wi-Fi, on every launch.
//
// So the render waits for RESOLUTION (`meteredRiskResolved`), while the gate reads
// the fail-closed value. This file pins the difference: during the window there is
// NO cost UI, and a tap in the window still spends nothing (the run awaits the
// probe). It is the guard that keeps `s.meteredRiskResolved ? … : null` honest —
// a mutation to `s.meteredRisk` (drop the resolution guard) flashes the card and is
// caught here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// A transport probe whose answer is GATED on a completer the test releases. Until
/// then the probe has not returned — the unresolved window.
class _Gated implements NetworkTransportProbe {
  _Gated(this._facts);
  final NetworkTransportFacts _facts;
  final Completer<void> _gate = Completer<void>();
  void release() => _gate.complete();
  @override
  Future<NetworkTransportFacts?> read() async {
    await _gate.future;
    return _facts;
  }
}

const NetworkTransportFacts _cellular = NetworkTransportFacts(
  cellular: true,
  wifi: false,
  ethernet: false,
  vpn: false,
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

class _NoWifiAdapter implements WifiInfoAdapter {
  @override
  Future<ConnectedAp> fetch() async => throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError, 'x');
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

void main() {
  testWidgets(
    'DURING the window: no cost UI is shown; AFTER a cellular resolve: it appears',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _Gated gate = _Gated(_cellular);
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: WifiConnectionService(
          networkInfo: _NoWifiAddress(),
          platformOverride: TargetPlatform.android,
          pathProbe: const _PathSilent(),
          transportProbe: gate,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
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
            qualityClient: MockQualityClient(),
          ),
        ),
      );
      // One frame: mounted, probe GATED (unresolved). This is the window.
      await tester.pump();

      // THE FIX. The fail-closed default is `unknown`, but the card must NOT flash.
      // A mutation dropping the `meteredRiskResolved` guard shows it here.
      expect(
        find.textContaining("You're on cellular."),
        findsNothing,
        reason: 'no confirmed-cellular claim during the window',
      );
      expect(
        find.textContaining("We can't tell"),
        findsNothing,
        reason: 'and no "may use data" nag either — we simply do not know yet, so we '
            'say nothing until we do',
      );
      expect(find.text('Check My Connection'), findsOneWidget);
      expect(find.text('Check without the speed test'), findsNothing);

      // Release the probe: it resolves to MEASURED cellular. Now the card appears.
      gate.release();
      await tester.pumpAndSettle();

      expect(find.textContaining("You're on cellular."), findsWidgets);
      expect(find.text('Check My Connection (uses data)'), findsOneWidget);
      expect(find.text('Check without the speed test'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      sampler.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'a TAP during the window still spends nothing (the run awaits the probe)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _Gated gate = _Gated(_cellular);
      final MockQualityClient quality = MockQualityClient();
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: WifiConnectionService(
          networkInfo: _NoWifiAddress(),
          platformOverride: TargetPlatform.android,
          pathProbe: const _PathSilent(),
          transportProbe: gate,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
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
      await tester.pump(); // in the window; the free-labelled button is showing

      // Tap while the probe is still gated, THEN release it. `_run` re-settles the
      // probe before deciding, so by the time `spendData` is evaluated the link is
      // known-cellular and the throughput is withheld.
      await tester.tap(find.text('Check My Connection'));
      gate.release();
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 1, reason: 'the run itself happens');
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason: 'a tap in the unresolved window cannot spend once the probe lands '
            'on cellular — the run awaits it',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      sampler.dispose();
      await tester.pump();
    },
  );
}
