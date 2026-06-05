// Unit tests for the NON-STUBBED parts of WlanPiSession: the pure helpers that
// do not need a device — HMAC canonical-string construction, OpenAPI version
// parsing + support gate, Retry-After parsing, backoff caps, and masked-token
// safety. The STUBBED parts (live auth handshake, live reads, live profiler)
// are deliberately NOT tested here — they throw WlanPiNotYetWired until Monday's
// on-device spike, and we assert exactly that contract instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/wlanpi/wlanpi_connection_state.dart';
import 'package:wlan_pros_toolbox/services/wlanpi/wlanpi_session.dart';

void main() {
  group('canonicalRequestString (matches wlanpi-core core/auth.py)', () {
    test('METHOD\\nPATH\\nQUERY\\nBODY with empty query/body', () {
      final WlanPiHttpRequest req = WlanPiHttpRequest(
        method: 'get',
        url: Uri.parse('http://wlanpi.local:31415/api/v1/system/device/info'),
      );
      expect(
        WlanPiSession.canonicalRequestString(req),
        'GET\n/api/v1/system/device/info\n\n',
      );
    });

    test('includes query string and body when present', () {
      final WlanPiHttpRequest req = WlanPiHttpRequest(
        method: 'post',
        url: Uri.parse('http://wlanpi.local:31415/api/v1/profiler/start?chan=36'),
        body: '{"device_id":"abc"}',
      );
      expect(
        WlanPiSession.canonicalRequestString(req),
        'POST\n/api/v1/profiler/start\nchan=36\n{"device_id":"abc"}',
      );
    });

    test('method is upper-cased', () {
      final WlanPiHttpRequest req = WlanPiHttpRequest(
        method: 'delete',
        url: Uri.parse('http://h/api/v1/auth/token'),
      );
      expect(
        WlanPiSession.canonicalRequestString(req).startsWith('DELETE\n'),
        isTrue,
      );
    });
  });

  group('computeHmacSignature (stub marker until crypto dep is wired)', () {
    test('returns a clearly-labeled STUB marker, never a real-looking digest', () {
      final WlanPiHttpRequest req = WlanPiHttpRequest(
        method: 'GET',
        url: Uri.parse('http://h/api/v1/system/device/info'),
      );
      final String sig = WlanPiSession.computeHmacSignature(req, 'secret');
      expect(sig.startsWith('STUB-HMAC-SHA256('), isTrue);
    });

    test('is deterministic for the same request + secret', () {
      final WlanPiHttpRequest req = WlanPiHttpRequest(
        method: 'GET',
        url: Uri.parse('http://h/api/v1/system/device/info'),
      );
      expect(
        WlanPiSession.computeHmacSignature(req, 's'),
        WlanPiSession.computeHmacSignature(req, 's'),
      );
    });
  });

  group('parseOpenApiVersion + isVersionSupported (version gate §2.5)', () {
    test('reads major from info.version "3.2.2"', () {
      expect(
        WlanPiSession.parseOpenApiVersion(<String, dynamic>{
          'info': <String, dynamic>{'version': '3.2.2'},
        }),
        3,
      );
    });

    test('null when no info block', () {
      expect(
        WlanPiSession.parseOpenApiVersion(<String, dynamic>{}),
        isNull,
      );
    });

    test('null when version has no digits', () {
      expect(
        WlanPiSession.parseOpenApiVersion(<String, dynamic>{
          'info': <String, dynamic>{'version': 'unknown'},
        }),
        isNull,
      );
    });

    test('3.x supported, 2.x (NEO2) not supported, null not supported', () {
      expect(WlanPiSession.isVersionSupported(3), isTrue);
      expect(WlanPiSession.isVersionSupported(4), isTrue);
      expect(WlanPiSession.isVersionSupported(2), isFalse);
      expect(WlanPiSession.isVersionSupported(null), isFalse);
    });
  });

  group('parseRetryAfter (429 backoff §2.3)', () {
    test('delta-seconds form', () {
      expect(
        WlanPiSession.parseRetryAfter(<String, String>{'Retry-After': '5'}),
        const Duration(seconds: 5),
      );
    });

    test('case-insensitive header name', () {
      expect(
        WlanPiSession.parseRetryAfter(<String, String>{'retry-after': '10'}),
        const Duration(seconds: 10),
      );
    });

    test('absent header → null', () {
      expect(
        WlanPiSession.parseRetryAfter(<String, String>{}),
        isNull,
      );
    });

    test('clamps absurd values to one hour', () {
      expect(
        WlanPiSession.parseRetryAfter(<String, String>{'Retry-After': '99999'}),
        const Duration(seconds: 3600),
      );
    });

    test('HTTP-date in the past → zero', () {
      expect(
        WlanPiSession.parseRetryAfter(<String, String>{
          'Retry-After': '2000-01-01T00:00:00Z',
        }),
        Duration.zero,
      );
    });
  });

  group('backoffForAttempt (capped exponential)', () {
    test('grows exponentially from the base', () {
      expect(WlanPiSession.backoffForAttempt(0).inMilliseconds, 400);
      expect(WlanPiSession.backoffForAttempt(1).inMilliseconds, 800);
      expect(WlanPiSession.backoffForAttempt(2).inMilliseconds, 1600);
    });

    test('caps at 30s for large attempts', () {
      expect(
        WlanPiSession.backoffForAttempt(20).inMilliseconds,
        lessThanOrEqualTo(30000),
      );
    });
  });

  group('STUBBED contract — honest failure pending Monday', () {
    final WlanPiCandidate candidate =
        const WlanPiCandidate(host: '192.168.1.42', port: 31415);

    test('authenticate throws WlanPiNotYetWired (bootstrap credential unknown)', () {
      final WlanPiSession s = WlanPiSession(candidate: candidate);
      expect(
        () => s.authenticate(deviceId: 'test-client'),
        throwsA(isA<WlanPiNotYetWired>()),
      );
    });

    test('reads throw WlanPiNotYetWired before a token exists', () {
      final WlanPiSession s = WlanPiSession(candidate: candidate);
      expect(() => s.readDeviceInfo(), throwsA(isA<WlanPiNotYetWired>()));
      expect(() => s.readNetworkInfo(), throwsA(isA<WlanPiNotYetWired>()));
      expect(() => s.pollProfilerStatus(), throwsA(isA<WlanPiNotYetWired>()));
    });

    test('maskedTokenState never exposes a token', () {
      final WlanPiSession s = WlanPiSession(candidate: candidate);
      expect(s.isAuthenticated, isFalse);
      expect(s.maskedTokenState, '<no token>');
    });
  });

  group('WlanPiCandidate URL construction (version base path carried once)', () {
    test('apiBaseUrl carries /api/v1 and port 31415', () {
      const WlanPiCandidate c = WlanPiCandidate(host: '10.0.0.5', port: 31415);
      expect(c.apiBaseUrl, 'http://10.0.0.5:31415/api/v1');
      expect(c.openApiUrl, 'http://10.0.0.5:31415/openapi.json');
    });

    test('label prefers hostname when present', () {
      const WlanPiCandidate c = WlanPiCandidate(
        host: '10.0.0.5',
        port: 31415,
        hostname: 'wlanpi-cda.local',
      );
      expect(c.label, 'wlanpi-cda.local');
    });
  });
}
