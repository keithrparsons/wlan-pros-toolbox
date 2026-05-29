// DartPingIcmpBackend mapping tests — verify the PURE translation from
// `dart_ping`'s PingData events to IcmpService's IcmpReply, using hand-built
// fixtures. NO live ICMP round-trip is performed (per GL-005/GL-008: the actual
// echo/TTL-walk against hardware is DEVICE-PENDING and is NOT what these tests
// cover). What IS verified here is the load-bearing mapping logic the device
// pass would otherwise be the only check on:
//   - a clean echo reply → success + rttMs + fromIp + ttl
//   - a TTL-exceeded router answer → success + fromIp + NO rttMs (the TTL-walk
//     hop-naming case, the whole reason mobile traceroute works on Android)
//   - requestTimedOut / noReply → lost probe ('timeout')
//   - unknownHost → 'unknownHost'
//   - unknown error → 'error'
//   - a summary-only event → null (no per-probe datum emitted)
//   - sequence fallback when the response carries no seq

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/dart_ping_icmp_backend.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';

void main() {
  group('DartPingIcmpBackend.parsePingData', () {
    test('clean echo reply → success with rtt, fromIp, ttl', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(
          response: PingResponse(
            seq: 3,
            ttl: 56,
            ip: '1.1.1.1',
            time: Duration(microseconds: 12345), // 12.345 ms
          ),
        ),
        99,
      );
      expect(reply, isNotNull);
      expect(reply!.success, isTrue);
      expect(reply.sequence, 3, reason: 'uses the response seq when present');
      expect(reply.fromIp, '1.1.1.1');
      expect(reply.ttl, 56);
      expect(reply.rttMs, closeTo(12.345, 0.0001));
      expect(reply.errorLabel, isNull);
    });

    test('falls back to the supplied seq when the response has none', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(
          response: PingResponse(ip: '8.8.8.8', time: Duration(milliseconds: 5)),
        ),
        7,
      );
      expect(reply!.sequence, 7);
      expect(reply.rttMs, closeTo(5, 0.0001));
    });

    test(
        'TTL-exceeded router answer → SUCCESS with fromIp and NO rtt '
        '(the TTL-walk hop-naming case)', () {
      // dart_ping's Linux/Android parser surfaces a TTL-expired hop as a
      // response carrying the router IP (no time) PLUS a timeToLiveExceeded
      // error. This must name the hop, not be dropped as a failure.
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(
          response: PingResponse(seq: 1, ip: '10.0.0.1'),
          error: PingError(ErrorType.timeToLiveExceeded),
        ),
        1,
      );
      expect(reply, isNotNull);
      expect(reply!.success, isTrue,
          reason: 'a named hop is a success for the TTL-walk');
      expect(reply.fromIp, '10.0.0.1');
      expect(reply.rttMs, isNull, reason: 'no RTT on a TTL-exceeded line');
    });

    test('requestTimedOut → lost probe labelled timeout', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(
          response: PingResponse(seq: 4),
          error: PingError(ErrorType.requestTimedOut),
        ),
        4,
      );
      expect(reply!.success, isFalse);
      expect(reply.errorLabel, 'timeout');
      expect(reply.sequence, 4);
    });

    test('noReply → lost probe labelled timeout', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(error: PingError(ErrorType.noReply)),
        2,
      );
      expect(reply!.success, isFalse);
      expect(reply.errorLabel, 'timeout');
      expect(reply.sequence, 2, reason: 'no response → falls back to seq');
    });

    test('unknownHost → labelled unknownHost', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(error: PingError(ErrorType.unknownHost)),
        1,
      );
      expect(reply!.success, isFalse);
      expect(reply.errorLabel, 'unknownHost');
    });

    test('any other error → generic error label', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        const PingData(error: PingError(ErrorType.unknown)),
        1,
      );
      expect(reply!.success, isFalse);
      expect(reply.errorLabel, 'error');
    });

    test('summary-only event → null (no per-probe datum)', () {
      final IcmpReply? reply = DartPingIcmpBackend.parsePingData(
        PingData(
          summary: PingSummary(transmitted: 10, received: 9),
        ),
        1,
      );
      expect(reply, isNull);
    });

    test('empty event → null', () {
      final IcmpReply? reply =
          DartPingIcmpBackend.parsePingData(const PingData(), 1);
      expect(reply, isNull);
    });
  });
}
