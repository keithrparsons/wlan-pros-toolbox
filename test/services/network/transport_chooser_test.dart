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

  group('platform detection must not depend on prose', () {
    // THE REAL STRING A WLAN Pi SENDS, copied verbatim from an R4 running
    // wlanpi-core 2.1.10 on 2026-09-04. Keep it verbatim: the bug this guards
    // was a case-sensitive substring match against exactly this sentence.
    const String kRealPiSource =
        'sysfs + ip addr on the WLAN Pi (no ethtool; it is not installed)';

    test('the Pi source string does NOT contain the lowercase needle', () {
      // The assertion that explains the bug. `contains('wlanpi')` was the whole
      // test, and on a real Pi it is false -- so a genuine WLAN Pi was
      // classified as a plain browser, `canEnumerate` went false, every row
      // collapsed to "a browser is not allowed to see network interfaces", and
      // the chooser rendered read-only ON TOP OF a screen listing eth0 at
      // 1 Gbps. If this ever starts passing, the source wording changed and the
      // fallback below is what keeps working.
      expect(kRealPiSource.contains('wlanpi'), isFalse,
          reason: 'this is why the old detection failed on real hardware');
      expect(kRealPiSource.toLowerCase().contains('wlan pi'), isTrue,
          reason: 'the spaced, cased spelling is what a Pi actually sends');
    });

    test('a browser is a browser when nothing says otherwise', () {
      // Off web this returns a native platform, so the web branch is only
      // reachable in a real browser. What we CAN pin here is the table: the web
      // capability must stay unable to enumerate, because that is the thing the
      // misdetection wrongly applied to a Pi.
      final TransportCapability web =
          kTransportCapabilities[TransportPlatform.web]!;
      expect(web.canEnumerate, isFalse);
      final TransportCapability pi =
          kTransportCapabilities[TransportPlatform.wlanPi]!;
      expect(pi.canEnumerate, isTrue,
          reason: 'the Pi enumerates its own interfaces; that is the point');
      expect(pi.canSelectLocal, SelectSupport.yes);
      expect(pi.canSelectInternet, SelectSupport.yes);
    });

    test('a Pi-classified table yields CHOOSABLE rows, not a dead card', () {
      // The user-visible consequence, asserted end to end. Misdetected as web,
      // every row is absent and nothing is choosable, which is exactly what
      // Keith saw. Classified correctly, the Ethernet row is live.
      final List<TransportOption> asPi = buildTransportOptions(
        platform: TransportPlatform.wlanPi,
        scope: TransportScope.internet,
        links: r4LinkTable(),
      );
      expect(asPi.any((TransportOption o) => o.isChoosable), isTrue,
          reason: 'a Pi must offer at least one choosable transport');

      final List<TransportOption> asWeb = buildTransportOptions(
        platform: TransportPlatform.web,
        scope: TransportScope.internet,
        links: r4LinkTable(),
      );
      expect(asWeb.any((TransportOption o) => o.isChoosable), isFalse,
          reason: 'a plain browser can choose nothing -- correct, and the '
              'misdetection is what wrongly applied this to a Pi');
      // And the contradiction that made it obvious on screen: the browser copy
      // denies interface visibility while the Pi table plainly has interfaces.
      expect(asWeb.first.reason.toLowerCase(), contains('browser'));
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

    // KEITH RULED THE COLLAPSED ROW ON 2026-09-04: short reason always
    // visible, long form on tap. He rejected hiding the explanation behind a
    // "Why?" link because a person who does not tap sees a greyed row and no
    // explanation -- which is exactly what the test above exists to prevent.
    //
    // So the short form inherits the SAME guarantee, and it inherits it for
    // EVERY state rather than only the un-choosable ones: the short string is
    // the one a user is guaranteed to see on every row, choosable or not.
    test('the SHORT reason carries the same promise, on every row', () {
      for (final TransportPlatform p in TransportPlatform.values) {
        for (final TransportScope s in TransportScope.values) {
          final List<TransportOption> rows = buildTransportOptions(
            platform: p,
            scope: s,
            links: r4LinkTable(),
          );
          for (final TransportOption o in rows) {
            expect(o.shortReason.trim(), isNotEmpty,
                reason: 'the collapsed ${o.kind.label} row on $p / $s would '
                    'render with no explanation at all');
          }
        }
      }
    });

    // The short form exists to fit a 330px phone row without wrapping to three
    // lines. A "short" string that is as long as the long one is the option
    // Keith rejected, arrived at by drift instead of by decision.
    test('the short form is actually short, and shorter than the long one', () {
      for (final TransportPlatform p in TransportPlatform.values) {
        for (final TransportScope s in TransportScope.values) {
          final List<TransportOption> rows = buildTransportOptions(
            platform: p,
            scope: s,
            links: r4LinkTable(),
          );
          for (final TransportOption o in rows) {
            expect(o.shortReason.length, lessThanOrEqualTo(72),
                reason: '${o.kind.label} on $p / $s: "${o.shortReason}" is too '
                    'long for a collapsed row');
            expect(o.shortReason.length, lessThanOrEqualTo(o.reason.length),
                reason: '${o.kind.label} on $p / $s: the short form is not '
                    'shorter than the long form, so "More" would do nothing');
          }
        }
      }
    });

    // The metered warning is the one fact on this screen that costs the user
    // money if they miss it, so it must survive into the collapsed form -- a
    // cost warning that only appears after a tap is not a warning.
    //
    // BUT IT IS SCOPED TO THE ROWS WHERE MONEY CAN ACTUALLY BE SPENT, and that
    // scoping is deliberate rather than an oversight. This test first asserted
    // the warning on an iOS present-but-idle cellular row and failed, which was
    // the test being wrong: on iOS both scopes are SelectSupport.no, so the
    // user CANNOT move a test onto cellular, so there is no impending spend to
    // warn about. Warning there would be noise attached to an action that does
    // not exist. The two rows that can cost money are the one already carrying
    // traffic and the one you are able to select.
    test('a cellular path you can CHOOSE warns about data in the SHORT form',
        () {
      LinkInfo cellular() => LinkInfo(
            name: 'rmnet0',
            kind: LinkKind.wired,
            carrier: true,
            addresses: <LinkAddress>[addr('10.44.2.9')],
          );
      List<LinkInfo> onWifi() => <LinkInfo>[
            LinkInfo(
              name: 'wlan0',
              kind: LinkKind.wifi,
              carrier: true,
              isDefaultRouteV4: true,
              addresses: <LinkAddress>[addr('192.168.8.187')],
            ),
          ];

      // Android can bind to a chosen network, so this row is selectable and
      // choosing it spends data.
      final TransportOption selectable = buildTransportOptions(
        platform: TransportPlatform.android,
        scope: TransportScope.internet,
        links: onWifi(),
        cellularLink: cellular(),
      ).firstWhere((TransportOption o) => o.kind == TransportKind.cellular);
      expect(selectable.isChoosable, isTrue);
      expect(selectable.shortReason.toLowerCase(), contains('metered'));

      // And the row that is already carrying traffic, where the data is being
      // spent right now. The cellular link has to appear in the link table AS
      // WELL as in cellularLink for this state: "active" means it holds the
      // default route, and selectDefaultLink only ever looks at the table.
      // That is how a real device reports it -- a modem presents as a network
      // device, which is why cellularLink is passed separately at all.
      final LinkInfo onCell = LinkInfo(
        name: 'rmnet0',
        kind: LinkKind.wired,
        carrier: true,
        isDefaultRouteV4: true,
        addresses: <LinkAddress>[addr('10.44.2.9')],
      );
      final TransportOption active = buildTransportOptions(
        platform: TransportPlatform.android,
        scope: TransportScope.internet,
        links: <LinkInfo>[onCell],
        cellularLink: onCell,
      ).firstWhere((TransportOption o) => o.kind == TransportKind.cellular);
      expect(active.state, TransportState.active);
      expect(active.shortReason.toLowerCase(), contains('metered'));
    });
  });

  // THE PROBE PATH. `probed` has been a parameter of buildTransportOptions
  // since it was written and NOTHING populated it until 2026-09-04. These
  // pin the three outcomes the "Try it now" button now drives.
  group('the probe answers what the platform table cannot', () {
    List<LinkInfo> multiHomedMac() => <LinkInfo>[
          LinkInfo(
            name: 'en5',
            kind: LinkKind.wired,
            carrier: true,
            isDefaultRouteV4: true,
            addresses: <LinkAddress>[
              const LinkAddress(address: '192.168.8.234', prefixLength: 24, isIPv4: true),
            ],
          ),
          LinkInfo(
            name: 'en0',
            kind: LinkKind.wifi,
            carrier: true,
            addresses: <LinkAddress>[
              const LinkAddress(address: '192.168.8.134', prefixLength: 24, isIPv4: true),
            ],
          ),
        ];

    TransportOption wifiRow(Map<String, bool> probed) =>
        buildTransportOptions(
          platform: TransportPlatform.macos,
          scope: TransportScope.internet,
          links: multiHomedMac(),
          probed: probed,
        ).firstWhere((TransportOption o) => o.kind == TransportKind.wifi);

    test('unprobed is NOT TESTED -- an open question, not a refusal', () {
      final TransportOption o = wifiRow(const <String, bool>{});
      expect(o.state, TransportState.presentUntested);
      expect(o.isChoosable, isFalse);
      expect(o.shortReason, contains('Not checked'));
    });

    test('a probe that succeeded makes the row selectable', () {
      final TransportOption o = wifiRow(const <String, bool>{'en0': true});
      expect(o.state, TransportState.selectable);
      expect(o.isChoosable, isTrue);
      expect(o.reason, contains('succeeded'));
    });

    test('a probe that failed is CANNOT PIN, and names the likely cause', () {
      final TransportOption o = wifiRow(const <String, bool>{'en0': false});
      expect(o.state, TransportState.presentNotSelectable);
      expect(o.isChoosable, isFalse);
      expect(o.reason, contains('different gateway'));
    });

    // The three outcomes must stay visibly different. Rendering "we will not"
    // and "we have not found out yet" identically is the two-kinds-of-null
    // error this file has already paid for twice.
    test('the three outcomes are distinguishable, not collapsed', () {
      final Set<TransportState> states = <TransportState>{
        wifiRow(const <String, bool>{}).state,
        wifiRow(const <String, bool>{'en0': true}).state,
        wifiRow(const <String, bool>{'en0': false}).state,
      };
      expect(states.length, 3);
    });

    // A probe result for a DIFFERENT interface must not leak onto this row.
    test('a probe result is keyed to its own interface', () {
      final TransportOption o = wifiRow(const <String, bool>{'en5': true});
      expect(o.state, TransportState.presentUntested,
          reason: 'en5 being probeable says nothing about en0');
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
