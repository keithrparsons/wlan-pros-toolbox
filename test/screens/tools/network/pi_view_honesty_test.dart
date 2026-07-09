// Regression guards for the three WLAN-Pi-hosted view-honesty decisions.
//
// Each decision only fires under `kIsWeb` (a const `false` on the Dart VM), so a
// plain widget test cannot force the Pi branch. Extracting the decisions into
// pure functions (lib/screens/tools/network/pi_view_honesty.dart) lets us pin
// BOTH branches here with no web harness — guarding the screenshot-must-match-
// prose invariant (GL-005) and the front-door copy fix (Vera MEDIUM-1 + -2,
// 2026-07-09).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/pi_view_honesty.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

void main() {
  group('showInterfaceConceptGraphic', () {
    test('native (not Pi-backed) shows the local-device graphic', () {
      // The graphic depicts a specific local device; on native that is truthful.
      expect(showInterfaceConceptGraphic(false), isTrue);
    });

    test('Pi-hosted omits the graphic so the picture cannot contradict prose',
        () {
      // The Pi prose says a browser cannot read this device's interface table;
      // the local-device illustration would contradict it, so it is omitted.
      expect(showInterfaceConceptGraphic(true), isFalse);
    });
  });

  group('netQualityBlurb', () {
    test('native blurb is unchanged, byte-for-byte', () {
      expect(
        netQualityBlurb(false),
        'Measures latency, jitter, loss, download, upload, and '
        'responsiveness over a TCP-connect probe and HTTPS '
        'transfers, then checks whether your device can reach a set '
        'of popular cloud apps right now. Each dimension is graded '
        'on its own; there is no single score.',
      );
    });

    test('Pi blurb reports the two throughput numbers and only excludes RF',
        () {
      final String pi = netQualityBlurb(true);
      // Attributes to the Pi, not "your device".
      expect(pi, contains('WLAN Pi hosting'));
      expect(pi, isNot(contains('your device')));
      // Throughput IS measured now (endpoint 11 + local-hop loop): the blurb
      // names the two distinct throughput numbers rather than calling
      // throughput unavailable.
      expect(pi, contains('two throughput numbers'));
      expect(pi, contains('Pi uplink to the internet'));
      expect(pi, contains('local hop between this device and the Pi'));
      // The one thing the Pi genuinely cannot see is the client's own RF.
      expect(pi, contains('Your own Wi-Fi RF is not visible to the Pi'));
      // The Pi sensor's real latency/loss/DNS measurements are still named.
      expect(pi, contains('packet loss'));
      expect(pi, contains('DNS resolution time'));
    });

    test('the two branches are different strings', () {
      expect(netQualityBlurb(true), isNot(netQualityBlurb(false)));
    });
  });

  group('piConntestCopyText', () {
    PiConntestResult result({
      required PiHop gateway,
      required PiHop internet,
      required PiDns dns,
    }) =>
        PiConntestResult(internet: internet, gateway: gateway, dns: dns);

    test('a good run serializes header + one TSV row per hop', () {
      final String copy = piConntestCopyText(
        result(
          gateway: const PiHop(
            target: '192.168.1.1',
            reachable: true,
            avgMs: 2.4,
          ),
          internet: const PiHop(
            target: '1.1.1.1',
            reachable: true,
            avgMs: 18.7,
            lossPct: 0,
          ),
          dns: const PiDns(host: 'cloudflare.com', ms: 12.3),
        ),
      );

      expect(
        copy,
        // The final row's empty trailing Loss cell (a dangling tab) is trimmed
        // by the shared .trimRight(), matching the sibling Pi copy builders.
        'Connection test — measured on the WLAN Pi hosting this page\n'
        'Hop\tReachability\tLatency\tLoss\n'
        'Gateway (192.168.1.1)\treachable\t2 ms\t\n'
        'Internet (1.1.1.1)\treachable\t19 ms\t0%\n'
        'DNS resolve (cloudflare.com)\treachable\t12 ms',
      );
    });

    test('an unreachable hop copies its honest word and an em-dash latency', () {
      final String copy = piConntestCopyText(
        result(
          gateway: const PiHop(target: '192.168.1.1', reachable: true, avgMs: 3),
          internet: const PiHop(
            target: '1.1.1.1',
            reachable: false,
            lossPct: 100,
          ),
          dns: const PiDns(host: 'cloudflare.com', ms: null),
        ),
      );

      // Unreachable internet: no fabricated latency, honest loss.
      expect(copy, contains('Internet (1.1.1.1)\tunreachable\t—\t100%'));
      // DNS with no resolve time reads unreachable, latency em-dash, no loss.
      // (DNS is the last row, so its empty trailing Loss cell is trimmed.)
      expect(copy, endsWith('DNS resolve (cloudflare.com)\tunreachable\t—'));
    });

    test('a hop with no target id falls back to the bare label', () {
      final String copy = piConntestCopyText(
        result(
          gateway: const PiHop(target: null, reachable: true, avgMs: 1),
          internet: const PiHop(target: '', reachable: true, avgMs: 1),
          dns: const PiDns(host: null, ms: 1),
        ),
      );
      expect(copy, contains('Gateway\treachable'));
      expect(copy, contains('Internet\treachable'));
      expect(copy, contains('DNS resolve\treachable'));
    });

    test('the payload is attributed to the Pi and never blank for a result', () {
      final String copy = piConntestCopyText(
        result(
          gateway: const PiHop(target: 'g', reachable: true, avgMs: 1),
          internet: const PiHop(target: 'i', reachable: true, avgMs: 1),
          dns: const PiDns(host: 'd', ms: 1),
        ),
      );
      // The MEDIUM-1 guard: a present result always yields copyable text (the
      // old front door produced null here, leaving the copy button dead-greyed).
      expect(copy, isNotEmpty);
      expect(copy, startsWith('Connection test — measured on the WLAN Pi'));
    });

    // Change 1 (2026-07-09): Test My Connection's Pi path now measures the two
    // throughput numbers Network Quality shows, so the copy carries them too.
    group('with throughput evidence', () {
      PiConntestResult goodCt() => result(
            gateway: const PiHop(target: '192.168.1.1', reachable: true, avgMs: 2),
            internet:
                const PiHop(target: '1.1.1.1', reachable: true, avgMs: 18, lossPct: 0),
            dns: const PiDns(host: 'cloudflare.com', ms: 12),
          );

      test('appends both labeled throughput sections when present', () {
        final String copy = piConntestCopyText(
          goodCt(),
          throughput: const PiThroughputResult(
            downloadMbps: 712.3,
            uploadMbps: 462.8,
          ),
          deviceToPiDownMbps: 240.5,
          deviceToPiUpMbps: 180.2,
        );
        // The hop TSV is preserved (nothing stripped — "DO NOT re-simplify").
        expect(copy, contains('Internet (1.1.1.1)\treachable\t18 ms\t0%'));
        // Pi uplink section — the Pi's own uplink, clearly labeled.
        expect(copy, contains('Pi to internet (throughput)'));
        expect(copy, contains('Download: 712.3 Mbps'));
        expect(copy, contains('Upload: 462.8 Mbps'));
        // Local Wi-Fi hop section — the second, distinct number, never conflated.
        expect(copy, contains('This device to Pi (Wi-Fi hop)'));
        expect(copy, contains('Download: 240.5 Mbps'));
        expect(copy, contains('Upload: 180.2 Mbps'));
      });

      test('a failed Pi uplink leg copies Unavailable, never a fabricated 0', () {
        final String copy = piConntestCopyText(
          goodCt(),
          throughput: const PiThroughputResult(
            downloadMbps: null,
            uploadMbps: 80.2,
            downloadError: 'download failed',
          ),
        );
        expect(copy, contains('Pi to internet (throughput)'));
        expect(copy, contains('Download: Unavailable'));
        expect(copy, contains('Upload: 80.2 Mbps'));
        expect(copy, isNot(contains('Download: 0')));
      });

      test('a local-hop error copies the honest message, not numbers', () {
        final String copy = piConntestCopyText(
          goodCt(),
          deviceToPiError:
              'The local Wi-Fi-hop test to the Pi could not complete.',
        );
        expect(copy, contains('This device to Pi (Wi-Fi hop)'));
        expect(
          copy,
          contains('The local Wi-Fi-hop test to the Pi could not complete.'),
        );
        expect(copy, isNot(contains('Wi-Fi hop)\n  Download')));
      });

      test('no throughput evidence keeps the original hop-only payload', () {
        final String bare = piConntestCopyText(goodCt());
        expect(bare, isNot(contains('throughput')));
        expect(bare, isNot(contains('Wi-Fi hop')));
        // Ends on the DNS row exactly as before the throughput additions.
        expect(bare, endsWith('DNS resolve (cloudflare.com)\treachable\t12 ms'));
      });
    });
  });
}
