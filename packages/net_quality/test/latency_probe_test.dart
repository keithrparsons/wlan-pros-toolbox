import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

/// Builds a connector that returns the given per-call RTTs in milliseconds.
/// A null entry simulates a failed/lost sample by throwing.
LatencyConnector scriptedConnector(List<double?> rttsMs) {
  var i = 0;
  return (host, port, timeout) async {
    final v = rttsMs[i++];
    if (v == null) {
      throw const SocketExceptionStub('lost');
    }
    return Duration(microseconds: (v * 1000).round());
  };
}

class SocketExceptionStub implements Exception {
  final String message;
  const SocketExceptionStub(this.message);
}

void main() {
  group('LatencyProbe', () {
    test('all samples succeed', () async {
      final probe = LatencyProbe(
        host: 'example.com',
        samples: 4,
        connector: scriptedConnector(<double?>[10, 20, 30, 40]),
      );
      final s = await probe.measure();
      expect(s.sent, 4);
      expect(s.received, 4);
      expect(s.lossPct, 0);
      expect(s.minMs, 10);
      expect(s.maxMs, 40);
      expect(s.avgMs, closeTo(25, 0.001));
    });

    test('some samples lost', () async {
      final probe = LatencyProbe(
        host: 'example.com',
        samples: 4,
        connector: scriptedConnector(<double?>[10, null, 30, null]),
      );
      final s = await probe.measure();
      expect(s.sent, 4);
      expect(s.received, 2);
      expect(s.lossPct, 50);
      expect(s.avgMs, closeTo(20, 0.001));
      expect(s.minMs, 10);
      expect(s.maxMs, 30);
    });

    test('all samples lost reports loss 100 and zeroed stats', () async {
      final probe = LatencyProbe(
        host: 'example.com',
        samples: 3,
        connector: scriptedConnector(<double?>[null, null, null]),
      );
      final s = await probe.measure();
      expect(s.sent, 3);
      expect(s.received, 0);
      expect(s.lossPct, 100);
      expect(s.avgMs, 0);
      expect(s.minMs, 0);
      expect(s.maxMs, 0);
      expect(s.jitterMs, 0);
    });

    test('single successful sample yields zero jitter', () async {
      final probe = LatencyProbe(
        host: 'example.com',
        samples: 1,
        connector: scriptedConnector(<double?>[15]),
      );
      final s = await probe.measure();
      expect(s.received, 1);
      expect(s.jitterMs, 0);
      expect(s.avgMs, 15);
    });

    test('jitter is mean absolute difference of consecutive samples', () async {
      // Samples 10,20,40,30 -> diffs |20-10|=10, |40-20|=20, |30-40|=10
      // -> mean = 40/3 = 13.333...
      final probe = LatencyProbe(
        host: 'example.com',
        samples: 4,
        connector: scriptedConnector(<double?>[10, 20, 40, 30]),
      );
      final s = await probe.measure();
      expect(s.jitterMs, closeTo(40 / 3, 0.001));
    });
  });
}
