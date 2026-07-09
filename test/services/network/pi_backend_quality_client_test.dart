// PiBackendQualityClient coverage — the conntest -> QualityResult mapping the
// Network Quality (and Test My Connection) Pi path renders.
//
// A MockClient stands in for the browser fetch so no Pi is needed; it answers
// both same-origin endpoints the client hits per run (`/toolboxapi/conntest`
// and `/toolboxapi/throughput`). The load-bearing check here is the JITTER wire
// (2026-07-09): the Pi now emits `internet.jitter_ms`, and the client must feed
// it as a real, graded Jitter metric instead of the old permanent "Unavailable".
// Honest-null is preserved: a null jitter stays a first-class unavailable metric,
// never faked (GL-005).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_quality_client.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

/// A MockClient that returns [conntest] on the conntest route and [throughput]
/// on the throughput route (best-effort — a null throughput 500s so the client's
/// try/catch leaves the uplink honest-null without failing the whole run).
PiBackendQualityClient _quality({
  required Map<String, dynamic> conntest,
  Map<String, dynamic>? throughput,
}) {
  final MockClient mock = MockClient((http.Request req) async {
    if (req.url.path == '/toolboxapi/conntest') return _json(conntest);
    if (req.url.path == '/toolboxapi/throughput') {
      return throughput == null
          ? _json(<String, dynamic>{'error': 'no throughput'}, status: 500)
          : _json(throughput);
    }
    return _json(<String, dynamic>{'error': 'unexpected route'}, status: 404);
  });
  return PiBackendQualityClient(
    client: PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/')),
  );
}

Future<QualityResult> _run(PiBackendQualityClient q) async {
  await q.measure().drain<void>();
  return q.lastResult!;
}

void main() {
  group('PiBackendQualityClient jitter', () {
    test('feeds internet.jitter_ms as a real, graded Jitter metric', () async {
      final PiBackendQualityClient q = _quality(
        conntest: <String, dynamic>{
          'internet': <String, dynamic>{
            'target': '1.1.1.1',
            'reachable': true,
            'avg_ms': 18.7,
            'loss_pct': 0,
            'jitter_ms': 2.4, // < 5 ms -> excellent band
          },
          'gateway': <String, dynamic>{
            'ip': '192.168.1.1',
            'reachable': true,
            'avg_ms': 2.1,
          },
          'dns': <String, dynamic>{'host': 'cloudflare.com', 'ms': 12.3},
        },
      );

      final QualityResult r = await _run(q);
      final QualityMetric? jitter = r.metric(MetricIds.jitter);
      expect(jitter, isNotNull);
      // The bug this guards: the Jitter row was permanently "Unavailable" even
      // when the Pi supplied a value.
      expect(jitter!.isAvailable, isTrue);
      expect(jitter.value, closeTo(2.4, 1e-9));
      expect(jitter.grade, QualityGrade.excellent);
    });

    test('grades a higher jitter into the right band', () async {
      final PiBackendQualityClient q = _quality(
        conntest: <String, dynamic>{
          'internet': <String, dynamic>{
            'target': '1.1.1.1',
            'reachable': true,
            'avg_ms': 40,
            'jitter_ms': 22, // 15..30 ms -> fair band
          },
          'gateway': <String, dynamic>{'ip': '10.0.0.1', 'reachable': true},
          'dns': <String, dynamic>{'host': 'd', 'ms': 9},
        },
      );
      final QualityMetric? jitter = (await _run(q)).metric(MetricIds.jitter);
      expect(jitter!.value, closeTo(22, 1e-9));
      expect(jitter.grade, QualityGrade.fair);
    });

    test('a null jitter stays honest-unavailable, never faked', () async {
      final PiBackendQualityClient q = _quality(
        conntest: <String, dynamic>{
          'internet': <String, dynamic>{
            'target': '1.1.1.1',
            'reachable': true,
            'avg_ms': 18.7,
            'jitter_ms': null, // Pi could not compute one
          },
          'gateway': <String, dynamic>{'ip': '192.168.1.1', 'reachable': true},
          'dns': <String, dynamic>{'host': 'd', 'ms': 9},
        },
      );
      final QualityMetric? jitter = (await _run(q)).metric(MetricIds.jitter);
      expect(jitter, isNotNull);
      expect(jitter!.isAvailable, isFalse);
      expect(jitter.value, isNull);
      expect(jitter.grade, QualityGrade.unavailable);
      expect(jitter.note, isNotNull);
    });

    test('a jitter_ms absent from the payload is unavailable (not zero)', () async {
      final PiBackendQualityClient q = _quality(
        conntest: <String, dynamic>{
          'internet': <String, dynamic>{
            'target': '1.1.1.1',
            'reachable': true,
            'avg_ms': 18.7,
          },
          'gateway': <String, dynamic>{'ip': '192.168.1.1', 'reachable': true},
          'dns': <String, dynamic>{'host': 'd', 'ms': 9},
        },
      );
      final QualityMetric? jitter = (await _run(q)).metric(MetricIds.jitter);
      expect(jitter!.isAvailable, isFalse);
      expect(jitter.value, isNull);
    });

    test('responsiveness stays honest-unavailable (unchanged by the jitter fix)',
        () async {
      final PiBackendQualityClient q = _quality(
        conntest: <String, dynamic>{
          'internet': <String, dynamic>{
            'target': '1.1.1.1',
            'reachable': true,
            'avg_ms': 18.7,
            'jitter_ms': 3,
          },
          'gateway': <String, dynamic>{'ip': '192.168.1.1', 'reachable': true},
          'dns': <String, dynamic>{'host': 'd', 'ms': 9},
        },
      );
      final QualityMetric? rpm =
          (await _run(q)).metric(MetricIds.responsiveness);
      expect(rpm!.isAvailable, isFalse);
    });
  });

  group('PiConntestResult jitter parse', () {
    test('parses internet.jitter_ms onto the internet hop', () {
      final PiConntestResult ct = PiConntestResult.fromJson(<String, dynamic>{
        'internet': <String, dynamic>{
          'target': '1.1.1.1',
          'reachable': true,
          'avg_ms': 18.7,
          'jitter_ms': 2.4,
        },
        'gateway': <String, dynamic>{'ip': '192.168.1.1', 'reachable': true},
        'dns': <String, dynamic>{'host': 'cloudflare.com', 'ms': 12.3},
      });
      expect(ct.internet.jitterMs, closeTo(2.4, 1e-9));
      // The gateway hop carries no jitter — honest-null, never zero-filled.
      expect(ct.gateway.jitterMs, isNull);
    });
  });
}
