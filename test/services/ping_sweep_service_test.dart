// PingSweepService unit tests — exercise spec parsing/validation (valid CIDR
// and range accepted, oversized + malformed rejected, no silent truncation),
// the per-host TCP-handshake classification (responds vs silent), and the
// streamed live/total tally — all with a fake connector so no real sockets open.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ping_sweep_service.dart';

void main() {
  group('parseSpec — validation', () {
    test('accepts a /24 CIDR and expands to 254 usable hosts', () {
      final SweepSpec spec = PingSweepService.parseSpec('192.168.1.0/24');
      expect(spec.isValid, isTrue);
      expect(spec.error, isNull);
      // /24 excludes the .0 network and .255 broadcast → 254 usable.
      expect(spec.hosts.length, 254);
      expect(spec.hosts.first, '192.168.1.1');
      expect(spec.hosts.last, '192.168.1.254');
    });

    test('accepts a non-zero CIDR base by masking to the network', () {
      final SweepSpec spec = PingSweepService.parseSpec('192.168.1.37/24');
      expect(spec.isValid, isTrue);
      expect(spec.hosts.first, '192.168.1.1');
      expect(spec.hosts.last, '192.168.1.254');
    });

    test('accepts a /30 (2 usable hosts)', () {
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.0/30');
      expect(spec.isValid, isTrue);
      expect(spec.hosts, <String>['10.0.0.1', '10.0.0.2']);
    });

    test('accepts a /32 as a single-host sweep', () {
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.5/32');
      expect(spec.isValid, isTrue);
      expect(spec.hosts, <String>['10.0.0.5']);
    });

    test('accepts a full base+range', () {
      final SweepSpec spec =
          PingSweepService.parseSpec('192.168.1.10-192.168.1.13');
      expect(spec.isValid, isTrue);
      expect(spec.hosts,
          <String>['192.168.1.10', '192.168.1.11', '192.168.1.12', '192.168.1.13']);
    });

    test('accepts last-octet shorthand range', () {
      final SweepSpec spec = PingSweepService.parseSpec('192.168.1.10-12');
      expect(spec.isValid, isTrue);
      expect(spec.hosts,
          <String>['192.168.1.10', '192.168.1.11', '192.168.1.12']);
    });

    test('accepts a bare single IPv4', () {
      final SweepSpec spec = PingSweepService.parseSpec('192.168.1.42');
      expect(spec.isValid, isTrue);
      expect(spec.hosts, <String>['192.168.1.42']);
    });

    test('rejects an oversized /16 — never silently truncated', () {
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.0/16');
      expect(spec.isValid, isFalse);
      expect(spec.error, SweepSpecError.tooLarge);
      expect(spec.hosts, isEmpty);
      // The UI needs the true requested count to say "that's N hosts".
      expect(spec.requestedCount, greaterThan(PingSweepService.maxHosts));
    });

    test('rejects an oversized explicit range', () {
      final SweepSpec spec =
          PingSweepService.parseSpec('10.0.0.1-10.0.3.0');
      expect(spec.error, SweepSpecError.tooLarge);
      expect(spec.requestedCount, greaterThan(PingSweepService.maxHosts));
    });

    test('a /23 (510 hosts) is over the /24 cap and rejected', () {
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.0/23');
      expect(spec.error, SweepSpecError.tooLarge);
    });

    test('rejects malformed input', () {
      for (final String bad in <String>[
        '',
        'not-an-ip',
        '192.168.1.0/33',
        '999.1.1.1/24',
        '192.168.1.0/',
        '192.168.1.50-192.168.1.10', // end before start
        '192.168.1.10-999',
        '192.168.1',
      ]) {
        final SweepSpec spec = PingSweepService.parseSpec(bad);
        expect(spec.isValid, isFalse, reason: 'should reject "$bad"');
        expect(spec.error, SweepSpecError.malformed, reason: 'for "$bad"');
      }
    });

    test('produces a readable range label', () {
      expect(
        PingSweepService.parseSpec('192.168.1.0/24').label,
        '192.168.1.1–192.168.1.254',
      );
      expect(PingSweepService.parseSpec('192.168.1.42').label, '192.168.1.42');
    });
  });

  group('sweep — per-host classification', () {
    test('a host that responds (handshake completes) is reported live', () async {
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.1');
      final List<SweepProgress> ticks =
          await svc.sweep(spec: spec, timeout: Duration.zero).toList();
      final SweepProgress last = ticks.last;
      expect(last.completed, 1);
      expect(last.total, 1);
      expect(last.live, 1);
      expect(last.lastResponsive, isNotNull);
      expect(last.lastResponsive!.host, '10.0.0.1');
      expect(last.lastResponsive!.responded, isTrue);
      expect(last.lastResponsive!.rtt, isNotNull);
    });

    test('a refused host (RST, errno 61) still counts as responsive', () async {
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async {
          throw const SocketException(
            'Connection refused',
            osError: OSError('refused', 61),
          );
        },
      );
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.1');
      final List<SweepProgress> ticks =
          await svc.sweep(spec: spec, timeout: Duration.zero).toList();
      expect(ticks.last.live, 1,
          reason: 'a RST proves the host answered the SYN');
    });

    test('a host that does not respond (timeout) is silent', () async {
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async {
          await Future<void>.delayed(timeout);
          throw const SocketException('Connection timed out',
              osError: OSError('Connection timed out', 110));
        },
      );
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.1');
      final List<SweepProgress> ticks = await svc
          .sweep(
            spec: spec,
            timeout: const Duration(milliseconds: 20),
          )
          .toList();
      final SweepProgress last = ticks.last;
      expect(last.completed, 1);
      expect(last.live, 0);
      expect(last.lastResponsive, isNull);
    });
  });

  group('sweep — live/total tally over a range', () {
    test('tallies only responsive hosts; completes every host', () async {
      // Odd last-octet → responds; even → times out. Range .1–.6 → 3 live.
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async {
          final int lastOctet = int.parse(host.split('.').last);
          if (lastOctet.isOdd) return _FakeSocket();
          await Future<void>.delayed(timeout);
          throw const SocketException('Connection timed out',
              osError: OSError('Connection timed out', 110));
        },
      );
      final SweepSpec spec = PingSweepService.parseSpec('192.168.1.1-6');
      expect(spec.hosts.length, 6);

      final List<SweepProgress> ticks = await svc
          .sweep(
            spec: spec,
            timeout: const Duration(milliseconds: 20),
            concurrency: 4,
          )
          .toList();

      final SweepProgress last = ticks.last;
      expect(last.completed, 6, reason: 'every host is probed');
      expect(last.total, 6);
      expect(last.live, 3, reason: '.1 .3 .5 respond; .2 .4 .6 silent');

      // Live count is monotonic non-decreasing across the stream.
      int prevLive = 0;
      for (final SweepProgress p in ticks) {
        expect(p.live, greaterThanOrEqualTo(prevLive));
        prevLive = p.live;
      }

      // Only the responsive hosts surface as lastResponsive, all odd-octet.
      final List<String> responsive = ticks
          .where((SweepProgress p) => p.lastResponsive != null)
          .map((SweepProgress p) => p.lastResponsive!.host)
          .toList();
      expect(responsive.length, 3);
      for (final String h in responsive) {
        expect(int.parse(h.split('.').last).isOdd, isTrue);
      }
    });

    test('emits the initial 0/total tick before any probe settles', () async {
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.1-3');
      final List<SweepProgress> ticks =
          await svc.sweep(spec: spec, timeout: Duration.zero).toList();
      expect(ticks.first.completed, 0);
      expect(ticks.first.total, 3);
      expect(ticks.first.live, 0);
    });

    test('first responding port wins; host probed across a port set', () async {
      // Only port 80 answers; 443 (first in the list) times out. The host must
      // still be reported live via the fallback port.
      final PingSweepService svc = PingSweepService(
        connector: (host, port, {required timeout}) async {
          if (port == 80) return _FakeSocket();
          await Future<void>.delayed(timeout);
          throw const SocketException('Connection timed out',
              osError: OSError('Connection timed out', 110));
        },
      );
      final SweepSpec spec = PingSweepService.parseSpec('10.0.0.9');
      final List<SweepProgress> ticks = await svc
          .sweep(
            spec: spec,
            ports: const <int>[443, 80],
            timeout: const Duration(milliseconds: 20),
          )
          .toList();
      expect(ticks.last.live, 1);
    });
  });
}

/// Minimal fake Socket — only `destroy()` is invoked by the service.
class _FakeSocket implements Socket {
  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
