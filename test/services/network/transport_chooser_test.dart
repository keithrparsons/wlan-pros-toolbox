// Transport chooser - platform and capability awareness, and the guarantee that
// every unavailable option explains itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/transport_chooser.dart';

LinkAddress addr(String a, {bool v4 = true, bool linkLocal = false}) =>
    LinkAddress(address: a, isIPv4: v4, isLinkLocal: linkLocal);

/// The R4's own link table, read live from /toolboxapi/links on 2026-08-31.
/// FOUR of these report carrier true and only one is a link a user can be on.
List<LinkInfo> r4LinkTable() => <LinkInfo>[
      LinkInfo(
        name: 'eth0',
        kind: LinkKind.wired,
        operState: 'UP',
        carrier: true,
        speedMbps: 1000,
        duplex: 'full',
        driver: 'bcmgenet',
        bus: 'platform',
        isDefaultRouteV4: true,
        addresses: <LinkAddress>[
          addr('192.168.8.176'),
          addr('fe80::2ecf:67ff:fe03:4b67', v4: false, linkLocal: true),
        ],
      ),
      const LinkInfo(name: 'lo', kind: LinkKind.loopback, carrier: true),
      const LinkInfo(name: 'wlanpi0', kind: LinkKind.monitor, carrier: true),
      const LinkInfo(name: 'wlanpi1', kind: LinkKind.monitor, carrier: true),
      const LinkInfo(name: 'pan0', kind: LinkKind.virtual, carrier: true),
      const LinkInfo(name: 'usb0', kind: LinkKind.wired, carrier: false),
      const LinkInfo(name: 'wlan0', kind: LinkKind.wifi, carrier: false),
      const LinkInfo(name: 'wlan1', kind: LinkKind.wifi, carrier: false),
    ];

void main() {
  group('selectDefaultLink', () {
    test('carrier alone is NOT sufficient: monitor and virtual are excluded', () {
      // FIVE interfaces on the R4 report carrier true (loopback included). A
      // selector written as
      // "first interface with carrier" picks eth0 here only by luck of
      // ordering, and would pick wlanpi0 on a Pi that started monitor mode
      // before the cable went in.
      final List<LinkInfo> links = r4LinkTable();
      expect(links.where((LinkInfo l) => l.carrier == true).length, 5);
      expect(selectDefaultLink(links)?.name, 'eth0');
    });

    test('the default route wins even against a stronger-looking candidate', () {
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en0',
          kind: LinkKind.wifi,
          carrier: true,
          addresses: <LinkAddress>[addr('192.168.8.134')],
        ),
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          carrier: true,
          speedMbps: 2500,
          isDefaultRouteV4: true,
          addresses: <LinkAddress>[addr('10.0.0.22')],
        ),
      ];
      // This is the exact macOS shape from Phase 0: Wi-Fi on en0 and a live
      // 2500Base-T wired link on en5. network_info_plus returns en0. We must
      // not.
      expect(selectDefaultLink(links)?.name, 'en5');
    });

    test('with no default route and one usable link, that link is the answer', () {
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          carrier: true,
          addresses: <LinkAddress>[addr('10.0.0.22')],
        ),
        const LinkInfo(name: 'en0', kind: LinkKind.wifi, carrier: false),
      ];
      expect(selectDefaultLink(links)?.name, 'en5');
    });

    test('two qualifying links with no default route returns NULL, never a guess', () {
      // Silently picking one is precisely the network_info_plus defect. The
      // honest answer is to ask.
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          carrier: true,
          addresses: <LinkAddress>[addr('10.0.0.22')],
        ),
        LinkInfo(
          name: 'en0',
          kind: LinkKind.wifi,
          carrier: true,
          addresses: <LinkAddress>[addr('192.168.8.134')],
        ),
      ];
      expect(selectDefaultLink(links), isNull);
    });

    test('a link-local-only address does not make a link usable', () {
      // 169.254.x is a diagnosis, not an address: the link came up and DHCP
      // never answered.
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          carrier: true,
          addresses: <LinkAddress>[addr('169.254.9.9', linkLocal: true)],
        ),
      ];
      expect(selectDefaultLink(links), isNull);
    });
  });

  group('THE GUARANTEE: every unavailable option says why', () {
    test('across every platform and both scopes, no silent absence', () {
      for (final TransportPlatform p in TransportPlatform.values) {
        for (final TransportScope s in TransportScope.values) {
          final List<TransportOption> rows = buildTransportOptions(
            platform: p,
            scope: s,
            links: r4LinkTable(),
          );
          expect(rows.length, TransportKind.values.length,
              reason: 'every transport gets a row on $p, even when absent');
          for (final TransportOption o in rows) {
            if (!o.isChoosable) {
              expect(o.reason.trim(), isNotEmpty,
                  reason: 'a greyed ${o.kind.label} row on $p / $s that does '
                      'not say why reads as a bug');
            }
          }
        }
      }
    });
  });

  group('platform awareness', () {
    test('web cannot enumerate, so every row is absent and explains itself', () {
      final List<TransportOption> rows = buildTransportOptions(
        platform: TransportPlatform.web,
        scope: TransportScope.internet,
        links: r4LinkTable(),
      );
      expect(rows.every((TransportOption o) => o.state == TransportState.absent),
          isTrue);
      expect(rows.first.reason, contains('browser'));
    });

    test('a desktop can pin a LOCAL test but not an internet one', () {
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en0',
          kind: LinkKind.wifi,
          carrier: true,
          isDefaultRouteV4: true,
          addresses: <LinkAddress>[addr('192.168.8.134')],
        ),
        LinkInfo(
          name: 'en5',
          kind: LinkKind.wired,
          carrier: true,
          addresses: <LinkAddress>[addr('10.0.0.22')],
        ),
      ];

      final TransportOption localEth = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.localSubnet,
        links: links,
      ).firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(localEth.state, TransportState.selectable);

      // Internet selection on a desktop is machine-dependent, not
      // platform-dependent: MEASURED 2026-08-31, binding the non-default
      // interface reached github.com fine because both NICs sat behind one
      // gateway. So untested is its own state, distinct from refused.
      final TransportOption untested = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.internet,
        links: links,
      ).firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(untested.state, TransportState.presentUntested);
      expect(untested.reason, contains('not been checked'));

      final TransportOption proven = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.internet,
        links: links,
        probed: const <String, bool>{'en5': true},
      ).firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(proven.state, TransportState.selectable);
      expect(proven.reason, contains('Tested on this machine'));

      final TransportOption failed = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.internet,
        links: links,
        probed: const <String, bool>{'en5': false},
      ).firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(failed.state, TransportState.presentNotSelectable);
      expect(failed.reason, contains('different gateway'));
    });

    test('KEITH\'S CASE: an iPhone on Wi-Fi, Ethernet and cellular at once', () {
      // He must be able to see which path is carrying the test even where he
      // cannot move it. Reporting is the requirement; choosing is a bonus.
      final List<LinkInfo> links = <LinkInfo>[
        LinkInfo(
          name: 'en0',
          kind: LinkKind.wifi,
          carrier: true,
          addresses: <LinkAddress>[addr('192.168.8.155')],
        ),
        LinkInfo(
          name: 'en2',
          kind: LinkKind.wired,
          carrier: true,
          isDefaultRouteV4: true,
          addresses: <LinkAddress>[addr('10.0.0.55')],
        ),
      ];
      final LinkInfo cell = LinkInfo(
        name: 'pdp_ip0',
        kind: LinkKind.wired,
        carrier: true,
        addresses: <LinkAddress>[addr('10.90.1.7')],
      );

      final List<TransportOption> rows = buildTransportOptions(
        platform: TransportPlatform.ios,
        scope: TransportScope.internet,
        links: links,
        cellularLink: cell,
      );

      final TransportOption eth =
          rows.firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      final TransportOption wifi =
          rows.firstWhere((TransportOption o) => o.kind == TransportKind.wifi);
      final TransportOption cellular =
          rows.firstWhere((TransportOption o) => o.kind == TransportKind.cellular);

      expect(eth.state, TransportState.active,
          reason: 'the wired adapter holds the default route, so say so');
      // iOS selection is deliberately NOT claimed until a device test proves a
      // source bind survives iOS routing. Telling a user a test ran over
      // Ethernet when it ran over cellular, on a metered link, is the failure
      // this caution exists to prevent.
      expect(wifi.state, TransportState.presentNotSelectable);
      expect(cellular.state, TransportState.presentNotSelectable);
      expect(cellular.reason, isNotEmpty);
    });

    test('no cellular radio is stated, not left as a mystery gap', () {
      final TransportOption cell = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.internet,
        links: r4LinkTable(),
      ).firstWhere((TransportOption o) => o.kind == TransportKind.cellular);
      expect(cell.state, TransportState.absent);
      expect(cell.reason, contains('no cellular radio'));
    });

    test('cellular present but idle warns about the data it would spend', () {
      final LinkInfo cell = LinkInfo(
        name: 'rmnet0',
        kind: LinkKind.wired,
        carrier: true,
        addresses: <LinkAddress>[addr('10.90.1.7')],
      );
      final TransportOption row = buildTransportOptions(
        platform: TransportPlatform.android,
        scope: TransportScope.internet,
        links: <LinkInfo>[
          LinkInfo(
            name: 'wlan0',
            kind: LinkKind.wifi,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.99')],
          ),
        ],
        cellularLink: cell,
      ).firstWhere((TransportOption o) => o.kind == TransportKind.cellular);

      expect(row.state, TransportState.selectable);
      expect(row.reason.toLowerCase(), contains('data'));
    });
  });

  group('the wired states Phase 0 measured', () {
    test('a cable into a dead switch reads the same as no cable, and says so', () {
      final List<TransportOption> rows = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.localSubnet,
        links: <LinkInfo>[
          const LinkInfo(name: 'en5', kind: LinkKind.wired, carrier: false),
          LinkInfo(
            name: 'en0',
            kind: LinkKind.wifi,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[addr('192.168.8.134')],
          ),
        ],
      );
      final TransportOption eth =
          rows.firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(eth.state, TransportState.presentNoLink);
      expect(eth.reason, contains('dead switch'));
    });

    test('an interface up with no address is distinguished from no link', () {
      final List<TransportOption> rows = buildTransportOptions(
        platform: TransportPlatform.macos,
        scope: TransportScope.localSubnet,
        links: <LinkInfo>[
          const LinkInfo(name: 'en5', kind: LinkKind.wired, carrier: true),
        ],
      );
      final TransportOption eth =
          rows.firstWhere((TransportOption o) => o.kind == TransportKind.ethernet);
      expect(eth.state, TransportState.presentNoLink);
      expect(eth.reason, contains('no address'));
    });
  });
}
