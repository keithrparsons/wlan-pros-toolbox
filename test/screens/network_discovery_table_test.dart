// Network Discovery results table — sort correctness and the responsive
// layout switch (customer request, Peter, desktop: "results in a table").
//
// The sort tests are pure unit tests against sortHosts, because the ordering
// rule is the part that is easy to get wrong and expensive to notice: a table
// that sorts 192.168.1.10 before 192.168.1.9 looks plausible until you are
// hunting for a specific host. The layout tests drive the real screen at two
// surface widths and assert which rendering appears.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_discovery_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_discovery_table.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_host.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/horizontal_scroll_table.dart';

/// A fake engine replaying a scripted result — no sockets, isolate, or mDNS.
class _FakeEngine implements LanDiscoveryEngine {
  _FakeEngine(this._result);

  final DiscoveryResult _result;

  @override
  DiscoveryResult? get lastResult => _result;

  @override
  Stream<DiscoveryProgress> run() async* {
    yield const DiscoveryProgress(DiscoveryPhase.seeding, 0.02);
    yield const DiscoveryProgress(DiscoveryPhase.complete, 1.0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LanHost _host(
  String ip, {
  String? hostname,
  String? mdnsName,
  String? mac,
  String? vendor,
  Set<int>? ports,
  Set<String>? services,
  DeviceType type = DeviceType.unknown,
}) => LanHost(
  ip: ip,
  hostname: hostname,
  mdnsName: mdnsName,
  mac: mac,
  vendor: vendor,
  openPorts: ports ?? <int>{},
  mdnsServices: services ?? <String>{},
  deviceType: type,
);

List<String> _ips(List<LanHost> hosts) =>
    hosts.map((LanHost h) => h.ip).toList();

void main() {
  group('ipSortKey', () {
    test('orders octets numerically, not lexically', () {
      expect(ipSortKey('192.168.1.9'), lessThan(ipSortKey('192.168.1.10')));
      expect(ipSortKey('10.0.0.2'), lessThan(ipSortKey('10.0.0.100')));
      // The whole address is compared, not just the last octet.
      expect(ipSortKey('10.0.2.1'), lessThan(ipSortKey('10.0.10.1')));
      // Top of the range does not overflow into a negative.
      expect(ipSortKey('255.255.255.255'), greaterThan(0));
    });

    test('a malformed address yields 0 rather than throwing', () {
      expect(ipSortKey('not-an-ip'), 0);
      expect(ipSortKey('1.2.3'), 0);
    });
  });

  group('sortHosts by IP', () {
    test('sorts NUMERICALLY: .9 comes before .10, not after', () {
      // Deliberately seeded in an order that a lexical string sort would
      // "confirm", so this test fails loudly if the comparator ever regresses
      // to comparing dotted-quad strings.
      final List<LanHost> hosts = <LanHost>[
        _host('192.168.1.10'),
        _host('192.168.1.9'),
        _host('192.168.1.100'),
        _host('192.168.1.2'),
        _host('192.168.1.20'),
      ];

      expect(_ips(sortHosts(hosts, const DiscoverySort())), <String>[
        '192.168.1.2',
        '192.168.1.9',
        '192.168.1.10',
        '192.168.1.20',
        '192.168.1.100',
      ]);
    });

    test('descending IP is the exact reverse', () {
      final List<LanHost> hosts = <LanHost>[
        _host('10.0.0.9'),
        _host('10.0.0.10'),
        _host('10.0.0.1'),
      ];
      expect(
        _ips(
          sortHosts(
            hosts,
            const DiscoverySort(
              column: DiscoverySortColumn.ip,
              ascending: false,
            ),
          ),
        ),
        <String>['10.0.0.10', '10.0.0.9', '10.0.0.1'],
      );
    });

    test('does not mutate the caller\'s list', () {
      final List<LanHost> hosts = <LanHost>[_host('10.0.0.5'), _host('10.0.0.1')];
      sortHosts(hosts, const DiscoverySort());
      expect(_ips(hosts), <String>['10.0.0.5', '10.0.0.1']);
    });
  });

  group('sortHosts blank handling', () {
    test('blank names sort last in BOTH directions', () {
      final List<LanHost> hosts = <LanHost>[
        _host('10.0.0.1'), // no name at all
        _host('10.0.0.2', hostname: 'zebra'),
        _host('10.0.0.3', hostname: 'alpha'),
      ];

      expect(
        _ips(
          sortHosts(hosts, const DiscoverySort(column: DiscoverySortColumn.name)),
        ),
        <String>['10.0.0.3', '10.0.0.2', '10.0.0.1'],
      );
      // Reversing shows the other end of the NAMED hosts; the nameless host
      // does not flood the top of the table.
      expect(
        _ips(
          sortHosts(
            hosts,
            const DiscoverySort(
              column: DiscoverySortColumn.name,
              ascending: false,
            ),
          ),
        ),
        <String>['10.0.0.2', '10.0.0.3', '10.0.0.1'],
      );
    });

    test('mDNS name wins over reverse-DNS hostname for the Name column', () {
      final LanHost h = _host('10.0.0.1', hostname: 'zzz', mdnsName: 'aaa');
      expect(hostDisplayName(h), 'aaa');
    });

    test('ties break on IP ascending, so the order is total', () {
      final List<LanHost> hosts = <LanHost>[
        _host('10.0.0.20', type: DeviceType.printer),
        _host('10.0.0.3', type: DeviceType.printer),
        _host('10.0.0.10', type: DeviceType.printer),
      ];
      expect(
        _ips(
          sortHosts(hosts, const DiscoverySort(column: DiscoverySortColumn.type)),
        ),
        <String>['10.0.0.3', '10.0.0.10', '10.0.0.20'],
      );
    });

    test('ports sort by the lowest open port; no open ports sorts last', () {
      final List<LanHost> hosts = <LanHost>[
        _host('10.0.0.1', ports: <int>{443, 8080}),
        _host('10.0.0.2'), // none open
        _host('10.0.0.3', ports: <int>{22}),
      ];
      expect(
        _ips(
          sortHosts(
            hosts,
            const DiscoverySort(column: DiscoverySortColumn.ports),
          ),
        ),
        <String>['10.0.0.3', '10.0.0.1', '10.0.0.2'],
      );
    });
  });

  group('DiscoverySort.select', () {
    test('re-selecting the same column toggles direction', () {
      const DiscoverySort s = DiscoverySort();
      expect(s.column, DiscoverySortColumn.ip);
      expect(s.ascending, isTrue);

      final DiscoverySort toggled = s.select(DiscoverySortColumn.ip);
      expect(toggled.column, DiscoverySortColumn.ip);
      expect(toggled.ascending, isFalse);

      final DiscoverySort back = toggled.select(DiscoverySortColumn.ip);
      expect(back.ascending, isTrue);
    });

    test('selecting a new column starts it ascending', () {
      const DiscoverySort s = DiscoverySort(
        column: DiscoverySortColumn.ip,
        ascending: false,
      );
      final DiscoverySort next = s.select(DiscoverySortColumn.vendor);
      expect(next.column, DiscoverySortColumn.vendor);
      expect(next.ascending, isTrue);
    });
  });

  group('responsive layout', () {
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti',
    });

    DiscoveryResult resultWith({required bool arpAvailable}) => DiscoveryResult(
      hosts: <LanHost>[
        _host(
          '10.0.10.10',
          mac: arpAvailable ? 'fc:ec:da:01:23:45' : null,
          vendor: arpAvailable ? 'Ubiquiti' : null,
          ports: <int>{80},
          type: DeviceType.webServer,
        ),
        _host('10.0.10.9', ports: <int>{22}, type: DeviceType.sshHost),
      ],
      subnetLabel: '10.0.10.1-10.0.10.254',
      arp: arpAvailable
          ? const ArpReadResult(available: true)
          : const ArpReadResult.unavailable('No ARP read on this platform.'),
    );

    Future<void> pumpAt(
      WidgetTester tester,
      Size size, {
      bool arpAvailable = true,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            engineFactory: () => _FakeEngine(resultWith(arpAvailable: arpAvailable)),
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Scan local network'));
      await tester.pumpAndSettle();
    }

    testWidgets('narrow viewport keeps the stacked card list, no table', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(500, 900));

      expect(find.byType(NetworkDiscoveryTable), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      // The hosts are still rendered, just as cards.
      expect(find.text('2 hosts found'), findsOneWidget);
      expect(find.text('10.0.10.9'), findsOneWidget);
    });

    testWidgets('wide viewport renders the table instead of the cards', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(1200, 900));

      expect(find.byType(NetworkDiscoveryTable), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('2 hosts found'), findsOneWidget);
      // Column headers present.
      for (final String header in <String>[
        'IP',
        'Name',
        'Type',
        'MAC',
        'Vendor',
        'Services',
        'Open ports',
      ]) {
        expect(find.text(header), findsOneWidget, reason: 'header $header');
      }
    });

    testWidgets('table scrolls horizontally INSIDE its own container, so the '
        'page never scrolls sideways', (WidgetTester tester) async {
      await pumpAt(tester, const Size(1200, 900));

      // The wide column set is wrapped in the shared HorizontalScrollTable
      // (always-visible scrollbar), not left to push the page wider.
      expect(
        find.ancestor(
          of: find.byType(DataTable),
          matching: find.byType(HorizontalScrollTable),
        ),
        findsOneWidget,
      );
      // The page's own scroll view is vertical only.
      final SingleChildScrollView page = tester.widget<SingleChildScrollView>(
        find
            .ancestor(
              of: find.byType(NetworkDiscoveryTable),
              matching: find.byType(SingleChildScrollView),
            )
            .last,
      );
      expect(page.scrollDirection, Axis.vertical);
    });

    testWidgets('table shows rows in numeric IP order by default', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(1200, 900));

      final double yOfNine = tester.getTopLeft(find.text('10.0.10.9')).dy;
      final double yOfTen = tester.getTopLeft(find.text('10.0.10.10')).dy;
      // .9 sits ABOVE .10 — the numeric answer, not the lexical one.
      expect(yOfNine, lessThan(yOfTen));
    });

    testWidgets('tapping the IP header toggles to descending order', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(1200, 900));

      await tester.tap(find.text('IP'));
      await tester.pumpAndSettle();

      final double yOfNine = tester.getTopLeft(find.text('10.0.10.9')).dy;
      final double yOfTen = tester.getTopLeft(find.text('10.0.10.10')).dy;
      expect(yOfTen, lessThan(yOfNine));
    });

    testWidgets('MAC and Vendor columns are omitted when no ARP read, not '
        'rendered as blanks', (WidgetTester tester) async {
      await pumpAt(tester, const Size(1200, 900), arpAvailable: false);

      expect(find.byType(NetworkDiscoveryTable), findsOneWidget);
      expect(find.text('MAC'), findsNothing);
      expect(find.text('Vendor'), findsNothing);
      // The remaining columns still render.
      expect(find.text('IP'), findsOneWidget);
      expect(find.text('Open ports'), findsOneWidget);
      // And the honest ceiling note is still stated.
      expect(find.textContaining('need a desktop ARP read'), findsOneWidget);
    });

    testWidgets('empty result reads as an honest empty state at table width', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            engineFactory: () => _FakeEngine(
              const DiscoveryResult(
                hosts: <LanHost>[],
                subnetLabel: '10.0.10.1-10.0.10.254',
                arp: ArpReadResult(available: true),
              ),
            ),
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Scan local network'));
      await tester.pumpAndSettle();

      // No empty table shell: the empty state replaces it entirely.
      expect(find.byType(NetworkDiscoveryTable), findsNothing);
      expect(find.text('No hosts responded'), findsOneWidget);
      expect(find.text('0 hosts found'), findsOneWidget);
    });

    testWidgets('idle at table width shows no table and no host list', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byType(NetworkDiscoveryTable), findsNothing);
      expect(find.text('Scan local network'), findsOneWidget);
    });
  });
}
