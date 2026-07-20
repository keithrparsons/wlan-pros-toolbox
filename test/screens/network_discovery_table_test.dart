// Network Discovery results table — sort correctness and the responsive
// layout switch (customer request, Peter, desktop: "results in a table").
//
// The sort tests are pure unit tests against sortHosts, because the ordering
// rule is the part that is easy to get wrong and expensive to notice: a table
// that sorts 192.168.1.10 before 192.168.1.9 looks plausible until you are
// hunting for a specific host. The layout tests drive the real screen at two
// surface widths and assert which rendering appears.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ---------------------------------------------------------------------------
  // Regression tests for the two defects the SOP-009 gate found. Both are about
  // state that OUTLIVES the thing it describes: a sort selection naming a column
  // that is no longer rendered, and a sort selection honoured by one layout but
  // not the other. Neither is reachable from the sort-correctness tests above,
  // which is exactly why those passed while these defects shipped.
  // ---------------------------------------------------------------------------

  group('a sorted column that disappears', () {
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti',
    });

    /// Two hosts, MAC + vendor present only when the ARP read succeeded.
    DiscoveryResult resultWith({required bool arpAvailable}) => DiscoveryResult(
      hosts: <LanHost>[
        _host(
          '10.0.10.9',
          mac: arpAvailable ? 'fc:ec:da:00:00:09' : null,
          vendor: arpAvailable ? 'Ubiquiti' : null,
          ports: <int>{22},
          type: DeviceType.sshHost,
        ),
        _host(
          '10.0.10.10',
          mac: arpAvailable ? 'fc:ec:da:00:00:10' : null,
          vendor: arpAvailable ? 'Aruba' : null,
          ports: <int>{80},
          type: DeviceType.webServer,
        ),
      ],
      subnetLabel: '10.0.10.1-10.0.10.254',
      arp: arpAvailable
          ? const ArpReadResult(available: true)
          : const ArpReadResult.unavailable('No ARP read on this platform.'),
    );

    testWidgets('sorting by MAC and then re-scanning WITHOUT an ARP read does '
        'not crash, and leaves a sort the user can see', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // First scan reads the ARP cache, second one cannot -- the real sequence
      // on a machine that loses its ARP read between runs. MAC and Vendor are
      // columns on scan 1 and gone on scan 2, while _sort still names MAC.
      int run = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            engineFactory: () =>
                _FakeEngine(resultWith(arpAvailable: run++ == 0)),
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Scan local network'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MAC'));
      await tester.pumpAndSettle();
      expect(find.text('MAC'), findsOneWidget, reason: 'sorted by MAC');

      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();

      // The column the sort names is gone.
      expect(find.text('MAC'), findsNothing);
      expect(find.text('Vendor'), findsNothing);
      // The table still renders, and DataTable was handed a REAL column index
      // rather than the -1 that indexOf returns for a missing column (which
      // trips the assertion in data_table.dart, and in release silently means
      // "no header is sorted" while the rows ARE sorted by a hidden column).
      expect(find.byType(NetworkDiscoveryTable), findsOneWidget);
      final DataTable table = tester.widget<DataTable>(find.byType(DataTable));
      expect(
        table.sortColumnIndex,
        isNot(-1),
        reason: 'a -1 sortColumnIndex is the crash',
      );
      expect(
        table.sortColumnIndex,
        isNotNull,
        reason: 'the rows are ordered, so some header must show as sorted',
      );
      expect(
        table.sortColumnIndex! >= 0 && table.sortColumnIndex! < 5,
        isTrue,
        reason: 'index must address one of the five surviving columns',
      );

      // And the order on screen is the one the visible sorted header claims:
      // IP ascending, so .9 sits above .10.
      final double yOfNine = tester.getTopLeft(find.text('10.0.10.9')).dy;
      final double yOfTen = tester.getTopLeft(find.text('10.0.10.10')).dy;
      expect(yOfNine, lessThan(yOfTen));
    });
  });

  group('accessibility and placeholders', () {
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti',
    });

    /// One host WITH a name, one WITHOUT, so the placeholder cell is rendered.
    final DiscoveryResult mixed = DiscoveryResult(
      hosts: <LanHost>[
        _host(
          '10.0.10.9',
          hostname: 'nine.local',
          mac: 'fc:ec:da:00:00:09',
          vendor: 'Ubiquiti',
          ports: <int>{22},
          type: DeviceType.sshHost,
        ),
        _host('10.0.10.10', ports: <int>{80}, type: DeviceType.webServer),
      ],
      subnetLabel: '10.0.10.1-10.0.10.254',
      arp: const ArpReadResult(available: true),
    );

    Future<void> pumpTable(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            engineFactory: () => _FakeEngine(mixed),
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Scan local network'));
      await tester.pumpAndSettle();
    }

    testWidgets('the active column announces its sort direction, not just an '
        'arrow', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpTable(tester);

      // Default is IP ascending.
      expect(find.bySemanticsLabel('IP, sorted ascending'), findsOneWidget);
      // A column that is not the active one still says it can be sorted, but
      // never claims a direction.
      expect(find.bySemanticsLabel('Vendor, sortable'), findsOneWidget);
      expect(find.bySemanticsLabel('Vendor, sorted ascending'), findsNothing);

      // Toggling to descending is announced, so direction is not carried by the
      // arrow glyph alone (WCAG 2.2 SC 1.3.1 / 4.1.2).
      await tester.tap(find.text('IP'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('IP, sorted descending'), findsOneWidget);
      expect(find.bySemanticsLabel('IP, sorted ascending'), findsNothing);

      handle.dispose();
    });

    testWidgets('an absent value renders the app\'s "n/a" placeholder', (
      WidgetTester tester,
    ) async {
      await pumpTable(tester);

      // 10.0.10.10 has no name, MAC, vendor or services (4 cells); 10.0.10.9
      // advertised no services (1 cell). Neither host is missing a port list,
      // which has its own worded placeholder ("none open"), not n/a.
      expect(find.text('n/a'), findsNWidgets(5));
      expect(find.text('none open'), findsNothing);
      // The lone period the branch invented is gone; it read as content.
      expect(find.text('.'), findsNothing);
    });
  });

  group('effectiveDiscoverySort', () {
    test('keeps a sort whose column is being rendered', () {
      const DiscoverySort byMac = DiscoverySort(
        column: DiscoverySortColumn.mac,
        ascending: false,
      );
      final DiscoverySort resolved = effectiveDiscoverySort(
        byMac,
        showMacColumns: true,
      );
      expect(resolved.column, DiscoverySortColumn.mac);
      expect(resolved.ascending, isFalse);
    });

    test('falls back to IP ascending when the sorted column is not rendered', () {
      for (final DiscoverySortColumn gone in <DiscoverySortColumn>[
        DiscoverySortColumn.mac,
        DiscoverySortColumn.vendor,
      ]) {
        final DiscoverySort resolved = effectiveDiscoverySort(
          DiscoverySort(column: gone, ascending: false),
          showMacColumns: false,
        );
        expect(resolved.column, DiscoverySortColumn.ip, reason: '$gone');
        expect(resolved.ascending, isTrue, reason: '$gone');
      }
    });

    test('leaves the always-present columns alone when MAC is hidden', () {
      for (final DiscoverySortColumn kept in <DiscoverySortColumn>[
        DiscoverySortColumn.ip,
        DiscoverySortColumn.name,
        DiscoverySortColumn.type,
        DiscoverySortColumn.services,
        DiscoverySortColumn.ports,
      ]) {
        expect(
          effectiveDiscoverySort(
            DiscoverySort(column: kept),
            showMacColumns: false,
          ).column,
          kept,
        );
      }
    });

    test('every resolved column is addressable in the rendered column set', () {
      // The property the crash violated: whatever comes back must have an index
      // in the columns actually rendered, for BOTH gate states.
      for (final bool showMac in <bool>[true, false]) {
        final List<DiscoverySortColumn> columns = visibleDiscoveryColumns(
          showMacColumns: showMac,
        );
        for (final DiscoverySortColumn column in DiscoverySortColumn.values) {
          final DiscoverySort resolved = effectiveDiscoverySort(
            DiscoverySort(column: column),
            showMacColumns: showMac,
          );
          expect(
            columns.indexOf(resolved.column),
            greaterThanOrEqualTo(0),
            reason: 'column $column, showMac $showMac',
          );
        }
      }
    });
  });

  group('NetworkDiscoveryTable holds its own index invariant', () {
    // The screen resolves the sort before handing it over, but the table is the
    // widget that must never pass an out-of-range index to DataTable. Driven
    // DIRECTLY here so the guard is pinned at its own boundary rather than only
    // through the screen that happens to protect it today.
    testWidgets('a sort naming a hidden column never becomes a -1 index', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final DiscoverySortColumn hidden in <DiscoverySortColumn>[
        DiscoverySortColumn.mac,
        DiscoverySortColumn.vendor,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: NetworkDiscoveryTable(
                hosts: <LanHost>[_host('10.0.10.9'), _host('10.0.10.10')],
                sort: DiscoverySort(column: hidden, ascending: false),
                showMacColumns: false,
                onSort: (DiscoverySortColumn _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final DataTable table = tester.widget<DataTable>(find.byType(DataTable));
        expect(table.sortColumnIndex, isNot(-1), reason: 'hidden $hidden');
        expect(
          table.sortColumnIndex,
          0,
          reason: 'falls back to IP, the first column',
        );
        expect(table.sortAscending, isTrue, reason: 'fallback is ascending');
      }
    });
  });

  group('displayed order and copied order', () {
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'FCECDA': 'Ubiquiti',
    });

    /// Raw engine order is IP-ascending (.9 then .10) and the vendors are seeded
    /// so that vendor-DESCENDING reverses it. Any layout that ignores the sort
    /// and renders the raw list therefore disagrees visibly.
    final DiscoveryResult twoHosts = DiscoveryResult(
      hosts: <LanHost>[
        _host(
          '10.0.10.9',
          mac: 'fc:ec:da:00:00:09',
          vendor: 'Aruba',
          ports: <int>{22},
          type: DeviceType.sshHost,
        ),
        _host(
          '10.0.10.10',
          mac: 'fc:ec:da:00:00:10',
          vendor: 'Ubiquiti',
          ports: <int>{80},
          type: DeviceType.webServer,
        ),
      ],
      subnetLabel: '10.0.10.1-10.0.10.254',
      arp: const ArpReadResult(available: true),
    );

    const List<String> ips = <String>['10.0.10.9', '10.0.10.10'];

    /// The IPs in the order they are painted, top to bottom. Works for either
    /// layout: the table paints them in DataRows, the cards in list rows.
    List<String> displayedOrder(WidgetTester tester) {
      final List<String> found = ips
          .where((String ip) => find.text(ip).evaluate().isNotEmpty)
          .toList();
      found.sort(
        (String a, String b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );
      return found;
    }

    /// The IP column of the TSV the copy action put on the clipboard.
    List<String> copiedOrder(String tsv) => tsv
        .split('\n')
        .skip(1)
        .where((String line) => line.trim().isNotEmpty)
        .map((String line) => line.split('\t').first)
        .toList();

    testWidgets('agree in BOTH layouts, including across a layout switch with '
        'an active sort', (WidgetTester tester) async {
      final List<String> clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetworkDiscoveryScreen(
            service: oui,
            engineFactory: () => _FakeEngine(twoHosts),
            glanceCard: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Scan local network'));
      await tester.pumpAndSettle();

      // Sort Vendor DESCENDING: Ubiquiti (.10) above Aruba (.9), which is the
      // reverse of the raw engine order.
      await tester.tap(find.text('Vendor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vendor'));
      await tester.pumpAndSettle();
      expect(
        displayedOrder(tester),
        <String>['10.0.10.10', '10.0.10.9'],
        reason: 'table honours vendor descending',
      );

      await tester.tap(find.byTooltip('Copy results'));
      await tester.pumpAndSettle();
      expect(
        copiedOrder(clipboard.last),
        displayedOrder(tester),
        reason: 'TABLE layout: clipboard must match what is on screen',
      );

      // Let the §8.16 confirm window lapse so the affordance reverts from
      // "Results copied" back to "Copy results" and can be found again.
      await tester.pump(const Duration(milliseconds: 1600));

      // Now the resize. The sort selection survives it; the ordering must too.
      await tester.binding.setSurfaceSize(const Size(500, 900));
      await tester.pumpAndSettle();
      expect(
        find.byType(NetworkDiscoveryTable),
        findsNothing,
        reason: 'narrow viewport reflows to cards',
      );

      await tester.tap(find.byTooltip('Copy results'));
      await tester.pumpAndSettle();
      expect(
        copiedOrder(clipboard.last),
        displayedOrder(tester),
        reason: 'CARD layout: clipboard must match what is on screen',
      );
      // And the sort the user chose is still the order they see, rather than
      // the cards silently reverting to raw engine order.
      expect(displayedOrder(tester), <String>['10.0.10.10', '10.0.10.9']);

      // Drain the second confirm window so no timer outlives the test.
      await tester.pump(const Duration(milliseconds: 1600));
    });
  });
}
