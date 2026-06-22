// NtpService unit tests.
//
// The heart of this is parseReply — a PURE function over the 48 reply bytes
// plus the client transmit (t1) and receive (t4) instants. We craft a 48-byte
// SNTP reply with a known stratum and known server receive/transmit timestamps,
// then assert the exact RFC 4330 offset/delay the formula must produce. No real
// network is touched.
//
// We also drive NtpService.query through an injected SntpExchange seam to assert
// the honest failure paths (short reply, stratum-0 kiss-o'-death, blank input)
// and the success wiring — again with no socket.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ntp_service.dart';

/// Seconds from the NTP epoch (1900) to the Unix epoch (1970).
const int _ntpToUnix = 2208988800;

/// Write a 64-bit NTP timestamp for [unixMicros] into [packet] at [offset]
/// (big-endian 32.32 fixed-point seconds since 1900). Mirrors the encoding
/// parseReply decodes, so a round-trip is exact at ms resolution.
void _writeNtpTimestamp(Uint8List packet, int offset, int unixMicros) {
  final int unixSeconds = unixMicros ~/ 1000000;
  final int micros = unixMicros % 1000000;
  final int ntpSeconds = unixSeconds + _ntpToUnix;
  // Fraction is units of 1/2^32 second.
  final int fraction = ((micros << 32) ~/ 1000000) & 0xFFFFFFFF;

  for (int i = 0; i < 4; i++) {
    packet[offset + i] = (ntpSeconds >> (8 * (3 - i))) & 0xFF;
  }
  for (int i = 0; i < 4; i++) {
    packet[offset + 4 + i] = (fraction >> (8 * (3 - i))) & 0xFF;
  }
}

/// Build a 48-byte SNTP reply with [stratum] and server receive (t2) / transmit
/// (t3) timestamps expressed as Unix microseconds.
Uint8List _craftReply({
  required int stratum,
  required int t2Micros,
  required int t3Micros,
}) {
  final Uint8List p = Uint8List(48);
  p[0] = 0x1C; // LI 0, VN 3, Mode 4 (server) — value not read by parseReply.
  p[1] = stratum;
  _writeNtpTimestamp(p, 32, t2Micros); // receive timestamp (t2)
  _writeNtpTimestamp(p, 40, t3Micros); // transmit timestamp (t3)
  return p;
}

void main() {
  group('buildRequest', () {
    test('is 48 bytes with the 0x1B client header and zero elsewhere', () {
      final Uint8List req = NtpService.buildRequest();
      expect(req.length, 48);
      expect(req[0], 0x1B); // LI=0, VN=3, Mode=3 (client).
      for (int i = 1; i < 48; i++) {
        expect(req[i], 0, reason: 'byte $i should be zero');
      }
    });
  });

  group('parseReply (pure formula)', () {
    test('computes the RFC 4330 offset and delay from a crafted packet', () {
      // Client send t1 = 1000 ms, receive t4 = 1050 ms (epoch-relative).
      // Server receive t2 = 1020 ms, transmit t3 = 1024 ms.
      //   offset = ((t2 - t1) + (t3 - t4)) / 2 = ((20) + (-26)) / 2 = -3 ms
      //   delay  = (t4 - t1) - (t3 - t2)       = 50 - 4          = 46 ms
      final DateTime t1 = DateTime.fromMicrosecondsSinceEpoch(1000 * 1000,
          isUtc: true);
      final DateTime t4 = DateTime.fromMicrosecondsSinceEpoch(1050 * 1000,
          isUtc: true);
      final Uint8List reply = _craftReply(
        stratum: 2,
        t2Micros: 1020 * 1000,
        t3Micros: 1024 * 1000,
      );

      final NtpReading r = NtpService.parseReply(reply, t1, t4);

      expect(r.stratum, 2);
      expect(r.offsetMs, -3);
      expect(r.delayMs, 46);
      // serverUtc is t3 (1024 ms). The test's own fixed-point encoder loses up
      // to 1 us in the fraction round-trip, so assert at ms resolution — the ms
      // outputs (offset/delay) are exact, which is what the tool reports.
      expect(
        (r.serverUtc.microsecondsSinceEpoch - 1024 * 1000).abs(),
        lessThanOrEqualTo(1),
      );
      expect(r.serverUtc.isUtc, isTrue);
      // deviceTime is t4.
      expect(r.deviceTime.microsecondsSinceEpoch, 1050 * 1000);
    });

    test('a positive offset means the device clock is behind the server', () {
      // Symmetric path (t1=0, t4=20 ms) with the server 100 ms AHEAD of the
      // device midpoint → device is behind → positive offset.
      //   t2 = 110, t3 = 111 → offset = ((110-0)+(111-20))/2 = (110+91)/2
      //   = 100.5 → 100 (round). delay = (20-0)-(111-110) = 19 ms.
      final DateTime t1 =
          DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      final DateTime t4 = DateTime.fromMicrosecondsSinceEpoch(20 * 1000,
          isUtc: true);
      final Uint8List reply = _craftReply(
        stratum: 1,
        t2Micros: 110 * 1000,
        t3Micros: 111 * 1000,
      );

      final NtpReading r = NtpService.parseReply(reply, t1, t4);
      expect(r.offsetMs.isNegative, isFalse);
      expect(r.offsetMs, 100);
      expect(r.delayMs, 19);
    });

    test('clamps a jitter-induced negative delay to zero', () {
      // Construct t3-t2 larger than t4-t1 so the raw delay is negative.
      //   t1=0, t4=5 ms; t2=10, t3=30 → delay = 5 - 20 = -15 → clamped to 0.
      final DateTime t1 =
          DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      final DateTime t4 = DateTime.fromMicrosecondsSinceEpoch(5 * 1000,
          isUtc: true);
      final Uint8List reply = _craftReply(
        stratum: 2,
        t2Micros: 10 * 1000,
        t3Micros: 30 * 1000,
      );

      final NtpReading r = NtpService.parseReply(reply, t1, t4);
      expect(r.delayMs, 0);
    });

    test('throws on a short reply', () {
      expect(
        () => NtpService.parseReply(
          Uint8List(40),
          DateTime.now().toUtc(),
          DateTime.now().toUtc(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('query (via injected exchange)', () {
    NtpService serviceReturning(Uint8List reply,
        {int t1Ms = 1000, int t4Ms = 1050, String? ip = '17.253.4.125'}) {
      return NtpService(
        exchange: (host, port, timeout) async => SntpExchangeResult(
          reply: reply,
          t1: DateTime.fromMicrosecondsSinceEpoch(t1Ms * 1000, isUtc: true),
          t4: DateTime.fromMicrosecondsSinceEpoch(t4Ms * 1000, isUtc: true),
          resolvedIp: ip,
        ),
      );
    }

    test('blank server input fails honestly without an exchange', () async {
      bool called = false;
      final NtpService svc = NtpService(
        exchange: (host, port, timeout) async {
          called = true;
          return SntpExchangeResult(reply: const <int>[], t1: _epoch, t4: _epoch);
        },
      );
      final NtpResult res = await svc.query(server: '   ');
      expect(res.isError, isTrue);
      expect(called, isFalse);
      expect(res.errorMessage, contains('Enter an NTP server'));
    });

    test('a successful exchange yields a reading with the resolved IP',
        () async {
      final Uint8List reply = _craftReply(
        stratum: 1,
        t2Micros: 1020 * 1000,
        t3Micros: 1024 * 1000,
      );
      final NtpResult res = await serviceReturning(reply).query();
      expect(res.isError, isFalse);
      expect(res.resolvedIp, '17.253.4.125');
      expect(res.reading, isNotNull);
      expect(res.reading!.offsetMs, -3);
      expect(res.reading!.delayMs, 46);
    });

    test('a reply shorter than 48 bytes is an honest failure', () async {
      final NtpResult res =
          await serviceReturning(Uint8List(20)).query();
      expect(res.isError, isTrue);
      expect(res.errorMessage, contains('48 bytes'));
      expect(res.reading, isNull);
    });

    test('a stratum-0 (kiss-o\'-death) reply is rejected, not trusted',
        () async {
      final Uint8List reply = _craftReply(
        stratum: 0,
        t2Micros: 1020 * 1000,
        t3Micros: 1024 * 1000,
      );
      final NtpResult res = await serviceReturning(reply).query();
      expect(res.isError, isTrue);
      expect(res.errorMessage, contains('stratum 0'));
      expect(res.reading, isNull);
    });
  });
}

/// Epoch helper for the no-exchange path (the exchange is never called there).
final DateTime _epoch =
    DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
