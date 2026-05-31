import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('ReachabilityProbe', () {
    const sites = <PopularSite>[
      PopularSite(name: 'A', host: 'a.example'),
      PopularSite(name: 'B', host: 'b.example'),
      PopularSite(name: 'C', host: 'c.example'),
    ];

    test('preserves input order even with varying completion', () async {
      final probe = ReachabilityProbe(
        sites: sites,
        prober: (host, port, timeout) async {
          // C resolves fastest, A slowest, to stress ordering.
          switch (host) {
            case 'a.example':
              return const Duration(milliseconds: 30);
            case 'b.example':
              return const Duration(milliseconds: 20);
            default:
              return const Duration(milliseconds: 5);
          }
        },
      );
      final results = await probe.measure();
      expect(results.map((r) => r.site.name).toList(), <String>['A', 'B', 'C']);
    });

    test('reachable flag and latency reflect prober result', () async {
      final probe = ReachabilityProbe(
        sites: sites,
        prober: (host, port, timeout) async {
          if (host == 'b.example') return null; // unreachable
          return const Duration(milliseconds: 12);
        },
      );
      final results = await probe.measure();

      expect(results[0].reachable, isTrue);
      expect(results[0].latencyMs, closeTo(12, 0.001));

      expect(results[1].reachable, isFalse);
      expect(results[1].latencyMs, isNull);

      expect(results[2].reachable, isTrue);
      expect(results[2].latencyMs, closeTo(12, 0.001));
    });

    test('probes every site exactly once', () async {
      final probed = <String>[];
      final probe = ReachabilityProbe(
        sites: sites,
        prober: (host, port, timeout) async {
          probed.add(host);
          return const Duration(milliseconds: 1);
        },
      );
      await probe.measure();
      expect(probed.toSet(), <String>{'a.example', 'b.example', 'c.example'});
      expect(probed.length, 3);
    });

    test('default site list is non-empty', () {
      expect(kPopularSites.length, greaterThanOrEqualTo(10));
    });
  });
}
