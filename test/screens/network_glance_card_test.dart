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

  testWidgets('iOS: SSID + signal say "Not reported on iOS", never a blank — '
      'but local IP/gateway/subnet still populate', (WidgetTester tester) async {
    await tester.pumpWidget(_host(NetworkGlanceCard(
      platformOverride: TargetPlatform.iOS,
      // wifiFetcher is intentionally omitted: iOS must NOT call it (the card
      // knows the link is not auto-readable). If it did, this throwing fetcher
      // would surface a different reason and fail the assertion below.
      wifiFetcher: () async => throw StateError('iOS must not auto-fetch Wi-Fi'),
      seedDeriver: _seed(),
      publicIpService: _publicIp('203.0.113.7'),
      ipGeoService: _geo('Comcast'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Not reported on iOS'), findsNWidgets(2)); // SSID + signal
    // The local-network rows DO work on iOS.
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.text('192.168.1.1–192.168.1.254'), findsOneWidget);
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
