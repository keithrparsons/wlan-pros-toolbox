// ArpNdpService unit tests — the regression-prone parts: subnet/host
// derivation, capability DERIVED from the platform ArpReader (never a
// hand-maintained table), and active discovery with an injected connector +
// ArpReader (no network, no filesystem, no platform channel).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/arp_ndp_service.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';

/// A reader that declares a capability and returns a scripted result, so the
/// tests drive the real cross-product: capable/incapable × read ok/failed.
class _FakeArpReader implements ArpReader {
  const _FakeArpReader({required this.readsMac, required this.result});

  @override
  final bool readsMac;

  final ArpReadResult result;

  @override
  Future<ArpReadResult> read() async => result;
}

/// macOS/Windows shape: capable, read succeeds with these entries.
_FakeArpReader _capableReader(Map<String, String> byIp) => _FakeArpReader(
      readsMac: true,
      result: ArpReadResult(
        available: true,
        entries: <ArpEntry>[
          for (final MapEntry<String, String> e in byIp.entries)
            ArpEntry(ip: e.key, mac: e.value),
        ],
      ),
    );

/// The case nobody wrote: a platform that CAN read, whose read FAILED.
const _FakeArpReader _capableButFailingReader = _FakeArpReader(
  readsMac: true,
  result: ArpReadResult.failed('GetIpNetTable returned ERROR_NOT_SUPPORTED'),
);

/// Counts reads so the lazy-load discipline is testable.
class _CountingArpReader implements ArpReader {
  _CountingArpReader(this._onRead);

  final void Function() _onRead;

  @override
  bool get readsMac => true;

  @override
  Future<ArpReadResult> read() async {
    _onRead();
    return const ArpReadResult(available: true);
  }
}

/// iOS/Android shape: no reader for the neighbor table at all.
const _FakeArpReader _incapableReader = _FakeArpReader(
  readsMac: false,
  result: ArpReadResult.unsupported('Sandbox cannot read the ARP table.'),
);

void main() {
  group('hostsForSubnet', () {
    test('/24 yields 254 usable hosts, excludes network + broadcast', () {
      final List<String> hosts =
          ArpNdpService.hostsForSubnet('192.168.1.50', 24);
      expect(hosts.length, 254);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.0'))); // network
      expect(hosts, isNot(contains('192.168.1.255'))); // broadcast
    });

    test('/30 yields 2 usable hosts', () {
      final List<String> hosts =
          ArpNdpService.hostsForSubnet('10.0.0.1', 30);
      expect(hosts, <String>['10.0.0.1', '10.0.0.2']);
    });

    test('refuses prefixes wider than /22 (never sweeps a /8)', () {
      expect(ArpNdpService.hostsForSubnet('10.0.0.1', 8), isEmpty);
      expect(ArpNdpService.hostsForSubnet('10.0.0.1', 16), isEmpty);
    });

    test('IPv6 / malformed input → empty', () {
      expect(ArpNdpService.hostsForSubnet('fe80::1', 64), isEmpty);
      expect(ArpNdpService.hostsForSubnet('not.an.ip', 24), isEmpty);
    });
  });

  group('defaultLanHosts', () {
    test('derives /24 and excludes the device own IP', () {
      final List<String> hosts = ArpNdpService.defaultLanHosts('192.168.1.50');
      expect(hosts.length, 253); // 254 minus self
      expect(hosts, isNot(contains('192.168.1.50')));
      expect(hosts, contains('192.168.1.1'));
    });
  });

  group('capabilityFor — derived from the reader, not a platform table', () {
    test('iOS → unavailable (the sweep itself is not offered)', () {
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: true,
          readerOverride: _incapableReader,
        ),
        ArpCapability.unavailable,
      );
    });

    test('macOS (reader available) → sweepWithMac', () {
      // The inverted matrix claimed sweepNoMac here while
      // MethodChannelArpReader was shipping and working.
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          readerOverride: _capableReader(const <String, String>{}),
        ),
        ArpCapability.sweepWithMac,
      );
    });

    test('Windows (reader available) → sweepWithMac', () {
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          readerOverride: const _FakeArpReader(
            readsMac: true,
            result: ArpReadResult(available: true),
          ),
        ),
        ArpCapability.sweepWithMac,
      );
    });

    test(
        'capable platform whose read FAILS is still sweepWithMac — capability '
        'is not revoked by one failed read', () {
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          readerOverride: _capableButFailingReader,
        ),
        ArpCapability.sweepWithMac,
      );
    });

    test('Android (no reader) → sweepNoMac, NOT sweepWithMac', () {
      // The old table claimed /proc/net/arp gave Android real MACs. It does
      // not: platformArpReader() hands Android an UnavailableArpReader.
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          readerOverride: _incapableReader,
        ),
        ArpCapability.sweepNoMac,
      );
    });

    test('unknown platform (no reader) → sweepNoMac', () {
      expect(
        ArpNdpService.capabilityFor(
          isIOSOverride: false,
          readerOverride: const _FakeArpReader(
            readsMac: false,
            result: ArpReadResult.unsupported('Out of scope on this platform.'),
          ),
        ),
        ArpCapability.sweepNoMac,
      );
    });
  });

  group('the real platform readers agree with the capability they drive', () {
    test('macOS + Windows readers declare readsMac; iOS/Android do not', () {
      expect(const MethodChannelArpReader().readsMac, isTrue);
      expect(const WindowsIpNetTableArpReader().readsMac, isTrue);
      expect(const UnavailableArpReader('sandboxed').readsMac, isFalse);
    });

    test('an unsupported result is distinguishable from a failed one', () {
      const ArpReadResult unsupported =
          ArpReadResult.unsupported('iOS sandbox cannot read the ARP table.');
      const ArpReadResult failed = ArpReadResult.failed('read blew up');
      expect(unsupported.platformSupported, isFalse);
      expect(failed.platformSupported, isTrue);
      // Both are "not available" — that is exactly why available alone was
      // never enough to pick the right sentence.
      expect(unsupported.available, isFalse);
      expect(failed.available, isFalse);
    });
  });

  group('missingMacReason — only one outcome may blame the platform', () {
    test('notAttempted → the platform claim (the only one that earns it)', () {
      expect(missingMacReason(MacReadOutcome.notAttempted),
          'Not exposed on this platform');
    });

    test('failed → could not, NOT cannot', () {
      final String s = missingMacReason(MacReadOutcome.failed);
      expect(s, 'MAC read failed');
      expect(s, isNot(contains('platform')));
    });

    test('ok but host absent → a statement about the cache, not the platform',
        () {
      final String s = missingMacReason(MacReadOutcome.ok);
      expect(s, 'Not in the ARP cache');
      expect(s, isNot(contains('platform')));
    });

    test('no two outcomes render the same sentence', () {
      final Set<String> all =
          MacReadOutcome.values.map(missingMacReason).toSet();
      expect(all.length, MacReadOutcome.values.length);
    });
  });

  group('discover', () {
    // A connector that "connects" (host up) for an allow-listed set, and
    // throws the REAL dead-host SocketException (Connection timed out, errno
    // 110 — note it DOES carry an osError) otherwise (host down).
    Future<Socket> Function(String, int, {required Duration timeout})
        connectorFor(Set<String> upHosts) {
      return (String host, int port, {required Duration timeout}) async {
        if (upHosts.contains(host)) {
          // We can't easily fabricate a real Socket; throw a refusal instead,
          // which the probe treats as "host up" (ECONNREFUSED = it answered).
          throw SocketException(
            'Connection refused',
            osError: const OSError('Connection refused', 61),
          );
        }
        throw const SocketException('Connection timed out',
              osError: OSError('Connection timed out', 110));
      };
    }

    test('lists only responders; down hosts excluded', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1', '192.168.1.5'}),
        arpReader: _incapableReader, // sweepNoMac path
      );
      final List<Neighbor> found = <Neighbor>[];
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1', '192.168.1.2', '192.168.1.5'],
        capabilityOverride: ArpCapability.sweepNoMac,
      )) {
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      final Set<String> ips = found.map((Neighbor n) => n.ip).toSet();
      expect(ips, <String>{'192.168.1.1', '192.168.1.5'});
      // sweepNoMac → no MAC fabricated.
      expect(found.every((Neighbor n) => n.mac == null), isTrue);
    });

    test('sweepWithMac attaches real MAC from the injected ARP table', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1'}),
        arpReader: _capableReader(
          const <String, String>{'192.168.1.1': 'de:ad:be:ef:00:01'},
        ),
      );
      final List<Neighbor> found = <Neighbor>[];
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1', '192.168.1.2'],
        capabilityOverride: ArpCapability.sweepWithMac,
      )) {
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      expect(found.length, 1);
      expect(found.first.ip, '192.168.1.1');
      expect(found.first.mac, 'de:ad:be:ef:00:01');
    });

    test(
        'THE CASE NOBODY WROTE — capable platform, read FAILED: no MAC, and '
        'the outcome says failed, not notAttempted', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1'}),
        arpReader: _capableButFailingReader,
      );
      final List<Neighbor> found = <Neighbor>[];
      MacReadOutcome outcome = MacReadOutcome.notAttempted;
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1'],
        capabilityOverride: ArpCapability.sweepWithMac,
      )) {
        outcome = p.macRead;
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      // The host is still reported — a failed MAC read is not a failed sweep.
      expect(found.length, 1);
      expect(found.first.mac, isNull);
      // The distinction the UI needs: this platform CAN read, this read did
      // not. Reporting it as notAttempted is what produced the false
      // "this platform cannot" copy.
      expect(outcome, MacReadOutcome.failed);
      expect(outcome, isNot(MacReadOutcome.notAttempted));
    });

    test(
        'capable platform, read OK but host absent from the cache → ok, not '
        'failed (a "did not", not a "cannot")', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.9'}),
        // Read succeeds, but holds an entry for a DIFFERENT host.
        arpReader: _capableReader(
          const <String, String>{'192.168.1.1': 'de:ad:be:ef:00:01'},
        ),
      );
      final List<Neighbor> found = <Neighbor>[];
      MacReadOutcome outcome = MacReadOutcome.notAttempted;
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.9'],
        capabilityOverride: ArpCapability.sweepWithMac,
      )) {
        outcome = p.macRead;
        if (p.lastFound != null) found.add(p.lastFound!);
      }
      expect(found.single.mac, isNull);
      expect(found.single.fromArpTable, isFalse);
      expect(outcome, MacReadOutcome.ok);
    });

    test(
        'capable platform, successful but EMPTY read is still ok — and is not '
        're-read on every responder', () async {
      int reads = 0;
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1', '192.168.1.2'}),
        arpReader: _CountingArpReader(() => reads++),
      );
      MacReadOutcome outcome = MacReadOutcome.notAttempted;
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1', '192.168.1.2'],
        capabilityOverride: ArpCapability.sweepWithMac,
      )) {
        outcome = p.macRead;
      }
      expect(outcome, MacReadOutcome.ok);
      // Guarding on "cache is empty" instead of "already loaded" would read
      // once per responder.
      expect(reads, 1);
    });

    test('sweepNoMac never reads the neighbor table at all', () async {
      int reads = 0;
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{'192.168.1.1'}),
        arpReader: _CountingArpReader(() => reads++),
      );
      MacReadOutcome outcome = MacReadOutcome.ok;
      await for (final ArpScanProgress p in svc.discover(
        hosts: <String>['192.168.1.1'],
        capabilityOverride: ArpCapability.sweepNoMac,
      )) {
        outcome = p.macRead;
      }
      expect(reads, 0);
      expect(outcome, MacReadOutcome.notAttempted);
    });

    test('empty host list closes immediately with a 0/0 tick', () async {
      final ArpNdpService svc = ArpNdpService(
        connector: connectorFor(<String>{}),
        arpReader: _incapableReader,
      );
      final List<ArpScanProgress> ticks = await svc
          .discover(
            hosts: const <String>[],
            capabilityOverride: ArpCapability.sweepNoMac,
          )
          .toList();
      expect(ticks.length, 1);
      expect(ticks.first.total, 0);
      expect(ticks.first.found, 0);
    });

    test('cancel stops the sweep early', () async {
      final Completer<void> cancel = Completer<void>();
      final ArpNdpService svc = ArpNdpService(
        connector: (String host, int port, {required Duration timeout}) async {
          // Slow "down" responses so cancel can fire mid-sweep.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw const SocketException('Connection timed out',
              osError: OSError('Connection timed out', 110));
        },
        arpReader: _incapableReader,
      );
      final List<String> hosts =
          List<String>.generate(200, (int i) => '10.0.0.${i + 1}');
      int probed = 0;
      final StreamSubscription<ArpScanProgress> sub = svc
          .discover(
            hosts: hosts,
            capabilityOverride: ArpCapability.sweepNoMac,
            cancel: cancel.future,
            concurrency: 4,
          )
          .listen((ArpScanProgress p) => probed = p.probed);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancel.complete();
      await sub.asFuture<void>();
      await sub.cancel();
      expect(probed, lessThan(hosts.length));
    });
  });
}
