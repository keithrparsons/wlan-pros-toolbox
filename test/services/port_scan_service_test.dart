// PortScanService unit tests — exercise port-spec parsing, the open/closed/
// filtered taxonomy, and bounded concurrency, all with a fake connector so no
// real sockets are opened.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/port_scan_service.dart';

void main() {
  group('parsePortSpec', () {
    test('parses a comma list', () {
      expect(
        PortScanService.parsePortSpec('22, 80, 443'),
        <int>[22, 80, 443],
      );
    });

    test('expands a range', () {
      expect(
        PortScanService.parsePortSpec('80-83'),
        <int>[80, 81, 82, 83],
      );
    });

    test('de-duplicates and sorts mixed input', () {
      expect(
        PortScanService.parsePortSpec('443, 22, 80, 22, 81-82'),
        <int>[22, 80, 81, 82, 443],
      );
    });

    test('handles a reversed range', () {
      expect(PortScanService.parsePortSpec('83-80'), <int>[80, 81, 82, 83]);
    });

    test('drops out-of-range and non-numeric tokens', () {
      expect(
        PortScanService.parsePortSpec('0, 1, 65535, 65536, abc, 80'),
        <int>[1, 80, 65535],
      );
    });

    test('returns empty for garbage', () {
      expect(PortScanService.parsePortSpec('hello world'), <int>[]);
    });
  });

  group('serviceFor', () {
    test('labels well-known ports', () {
      expect(PortScanService.serviceFor(443), 'HTTPS');
      expect(PortScanService.serviceFor(5201), 'iperf3');
    });
    test('returns null for unknown ports', () {
      expect(PortScanService.serviceFor(12345), isNull);
    });
  });

  group('scan classification', () {
    test('connect success → OPEN', () async {
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PortScanProgress> ticks =
          await svc.scan(host: 'h', ports: <int>[80]).toList();
      final PortResult result = ticks.last.lastResult!;
      expect(result.status, PortStatus.open);
      expect(result.port, 80);
      expect(result.serviceName, 'HTTP');
    });

    test('refused (osError present) → CLOSED', () async {
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async {
          throw const SocketException(
            'Connection refused',
            osError: OSError('refused', 61),
          );
        },
      );
      final List<PortScanProgress> ticks =
          await svc.scan(host: 'h', ports: <int>[81]).toList();
      expect(ticks.last.lastResult!.status, PortStatus.closed);
    });

    test('timeout (no osError, elapsed ~ timeout) → FILTERED', () async {
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async {
          await Future<void>.delayed(timeout);
          throw const SocketException('timed out'); // osError == null
        },
      );
      final List<PortScanProgress> ticks = await svc
          .scan(
            host: 'h',
            ports: <int>[82],
            timeout: const Duration(milliseconds: 80),
          )
          .toList();
      expect(ticks.last.lastResult!.status, PortStatus.filtered);
    });
  });

  group('scan streaming + concurrency', () {
    test('emits an initial 0/total tick then one per port', () async {
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PortScanProgress> ticks = await svc
          .scan(host: 'h', ports: <int>[1, 2, 3])
          .toList();
      // 1 initial + 3 per-port.
      expect(ticks.length, 4);
      expect(ticks.first.completed, 0);
      expect(ticks.first.total, 3);
      expect(ticks.last.completed, 3);
    });

    test('never exceeds the concurrency cap of live connects', () async {
      int live = 0;
      int peak = 0;
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async {
          live++;
          peak = peak > live ? peak : live;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          live--;
          return _FakeSocket();
        },
      );
      await svc
          .scan(
            host: 'h',
            ports: List<int>.generate(50, (int i) => i + 1),
            concurrency: 8,
          )
          .toList();
      expect(peak, lessThanOrEqualTo(8));
    });

    test('empty port list closes immediately with a single tick', () async {
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async => _FakeSocket(),
      );
      final List<PortScanProgress> ticks =
          await svc.scan(host: 'h', ports: <int>[]).toList();
      expect(ticks.length, 1);
      expect(ticks.single.total, 0);
    });

    test('cancel stops the scan before all ports complete', () async {
      final Completer<void> cancel = Completer<void>();
      final PortScanService svc = PortScanService(
        connector: (host, port, {required timeout}) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return _FakeSocket();
        },
      );
      final Stream<PortScanProgress> stream = svc.scan(
        host: 'h',
        ports: List<int>.generate(200, (int i) => i + 1),
        concurrency: 4,
        cancel: cancel.future,
      );
      final List<PortScanProgress> got = <PortScanProgress>[];
      final Completer<void> done = Completer<void>();
      stream.listen(got.add, onDone: done.complete);
      // Let a few complete, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 25));
      cancel.complete();
      await done.future;
      // Far fewer than the full 200 completed.
      expect(got.last.completed, lessThan(200));
    });
  });
}

/// Minimal fake Socket — only `destroy()` is invoked by the service.
class _FakeSocket implements Socket {
  bool destroyed = false;

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
