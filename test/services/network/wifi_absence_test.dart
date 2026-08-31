// Why a Wi-Fi surface is empty - the wired dead-end that has been silent.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_absence.dart';

LinkAddress addr(String a, {bool v4 = true, bool ll = false}) =>
    LinkAddress(address: a, isIPv4: v4, isLinkLocal: ll);

void main() {
  group('classifyWifiAbsence', () {
    test('THE DEFECT: wired carrying traffic, Wi-Fi radio idle', () {
      // Keith's M5 this morning, minus the Wi-Fi association: en5 wired holds
      // the default route, en0 Wi-Fi is present and not joined. Today the app
      // offers "Start Live Monitoring" here, for RF that does not exist.
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          LinkInfo(
            name: 'en5',
            kind: LinkKind.wired,
            carrier: true,
            speedMbps: 2500,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.233')],
          ),
          const LinkInfo(name: 'en0', kind: LinkKind.wifi, carrier: false),
        ],
        defaultRouteInterfaceV4: 'en5',
      );
      expect(classifyWifiAbsence(t), WifiAbsence.onWiredInstead);

      final ({String title, String message})? c = wifiAbsenceCopy(
        WifiAbsence.onWiredInstead,
        wiredInterfaceName: 'en5',
      );
      expect(c, isNotNull);
      expect(c!.title, contains('Ethernet'));
      expect(c.message, contains('en5'));
      // Half an answer is not enough: it has to say what still works.
      expect(c.message, contains('ping'));
    });

    test('an associated radio proceeds normally', () {
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          LinkInfo(
            name: 'en0',
            kind: LinkKind.wifi,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.134')],
          ),
        ],
        defaultRouteInterfaceV4: 'en0',
      );
      expect(classifyWifiAbsence(t), WifiAbsence.associated);
      expect(wifiAbsenceCopy(WifiAbsence.associated), isNull);
    });

    test('no Wi-Fi interface at all is stated, not left blank', () {
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          LinkInfo(
            name: 'eth0',
            kind: LinkKind.wired,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.176')],
          ),
        ],
      );
      expect(classifyWifiAbsence(t), WifiAbsence.noRadio);
      expect(wifiAbsenceCopy(WifiAbsence.noRadio)!.title, contains('no Wi-Fi'));
    });

    test('radio idle with nothing else carrying traffic', () {
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          const LinkInfo(name: 'en0', kind: LinkKind.wifi, carrier: false),
          const LinkInfo(name: 'en5', kind: LinkKind.wired, carrier: false),
        ],
      );
      expect(classifyWifiAbsence(t), WifiAbsence.notAssociated);
    });

    test('a NULL carrier is not a false one', () {
      // A driver that did not report carrier tells us nothing. Inferring "off"
      // from silence is exactly the claim the old code correctly refused.
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          const LinkInfo(name: 'en0', kind: LinkKind.wifi),
          LinkInfo(
            name: 'en5',
            kind: LinkKind.wired,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.233')],
          ),
        ],
      );
      expect(classifyWifiAbsence(t), WifiAbsence.unknown);
      expect(wifiAbsenceCopy(WifiAbsence.unknown), isNull,
          reason: 'unknown must never render as a confident message');
    });

    test('no table at all is unknown, and never overrules iOS or Android', () {
      expect(classifyWifiAbsence(null), WifiAbsence.unknown);
    });

    test('an EMPTY table is a failed read, not a laptop without Wi-Fi', () {
      expect(classifyWifiAbsence(const LinkTable(links: <LinkInfo>[])),
          WifiAbsence.unknown);
    });

    test('a link-local-only Wi-Fi address is not an association', () {
      // 169.254 means the radio joined and DHCP never answered. Treating it as
      // associated would send the user hunting for RF that is fine.
      final LinkTable t = LinkTable(
        links: <LinkInfo>[
          LinkInfo(
            name: 'en0',
            kind: LinkKind.wifi,
            carrier: false,
            addresses: <LinkAddress>[addr('169.254.3.3', ll: true)],
          ),
        ],
      );
      expect(classifyWifiAbsence(t), WifiAbsence.notAssociated);
    });
  });

  group('every copy branch names a next action', () {
    test('no branch leaves the user with only a diagnosis', () {
      for (final WifiAbsence a in WifiAbsence.values) {
        final ({String title, String message})? c = wifiAbsenceCopy(a);
        if (c == null) continue;
        expect(c.title.trim(), isNotEmpty);
        expect(c.message.trim().length, greaterThan(60),
            reason: '$a must explain, not just label');
      }
    });
  });
}
