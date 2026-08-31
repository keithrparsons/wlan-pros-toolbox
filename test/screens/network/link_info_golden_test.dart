// A real render of the Link Info screen, so there is something to LOOK at.
//
// Keith has asked repeatedly to SEE the Ethernet work. The data below is his
// M5's ACTUAL link table, read live on 2026-08-31 with both links up: en5
// wired at 2500Base-T holding the default route, en0 Wi-Fi associated
// alongside it, and en2/en3 the permanently-inactive "Ethernet Adapter"
// decoys that carry IFF_RUNNING and have never had a cable in them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/link_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/link_table_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _FakeService implements LinkTableService {
  _FakeService(this._result);
  final LinkTableResult _result;
  @override
  Future<LinkTableResult> read() async => _result;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

LinkAddress a4(String a, int p) =>
    LinkAddress(address: a, isIPv4: true, prefixLength: p);

/// Keith's M5, 2026-08-31, both links up at once.
LinkTable m5() => LinkTable(
      links: <LinkInfo>[
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          operState: 'UP',
          carrier: true,
          speedMbps: 2500,
          duplex: 'full',
          mtu: 1500,
          mac: '00:e0:4c:99:a3:4e',
          isDefaultRouteV4: true,
          addresses: <LinkAddress>[a4('192.168.8.233', 24)],
        ),
        LinkInfo(
          name: 'en0',
          kind: LinkKind.wifi,
          operState: 'UP',
          carrier: true,
          mtu: 1500,
          mac: 'c0:c7:db:a0:6e:8d',
          addresses: <LinkAddress>[a4('192.168.8.134', 24)],
        ),
        const LinkInfo(
          name: 'en2',
          kind: LinkKind.wired,
          operState: 'UP',
          carrier: false,
          mtu: 1500,
          mac: '0a:d1:86:a7:8b:fe',
        ),
        const LinkInfo(
          name: 'en3',
          kind: LinkKind.wired,
          operState: 'UP',
          carrier: false,
          mtu: 1500,
          mac: '0a:d1:86:a7:8b:ff',
        ),
      ],
      defaultRouteInterfaceV4: 'en5',
      defaultGatewayV4: '192.168.8.1',
      source: 'macos ifconfig + networksetup + route',
    );

/// The R4, read live from /toolboxapi/links the same morning. Note the two
/// monitor radios and the Bluetooth PAN bridge, all reporting carrier true.
LinkTable r4() => LinkTable(
      links: <LinkInfo>[
        LinkInfo(
          name: 'eth0',
          kind: LinkKind.wired,
          operState: 'UP',
          carrier: true,
          speedMbps: 1000,
          duplex: 'full',
          mtu: 1500,
          mac: '2c:cf:67:03:4b:67',
          driver: 'bcmgenet',
          bus: 'platform',
          isDefaultRouteV4: true,
          addresses: <LinkAddress>[a4('192.168.8.176', 24)],
        ),
        const LinkInfo(name: 'wlanpi0', kind: LinkKind.monitor, carrier: true),
        const LinkInfo(name: 'wlanpi1', kind: LinkKind.monitor, carrier: true),
        const LinkInfo(name: 'pan0', kind: LinkKind.virtual, carrier: true),
        const LinkInfo(name: 'usb0', kind: LinkKind.wired, carrier: false),
        const LinkInfo(name: 'wlan0', kind: LinkKind.wifi, carrier: false),
        const LinkInfo(name: 'wlan1', kind: LinkKind.wifi, carrier: false),
      ],
      defaultRouteInterfaceV4: 'eth0',
      defaultGatewayV4: '192.168.8.1',
      source: 'wlanpi /toolboxapi/links',
    );

Future<void> capture(
    WidgetTester tester, LinkTableResult r, String slug) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(760, 940),
        textScaler: TextScaler.linear(1.0),
      ),
      child: LinkInfoScreen(service: _FakeService(r)),
    ),
  ));
  await tester.pumpAndSettle();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$slug.png'));
}

void main() {
  testWidgets('macbook, both links up', (WidgetTester tester) async {
    await capture(tester, LinkTableResult.ok(m5()), 'link_info_macbook');
  });

  testWidgets('wlan pi r4', (WidgetTester tester) async {
    await capture(tester, LinkTableResult.ok(r4()), 'link_info_wlanpi');
  });

  testWidgets('unavailable states its reason', (WidgetTester tester) async {
    await capture(
      tester,
      const LinkTableResult.unavailable(
        'A browser is not allowed to see network interfaces. Open this in the '
        'Toolbox app, or reach it from a WLAN Pi, which reports its own links '
        'in full.',
        source: 'web',
      ),
      'link_info_unavailable',
    );
  });
}
