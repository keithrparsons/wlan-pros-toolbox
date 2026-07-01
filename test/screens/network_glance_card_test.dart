// Network-at-a-glance card (M2) — widget tests for the platform-honest fields.
//
// The card composes four shared services behind injectable seams, so these
// tests drive it with fakes — no real network, no platform channel. The
// load-bearing checks (GL-005 / GL-008):
//   * a value lane renders the real datum (SSID, local IP, public IP, ISP);
//   * iOS renders "Not reported on iOS" for SSID + signal (the app cannot
//     auto-read the link there) rather than a blank that implies "no Wi-Fi";
//   * a failed public-IP / ISP lane renders "Unavailable", distinct from the
//     platform-ceiling "Not reported";
//   * nothing is fabricated when a field is absent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_glance_card.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/subnet_seed.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: child));

/// A subnet deriver fed a fixed ip/mask/gateway with no plugin call.
SubnetSeedDeriver _seed({
  String? ip = '192.168.1.50',
  String? mask = '255.255.255.0',
  String? gateway = '192.168.1.1',
}) =>
    SubnetSeedDeriver(reader: () async => (ip: ip, mask: mask, gateway: gateway));

/// A public-IP service whose fetch returns a scripted body via the seam.
PublicIpService _publicIp(String? ip) => PublicIpService(
      fetcher: (String url, Duration timeout) async => ip ?? '',
    );

/// A geo service that resolves the ISP to [org] (ipinfo shape), or fails when
/// [org] is null — both kept off the real network via the JsonHttpClient seam.
/// The seam shape is the real [JsonFetcher]: `(Uri url, Duration timeout)`; a
/// null [org] throws a transport failure so the ISP lane degrades to the honest
/// "Unavailable", never a guessed carrier.
IpGeoService _geo(String? org) => IpGeoService(
      client: JsonHttpClient(
        fetcher: (Uri url, Duration timeout) async {
          if (org == null) {
            throw const JsonHttpException(
              JsonHttpErrorKind.transport,
              'offline',
            );
          }
          return <String, dynamic>{
            'ip': '203.0.113.7',
            'loc': '37.75,-122.4',
            'org': 'AS396325 $org',
          };
        },
      ),
    );

void main() {
  testWidgets('macOS: a real Wi-Fi reading + subnet + public IP/ISP render '
      'their values', (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.macOS,
      wifiFetcher: () async => const ConnectedAp(ssid: 'WLANPros', rssiDbm: -52),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      // The ISP lane reads through a fake geo client (ipinfo shape) so the row
      // resolves deterministically rather than depending on real-network
      // behavior in the test harness.
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Network at a glance'), findsOneWidget);
    expect(find.text('WLANPros'), findsOneWidget);
    expect(find.text('-52 dBm'), findsOneWidget);
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('192.168.1.1–192.168.1.254'), findsOneWidget);
    expect(find.text('203.0.113.7'), findsOneWidget);
    // ISP resolved from the geo lane — never guessed when present.
    expect(find.text('Comcast'), findsOneWidget);
  });

  testWidgets(
      'iOS: a fresh cached live reading renders SSID + Signal (the SAME values '
      'the Wi-Fi Information tool shows) — never "Not reported on iOS"',
      (WidgetTester tester) async {
    // The Wi-Fi Information tool writes into this shared cache. A warm cache is
    // the common case once the user has used the live tools this session.
    final ConnectedApCache cache = ConnectedApCache()
      ..update(const ConnectedAp(ssid: 'WLANPros', rssiDbm: -47));

    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.iOS,
      apCache: cache,
      // wifiFetcher must NOT be consulted on iOS (the reading comes from the
      // cache); a call here would throw and fail the test.
      wifiFetcher: () async => throw StateError('iOS must not auto-fetch Wi-Fi'),
      // The live requester must NOT fire on mount — only on an explicit tap.
      liveReadingRequester: () async =>
          throw StateError('must not fire on mount'),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    // The real cached values render — no lie about iOS being unable to report.
    expect(find.text('WLANPros'), findsOneWidget);
    expect(find.text('-47 dBm'), findsOneWidget);
    expect(find.text('Not reported on iOS'), findsNothing);
    expect(find.text('Get a live reading'), findsNothing);
    // The local-network rows DO work on iOS.
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.text('192.168.1.1–192.168.1.254'), findsOneWidget);
  });

  testWidgets(
      'iOS + cold cache: shows "Get a live reading" (NOT "Not reported"); '
      'firing it populates SSID + Signal from the returned reading',
      (WidgetTester tester) async {
    final ConnectedApCache cache = ConnectedApCache(); // cold
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.iOS,
      apCache: cache,
      wifiFetcher: () async => throw StateError('iOS must not auto-fetch Wi-Fi'),
      // A fake live requester standing in for the Wi-Fi Information tool's
      // Shortcut flow: returns a real reading when the user taps.
      liveReadingRequester: () async =>
          const ConnectedAp(ssid: 'LiveNet', rssiDbm: -55),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    // Cold cache → the honest actionable state, never the false ceiling.
    expect(find.text('Get a live reading'), findsOneWidget);
    expect(find.text('Not reported on iOS'), findsNothing);
    expect(find.text('LiveNet'), findsNothing);

    // Fire the affordance → the reading returns and the rows populate.
    await tester.tap(find.text('Get a live reading'));
    await tester.pumpAndSettle();

    expect(find.text('LiveNet'), findsOneWidget);
    expect(find.text('-55 dBm'), findsOneWidget);
    // The affordance retires once a reading is on screen.
    expect(find.text('Get a live reading'), findsNothing);
  });

  testWidgets(
      'iOS + cold cache + no reading obtained (Shortcut not installed): the '
      '"Get a live reading" affordance stays — never a dead "Not reported"',
      (WidgetTester tester) async {
    final ConnectedApCache cache = ConnectedApCache(); // cold
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.iOS,
      apCache: cache,
      // Requester returns null: no reading (the tool's install fall-through ran).
      liveReadingRequester: () async => null,
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get a live reading'));
    await tester.pumpAndSettle();

    // Honest: the affordance remains, no fabricated value, no false ceiling.
    expect(find.text('Get a live reading'), findsOneWidget);
    expect(find.text('Not reported on iOS'), findsNothing);
  });

  testWidgets(
      'Windows: auto-reads SSID + Signal via the shipped adapter (no permission '
      'gate) — never "Not reported on this platform" (C2 fix)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.windows,
      // Windows resolves to windowsNativeWifi and auto-reads through the SAME
      // wifiFetcher seam macOS/Android use — the fake stands in for the FFI read.
      wifiFetcher: () async => const ConnectedAp(ssid: 'WLANPros', rssiDbm: -41),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('WLANPros'), findsOneWidget);
    expect(find.text('-41 dBm'), findsOneWidget);
    // The old false ceiling must be gone.
    expect(find.textContaining('Not reported'), findsNothing);
    expect(find.text('Get a live reading'), findsNothing);
  });

  testWidgets('public IP unavailable (offline) renders "Unavailable", distinct '
      'from the platform "Not reported"', (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.macOS,
      wifiFetcher: () async => const ConnectedAp(ssid: 'WLANPros', rssiDbm: -52),
      seedDeriver: _seed(),
      // A null public IP (both endpoints unreachable) → "Unavailable (offline?)".
      publicIpService: _publicIp(null),
      // And the geo lane fails too → the ISP row degrades to "Unavailable",
      // never a guessed carrier.
      ipGeoService: _geo(null),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unavailable'), findsWidgets);
    expect(find.text('203.0.113.7'), findsNothing);
    // The platform-ceiling wording must NOT appear here — this is a transient
    // failure ("Unavailable"), distinct from "Not reported".
    expect(find.textContaining('Not reported'), findsNothing);
  });

  testWidgets('macOS reading with no SSID (Location not granted) → an honest '
      'permission reason, not a fabricated network name',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.macOS,
      // A reading arrived (rssi present) but SSID is null — the Location gate.
      wifiFetcher: () async => const ConnectedAp(rssiDbm: -60),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Location permission'), findsOneWidget);
    expect(find.text('-60 dBm'), findsOneWidget);
  });

  testWidgets('no local IPv4 → "No local IPv4", subnet honest, never a guess',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.macOS,
      wifiFetcher: () async => const ConnectedAp(ssid: 'WLANPros', rssiDbm: -52),
      seedDeriver: _seed(ip: null, mask: null, gateway: null),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('No local IPv4'), findsOneWidget);
  });
}
