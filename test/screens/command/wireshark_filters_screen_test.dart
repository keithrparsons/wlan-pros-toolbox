// Tests for the Wireshark 802.11 Filters screen.
//
// Dataset assertions lock in the two Pax corrections:
//   1. RSN cipher = pcs/gcs.type (Table 9-149); AKM = akms.type (Table 9-151).
//      The source card mislabeled cipher values as AKM — guard against regress.
//   2. The 5 GHz band filter uses the SAFE freq-range fallback, NOT the
//      unverified radiotap.channel.flags.5ghz child-token.
// A widget smoke confirms render + the group-aware live filter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/wireshark_filters_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  List<WiresharkFilter> allFilters() => <WiresharkFilter>[
        for (final FilterGroup g in WiresharkFiltersScreen.groups) ...g.filters,
      ];

  FilterGroup groupFor(String label) =>
      WiresharkFiltersScreen.groups.firstWhere((g) => g.label == label);

  group('Wireshark filters — Pax corrections', () {
    test('RSN cipher group uses pcs/gcs.type, NOT akms.type', () {
      final FilterGroup cipher = groupFor('RSN cipher (display)');
      for (final WiresharkFilter f in cipher.filters) {
        expect(
          f.filter.contains('akms'),
          isFalse,
          reason: 'cipher values must be pcs/gcs.type, never akms.type',
        );
        expect(
          f.filter.contains('pcs.type') || f.filter.contains('gcs.type'),
          isTrue,
        );
      }
      // CCMP-128 anchor.
      expect(
        cipher.filters.any((f) =>
            f.filter == 'wlan.rsn.pcs.type == 4' &&
            f.description.contains('CCMP-128')),
        isTrue,
      );
    });

    test('RSN AKM group uses akms.type with correct selectors', () {
      final FilterGroup akm = groupFor('RSN AKM (display)');
      for (final WiresharkFilter f in akm.filters) {
        expect(f.filter.contains('akms.type'), isTrue);
      }
      // SAE = 8, OWE = 18, PSK = 2, 802.1X = 1.
      expect(
        akm.filters.any((f) =>
            f.filter == 'wlan.rsn.akms.type == 8' &&
            f.description.contains('SAE')),
        isTrue,
      );
      expect(
        akm.filters.any((f) =>
            f.filter == 'wlan.rsn.akms.type == 18' &&
            f.description.contains('OWE')),
        isTrue,
      );
    });

    test('5 GHz band filter uses the SAFE freq-range fallback, not flags.5ghz',
        () {
      // The unverified child-token must NOT ship anywhere.
      for (final WiresharkFilter f in allFilters()) {
        expect(
          f.filter.contains('channel.flags.5ghz'),
          isFalse,
          reason: 'ship the freq-range fallback, not the unverified token',
        );
      }
      // The freq-range 5 GHz filter ships instead.
      expect(
        allFilters().any((f) =>
            f.filter.contains('radiotap.channel.freq >= 5000') &&
            f.description.contains('5 GHz')),
        isTrue,
      );
    });

    test('general TCP/IP display groups are present with accurate syntax', () {
      // The three new Layer 3-4 groups (2026-07-18).
      final FilterGroup ip = groupFor('IP addressing (TCP/IP display)');
      final FilterGroup tcpUdp = groupFor('TCP / UDP (TCP/IP display)');
      final FilterGroup proto = groupFor('Higher-layer protocols (TCP/IP display)');

      bool hasIn(FilterGroup g, String filter) =>
          g.filters.any((f) => f.filter == filter);

      // IP addressing.
      expect(hasIn(ip, 'ip.addr == 10.0.0.5'), isTrue);
      expect(hasIn(ip, 'ip.src == 10.0.0.5'), isTrue);
      expect(hasIn(ip, 'ip.dst == 10.0.0.5'), isTrue);
      // TCP/UDP incl. the SYN-without-ACK and analysis filters + stream index.
      expect(hasIn(tcpUdp, 'tcp.port == 443'), isTrue);
      expect(hasIn(tcpUdp, 'udp.port == 53'), isTrue);
      expect(
        hasIn(tcpUdp, 'tcp.flags.syn == 1 && tcp.flags.ack == 0'),
        isTrue,
      );
      expect(hasIn(tcpUdp, 'tcp.analysis.retransmission'), isTrue);
      expect(hasIn(tcpUdp, 'tcp.stream eq 0'), isTrue);
      // Higher-layer protocols.
      expect(hasIn(proto, 'icmp'), isTrue);
      expect(hasIn(proto, 'dns'), isTrue);
      expect(hasIn(proto, 'http'), isTrue);
      expect(hasIn(proto, 'arp'), isTrue);
    });

    test('frame type/subtype anchors (beacon=8, deauth=12)', () {
      expect(
        allFilters().any((f) =>
            f.filter == 'wlan.fc.type_subtype == 8' &&
            f.description == 'Beacon'),
        isTrue,
      );
      expect(
        allFilters().any((f) =>
            f.filter == 'wlan.fc.type_subtype == 12' &&
            f.description == 'Deauthentication'),
        isTrue,
      );
    });
  });

  group('WiresharkFiltersScreen widget', () {
    testWidgets('renders title and group headings', (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(),
              home: const WiresharkFiltersScreen()),
        );
        expect(find.text('Wireshark 802.11 Filters'), findsWidgets);
        expect(find.text('RSN AKM (display)'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    testWidgets('filtering by "rsn" surfaces both RSN groups', (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
              theme: AppTheme.dark(),
              home: const WiresharkFiltersScreen()),
        );
        await tester.enterText(find.byType(TextField), 'rsn');
        await tester.pump();
        expect(find.text('RSN cipher (display)'), findsOneWidget);
        expect(find.text('RSN AKM (display)'), findsOneWidget);
        // A non-RSN group heading should be gone.
        expect(find.text('Address (display)'), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/768 widths', (tester) async {
      for (final double width in <double>[320, 768]) {
        await _withViewport(tester, Size(width, 3000), () async {
          await tester.pumpWidget(
            MaterialApp(
                theme: AppTheme.dark(),
                home: const WiresharkFiltersScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
