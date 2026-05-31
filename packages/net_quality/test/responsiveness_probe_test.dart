import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('ResponsivenessProbe', () {
    test('idle and loaded averages and rpm = 60000/loadedAvg', () async {
      // First 3 samples (idle) average 10ms, next 5 (loaded) average 60ms.
      final idle = <double>[10, 10, 10];
      final loaded = <double>[40, 50, 60, 70, 80]; // avg 60
      final all = <double>[...idle, ...loaded];
      var i = 0;
      var loadStarted = false;

      final probe = ResponsivenessProbe(
        idleSamples: 3,
        loadedSamples: 5,
        latencySampler: () async =>
            Duration(microseconds: (all[i++] * 1000).round()),
        loadGenerator: () async {
          loadStarted = true;
        },
      );

      final s = await probe.measure();
      expect(s.idleAvgRttMs, closeTo(10, 0.001));
      expect(s.loadedAvgRttMs, closeTo(60, 0.001));
      expect(s.rpm, closeTo(1000, 0.001)); // 60000 / 60
      expect(s.samples, 5);
      expect(loadStarted, isTrue);
    });

    test('divide-by-zero guard yields rpm 0 when loaded avg is 0', () async {
      final probe = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 0,
        latencySampler: () async => Duration.zero,
        loadGenerator: () async {},
      );
      final s = await probe.measure();
      expect(s.loadedAvgRttMs, 0);
      expect(s.rpm, 0);
      expect(s.samples, 0);
    });

    test('sample counts honor configuration', () async {
      var calls = 0;
      final probe = ResponsivenessProbe(
        idleSamples: 2,
        loadedSamples: 4,
        latencySampler: () async {
          calls++;
          return const Duration(milliseconds: 10);
        },
        loadGenerator: () async {},
      );
      await probe.measure();
      expect(calls, 6); // 2 idle + 4 loaded
    });
  });
}
