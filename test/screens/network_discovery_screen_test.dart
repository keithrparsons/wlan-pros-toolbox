// Network Discovery screen — widget smoke tests (TICKET-HSD-02 W1).
//
// Focused state-coverage checks for the productized screen: it builds in idle
// state with the scan action, renders a discovered host (IP + device type +
// MAC/vendor) from an injected fake engine, surfaces an honest "no hosts" empty
// state, and reports an engine error without fabricating a result. A fake
// engine + a pre-built in-memory MacOuiService keep the tests off the real
// network and off any asset load. Deeper a11y/visual gating is W7 (Vera).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_host.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_discovery_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A fake engine that replays a scripted progress stream and exposes a scripted
/// [lastResult] — no sockets, no isolate, no mDNS, no plugins.
class _FakeEngine implements LanDiscoveryEngine {
  _FakeEngine(this._result);

  final DiscoveryResult _result;

  @override
  DiscoveryResult? get lastResult => _result;

  @override
  Stream<DiscoveryProgress> run() async* {
    yield const DiscoveryProgress(DiscoveryPhase.seeding, 0.02);
    yield const DiscoveryProgress(DiscoveryPhase.scanning, 0.5);
    yield const DiscoveryProgress(DiscoveryPhase.complete, 1.0);
  }

  // The screen only ever uses run() + lastResult; nothing else is reachable.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: child);

void main() {
  final MacOuiService oui =
      MacOuiService.fromTable(<String, String>{'FCECDA': 'Ubiquiti'});

  testWidgets('idle: shows the concept-less scan action, no host list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(
      NetworkDiscoveryScreen(service: oui, glanceCard: const SizedBox.shrink()),
    ));
    expect(find.text('Network Discovery'), findsOneWidget);
    expect(find.text('Scan local network'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('success: renders a discovered host with IP, type, and vendor', (
    WidgetTester tester,
  ) async {
    final DiscoveryResult result = DiscoveryResult(
      hosts: <LanHost>[
        LanHost(
          ip: '10.0.10.5',
          openPorts: <int>{80, 443},
          mac: 'fc:ec:da:01:23:45',
          vendor: 'Ubiquiti',
          deviceType: DeviceType.webServer,
        ),
      ],
      subnetLabel: '10.0.10.1–10.0.10.254',
      selfIp: '10.0.10.20',
      gateway: '10.0.10.1',
      arp: const ArpReadResult(available: true),
    );

    await tester.pumpWidget(_host(
      NetworkDiscoveryScreen(
        service: oui,
        engineFactory: () => _FakeEngine(result),
        glanceCard: const SizedBox.shrink(),
      ),
    ));
    await tester.tap(find.text('Scan local network'));
    await tester.pumpAndSettle();

    expect(find.text('1 host found'), findsOneWidget);
    expect(find.text('10.0.10.5'), findsOneWidget);
    expect(find.text(DeviceType.webServer.label), findsOneWidget);
    expect(find.textContaining('Ubiquiti'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });

  testWidgets('empty: a completed scan with no hosts shows an honest empty '
      'state, not an error', (WidgetTester tester) async {
    final DiscoveryResult result = DiscoveryResult(
      hosts: const <LanHost>[],
      subnetLabel: '10.0.10.1–10.0.10.254',
      arp: const ArpReadResult.unavailable('iOS cannot read the ARP table.'),
    );

    await tester.pumpWidget(_host(
      NetworkDiscoveryScreen(
        service: oui,
        engineFactory: () => _FakeEngine(result),
        glanceCard: const SizedBox.shrink(),
      ),
    ));
    await tester.tap(find.text('Scan local network'));
    await tester.pumpAndSettle();

    expect(find.text('0 hosts found'), findsOneWidget);
    expect(find.text('No hosts responded'), findsOneWidget);
    // The desktop-MAC ceiling is stated, not rendered as a blank field.
    expect(find.textContaining('need a desktop ARP read'), findsOneWidget);
  });

  testWidgets('error: an engine that reports a subnet error surfaces it, never '
      'a fabricated host list', (WidgetTester tester) async {
    final DiscoveryResult result = const DiscoveryResult(
      hosts: <LanHost>[],
      subnetLabel: 'unknown',
      error: 'Could not derive a local subnet to scan.',
    );

    await tester.pumpWidget(_host(
      NetworkDiscoveryScreen(
        service: oui,
        engineFactory: () => _FakeEngine(result),
        glanceCard: const SizedBox.shrink(),
      ),
    ));
    await tester.tap(find.text('Scan local network'));
    await tester.pumpAndSettle();

    expect(find.text('Could not scan'), findsOneWidget);
    expect(
      find.textContaining('Could not derive a local subnet'),
      findsOneWidget,
    );
  });
}
