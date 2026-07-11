// Unit tests for the shared TCP probe classifier — the SSOT for "did this host
// answer?". Every probe in the app routes its liveness decision through here, so
// this is the one place the errno tables and the message fallbacks are pinned.
//
// The load-bearing case is errno 110: Dart's OWN connect-timeout stamps it, on
// every platform. It must classify DEAD. Reading it as "the host answered" is
// the bug that made a /24 sweep report 254/254 live.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/tcp_probe_classifier.dart';

SocketException _ex(String message, [String? osMessage, int? errno]) =>
    SocketException(
      message,
      osError: errno == null ? null : OSError(osMessage ?? message, errno),
    );

void main() {
  group('refused → ALIVE (a RST proves the host answered the SYN)', () {
    final Map<String, SocketException> cases = <String, SocketException>{
      'ECONNREFUSED BSD (61)': _ex('Connection refused', 'Connection refused', 61),
      'ECONNRESET BSD (54)':
          _ex('Connection reset by peer', 'Connection reset by peer', 54),
      'ECONNREFUSED Linux (111)':
          _ex('Connection refused', 'Connection refused', 111),
      'ECONNRESET Linux (104)':
          _ex('Connection reset by peer', 'Connection reset by peer', 104),
      'WSAECONNREFUSED Windows (10061)': _ex(
          'No connection could be made because the target machine actively '
          'refused it',
          'actively refused it',
          10061),
      'WSAECONNRESET Windows (10054)': _ex('Connection reset by peer',
          'An existing connection was forcibly closed by the remote host', 10054),
    };

    cases.forEach((String label, SocketException e) {
      test('$label → refused / alive', () {
        final TcpProbeFailure f = classifyTcpFailure(e);
        expect(f.reason, TcpFailureReason.refused, reason: label);
        expect(f.outcome, TcpProbeOutcome.refused, reason: label);
        expect(f.hostAnswered, isTrue, reason: label);
        expect(tcpErrorProvesHostAlive(e), isTrue, reason: label);
      });
    });

    test('a refusal with NO errno is still read from the message', () {
      // Belt and braces for platforms/locales that do not surface an errno.
      final TcpProbeFailure f = classifyTcpFailure(_ex('Connection refused'));
      expect(f.reason, TcpFailureReason.refused);
      expect(f.errorCode, isNull);
    });
  });

  group('timeout → DEAD (this is the bug)', () {
    test("Dart's synthetic connect-timeout errno 110 is DEAD, not alive", () {
      // THE regression. Measured on macOS: Socket.connect(timeout: 600ms)
      // against a dead host throws SocketException('Connection timed out',
      // osError: OSError('Connection timed out', 110)) after ~607ms. osError is
      // NOT null. Treating that as "the host answered" is what produced 254/254.
      final SocketException e =
          _ex('Connection timed out', 'Connection timed out', 110);

      expect(e.osError, isNotNull,
          reason: 'the premise of the bug: a dead host DOES carry an osError');

      final TcpProbeFailure f = classifyTcpFailure(e);
      expect(f.reason, TcpFailureReason.timedOut);
      expect(f.outcome, TcpProbeOutcome.dead);
      expect(f.hostAnswered, isFalse);
      expect(f.errorCode, 110);
    });

    test('ETIMEDOUT BSD (60) and WSAETIMEDOUT (10060) are DEAD', () {
      for (final int errno in <int>[60, 10060]) {
        final TcpProbeFailure f =
            classifyTcpFailure(_ex('Operation timed out', 'timed out', errno));
        expect(f.reason, TcpFailureReason.timedOut, reason: 'errno $errno');
        expect(f.outcome, TcpProbeOutcome.dead, reason: 'errno $errno');
      }
    });

    test('a timeout with no errno is read from the message', () {
      final TcpProbeFailure f = classifyTcpFailure(_ex('Connection timed out'));
      expect(f.reason, TcpFailureReason.timedOut);
      expect(f.outcome, TcpProbeOutcome.dead);
    });
  });

  group('unreachable / host-down → DEAD', () {
    final Map<String, SocketException> cases = <String, SocketException>{
      'ENETUNREACH BSD (51)':
          _ex('Network is unreachable', 'Network is unreachable', 51),
      'EHOSTDOWN BSD (64)': _ex('Host is down', 'Host is down', 64),
      'EHOSTUNREACH BSD (65)': _ex('No route to host', 'No route to host', 65),
      'ENETUNREACH Linux (101)':
          _ex('Network is unreachable', 'Network is unreachable', 101),
      'EHOSTDOWN Linux (112)': _ex('Host is down', 'Host is down', 112),
      'EHOSTUNREACH Linux (113)':
          _ex('No route to host', 'No route to host', 113),
      'WSAEHOSTUNREACH Windows (10065)': _ex('No route to host',
          'A socket operation was attempted to an unreachable host', 10065),
    };

    cases.forEach((String label, SocketException e) {
      test('$label → unreachable / dead', () {
        final TcpProbeFailure f = classifyTcpFailure(e);
        expect(f.reason, TcpFailureReason.unreachable, reason: label);
        expect(f.outcome, TcpProbeOutcome.dead, reason: label);
        expect(f.hostAnswered, isFalse, reason: label);
      });
    });
  });

  group('lookup failure → DEAD (we never even sent a SYN)', () {
    test('failed host lookup', () {
      final TcpProbeFailure f =
          classifyTcpFailure(_ex('Failed host lookup: nowhere.invalid'));
      expect(f.reason, TcpFailureReason.lookupFailure);
      expect(f.outcome, TcpProbeOutcome.dead);
    });

    test('nodename nor servname provided (BSD wording)', () {
      final TcpProbeFailure f = classifyTcpFailure(
          _ex('Failed host lookup', 'nodename nor servname provided', 8));
      expect(f.reason, TcpFailureReason.lookupFailure);
      expect(f.outcome, TcpProbeOutcome.dead);
    });
  });

  group('the DEFAULT is dead — an unknown error never invents a host', () {
    test('an unrecognised SocketException is dead', () {
      final TcpProbeFailure f =
          classifyTcpFailure(_ex('Something we have never seen', 'weird', 9999));
      expect(f.reason, TcpFailureReason.unknown);
      expect(f.outcome, TcpProbeOutcome.dead);
      expect(f.hostAnswered, isFalse);
    });

    test('a non-SocketException (TimeoutException, StateError…) is dead', () {
      for (final Object e in <Object>[
        TimeoutException('deadline'),
        StateError('boom'),
        const HandshakeException('tls blew up'),
      ]) {
        expect(classifyTcpError(e), TcpProbeOutcome.dead,
            reason: e.runtimeType.toString());
        expect(tcpErrorProvesHostAlive(e), isFalse);
      }
    });
  });

  group('message-fallback ordering: a timeout is NEVER read as a refusal', () {
    test('a message naming BOTH a reset and a timeout classifies as timeout',
        () {
      // Precedence matters. If a message ever carries both words, "no answer"
      // must win — we do not get to promote a dead host to alive on a substring.
      final TcpProbeFailure f = classifyTcpFailure(
        _ex('Connection timed out; the connection was reset'),
      );
      expect(f.reason, TcpFailureReason.timedOut);
      expect(f.outcome, TcpProbeOutcome.dead);
    });

    test('"host is down" is not promoted by an incidental "reset"', () {
      final TcpProbeFailure f =
          classifyTcpFailure(_ex('Host is down, reset expected'));
      expect(f.outcome, TcpProbeOutcome.dead);
    });
  });

  group('message exposure — callers never need osError themselves', () {
    test('prefers the OS-level message when the platform gives one', () {
      final TcpProbeFailure f = classifyTcpFailure(
          _ex('SocketException wrapper', 'Connection refused', 61));
      expect(f.message, 'Connection refused');
      expect(f.errorCode, 61);
    });

    test('falls back to the exception message when there is no OS error', () {
      final TcpProbeFailure f = classifyTcpFailure(_ex('Connection refused'));
      expect(f.message, 'Connection refused');
      expect(f.errorCode, isNull);
    });
  });

  group('probeTcp — the one place a probe outcome is decided', () {
    test('a completed handshake is OPEN', () async {
      final TcpProbeOutcome outcome = await probeTcp(
        (String h, int p, Duration t) async => _FakeSocket(),
        '10.0.0.1',
        443,
        const Duration(milliseconds: 100),
      );
      expect(outcome, TcpProbeOutcome.open);
    });

    test('a refusal is REFUSED (alive)', () async {
      final TcpProbeOutcome outcome = await probeTcp(
        (String h, int p, Duration t) async =>
            throw _ex('Connection refused', 'Connection refused', 61),
        '10.0.0.1',
        443,
        const Duration(milliseconds: 100),
      );
      expect(outcome, TcpProbeOutcome.refused);
    });

    test('a connect-timeout is DEAD', () async {
      final TcpProbeOutcome outcome = await probeTcp(
        (String h, int p, Duration t) async =>
            throw _ex('Connection timed out', 'Connection timed out', 110),
        '10.0.0.1',
        443,
        const Duration(milliseconds: 100),
      );
      expect(outcome, TcpProbeOutcome.dead);
    });
  });

  group('errno tables are disjoint (no code can mean two things)', () {
    test('refused / timedOut / unreachable never overlap', () {
      expect(kRefusedErrno.intersection(kTimedOutErrno), isEmpty);
      expect(kRefusedErrno.intersection(kUnreachableErrno), isEmpty);
      expect(kTimedOutErrno.intersection(kUnreachableErrno), isEmpty);
    });

    test('110 is in the timeout table, and NOT in the refused table', () {
      // The single most important assertion in this file.
      expect(kTimedOutErrno.contains(110), isTrue);
      expect(kRefusedErrno.contains(110), isFalse);
    });
  });
}

/// Minimal Socket stand-in — probeTcp only ever calls destroy().
class _FakeSocket extends Fake implements Socket {
  @override
  void destroy() {}
}
