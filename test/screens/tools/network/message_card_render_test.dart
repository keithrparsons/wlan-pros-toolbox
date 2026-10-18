// Render checks for the message card on five network/lookup screens that had no
// screen test (HTTP Header, Wake-on-LAN, ARP/NDP, BGP/ASN, WHOIS).
//
// Each test drives the screen through its injected service seam to a state that
// shows the screen's message card, then asserts the card's icon, title and body
// are on screen and nothing overflowed. These pin the card's output so it can be
// shared between screens without changing what any of them shows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/arp_ndp_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bgp_asn_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/http_header_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wake_on_lan_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/whois_screen.dart';
import 'package:wlan_pros_toolbox/services/network/arp_ndp_service.dart';
import 'package:wlan_pros_toolbox/services/network/bgp_asn_service.dart';
import 'package:wlan_pros_toolbox/services/network/http_header_service.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wake_on_lan_service.dart';
import 'package:wlan_pros_toolbox/services/network/whois_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _FakeHttp extends HttpHeaderService {
  @override
  Future<HttpHeaderResult> inspect({
    required String rawUrl,
    HttpMethod method = HttpMethod.head,
    Duration timeout = const Duration(seconds: 10),
    int maxRedirects = HttpHeaderService.defaultMaxRedirects,
  }) async => HttpHeaderResult.failure(
    requestedUrl: rawUrl,
    message: 'Test failure: connection refused',
  );
}

class _FakeWol extends WakeOnLanService {
  @override
  Future<WakeOnLanResult> wake({
    required String rawMac,
    String? rawBroadcast,
    int port = WakeOnLanService.defaultPort,
  }) async => WakeOnLanResult.failure(message: 'Test failure: no route');
}

class _FakeWhois extends WhoisService {
  @override
  Future<WhoisResult> lookup({
    required String rawQuery,
    Duration timeout = const Duration(seconds: 8),
  }) async => WhoisResult.failure(
    query: rawQuery,
    message: 'Test failure: server unreachable',
  );
}

class _FakeBgp extends BgpAsnService {
  @override
  Future<BgpAsnResult> lookup({required String rawQuery}) async =>
      BgpAsnResult.success(query: rawQuery, kind: BgpQueryKind.ip);
}

/// A device with no network interface at all, so there is no subnet to scan.
class _NoInterfaces extends InterfaceInfoService {
  @override
  Future<InterfaceInfoSnapshot> read() async => const InterfaceInfoSnapshot(
    interfaces: <NetworkInterfaceInfo>[],
    wifi: WifiLinkInfo(),
    hostname: null,
  );
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
  await tester.pump();
}

void main() {
  testWidgets('HTTP Header: a failed request shows the message card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, HttpHeaderScreen(service: _FakeHttp()));
    await tester.enterText(find.byType(TextField).first, 'example.com');
    await tester.pump();
    await tester.tap(find.text('Inspect'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Request failed'), findsOneWidget);
    expect(find.text('Test failure: connection refused'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wake-on-LAN: a failed send shows the message card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, WakeOnLanScreen(service: _FakeWol()));
    await tester.enterText(find.byType(TextField).first, 'AA:BB:CC:DD:EE:FF');
    await tester.pump();
    await tester.tap(find.text('Send magic packet'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Test failure: no route'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WHOIS: a failed lookup shows the message card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, WhoisScreen(service: _FakeWhois()));
    await tester.enterText(find.byType(TextField).first, 'example.com');
    await tester.pump();
    await tester.tap(find.text('Look up'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lookup failed'), findsOneWidget);
    expect(find.text('Test failure: server unreachable'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BGP/ASN: a lookup with no routing data shows the message card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, BgpAsnScreen(service: _FakeBgp()));
    await tester.enterText(find.byType(TextField).first, '8.8.8.8');
    await tester.pump();
    await tester.tap(find.text('Look up'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No routing data'), findsOneWidget);
    expect(
      find.textContaining('RIPEstat returned no ASN or prefix'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.search_off), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ARP/NDP: no IPv4 interface shows the Cannot scan card', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      ArpNdpScreen(
        service: ArpNdpService(),
        interfaceService: _NoInterfaces(),
        capabilityOverride: ArpCapability.sweepNoMac,
      ),
    );
    await tester.tap(find.text('Scan subnet'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cannot scan'), findsOneWidget);
    expect(
      find.textContaining('No active IPv4 interface found'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
