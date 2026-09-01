// Phone width, because the Pi edition is reached from a BROWSER, and on a job
// that browser is usually on a phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/join_network_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/link_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/link_table_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'join_network_screen_test.dart' as fixtures;

class _FakeLink implements LinkTableService {
  @override
  Future<LinkTableResult> read() async => LinkTableResult.ok(LinkTable(
        links: <LinkInfo>[
          LinkInfo(
              name: 'eth0',
              kind: LinkKind.wired,
              carrier: true,
              speedMbps: 1000,
              duplex: 'full',
              driver: 'bcmgenet',
              isDefaultRouteV4: true,
              addresses: const <LinkAddress>[
                LinkAddress(
                    address: '192.168.8.176', isIPv4: true, prefixLength: 24)
              ]),
          const LinkInfo(name: 'usb0', kind: LinkKind.wired, carrier: false),
          const LinkInfo(name: 'wlan0', kind: LinkKind.wifi, carrier: false),
        ],
        defaultRouteInterfaceV4: 'eth0',
        defaultGatewayV4: '192.168.8.1',
        source: 'wlanpi /toolboxapi/links',
      ));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> phone(WidgetTester t, Widget w, String slug) async {
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: const MediaQueryData(
          size: Size(390, 844), textScaler: TextScaler.linear(1.0)),
      child: w,
    ),
  ));
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$slug.png'));
}

void main() {
  testWidgets('join at iPhone width, no overflow', (WidgetTester t) async {
    await phone(t, JoinNetworkScreen(client: fixtures.FakePi()), 'phone_join');
  });
  testWidgets('link info at iPhone width, no overflow', (WidgetTester t) async {
    await phone(t, LinkInfoScreen(service: _FakeLink()), 'phone_link_info');
  });
}
