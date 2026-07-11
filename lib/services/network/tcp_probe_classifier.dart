// TcpProbeClassifier — the SINGLE source of truth for "did this host answer?"
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS FILE EXISTS (read before touching any TCP probe in this repo)
// ─────────────────────────────────────────────────────────────────────────────
//
// Five separate probes in this codebase each hand-rolled their own answer to
// "did the host respond?", and four of them got it wrong THE SAME WAY: they
// assumed a NULL `osError` means "our own connect-timeout fired" and therefore
// that a NON-null `osError` means "the host answered". That is FALSE.
//
// Measured on macOS with `Socket.connect(..., timeout: 600ms)` (2026-07-10):
//
//   Scenario                 | Exception            | errno | elapsed | osError?
//   -------------------------|----------------------|-------|---------|---------
//   Live host, closed port   | Connection refused   |  61   |   8 ms  | non-null
//   DEAD host                | Connection timed out |  110  | 607 ms  | non-null
//   DEAD host #2             | Connection timed out |  110  | 602 ms  | non-null
//
// Dart's OWN connect-timeout populates `osError` with a SYNTHETIC errno 110. So
// `osError != null` fires for timeouts, unreachable, and host-down right
// alongside genuine refusals. The consequence in the field: a /24 Ping Sweep
// reported "254 / 254 · 254 live" — every dead IP on the subnet counted as a
// live host.
//
// The errno is authoritative. Elapsed-time heuristics ("we ran the full
// timeout, so it must have been a timeout") are guesswork and are BANNED here.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE THREE HONEST OUTCOMES (never collapse them into two)
// ─────────────────────────────────────────────────────────────────────────────
//
//   open    — the TCP handshake completed. Host ALIVE, port LISTENING.
//   refused — the host answered our SYN with a RST (ECONNREFUSED), or reset an
//             established connection (ECONNRESET). Host ALIVE, port CLOSED.
//             This is deliberate and correct: a RST proves the host answered.
//             It is exactly how `tcping` behaves.
//   dead    — timeout, unreachable, host-down, name-lookup failure, or anything
//             we do not recognise. NOBODY answered. This is the DEFAULT.
//
// Defaulting to `dead` is the safety property: an unrecognised error can never
// invent a host. Any new failure shape lands in `dead` until someone proves it
// means "the host answered".
//
// ─────────────────────────────────────────────────────────────────────────────
// THE RULE (enforced mechanically)
// ─────────────────────────────────────────────────────────────────────────────
//
// NO OTHER FILE in lib/ or packages/ may reference `osError`. This file owns it.
// `test/services/network/os_error_liveness_guard_test.dart` fails the build if
// another file reaches for it. If you need the OS-level message for display,
// call [classifyTcpFailure] and read [TcpProbeFailure.message] — the classifier
// hands it to you already unwrapped.

import 'dart:io';

/// The three honest outcomes of a single TCP connect probe.
///
/// [open] and [refused] BOTH prove the host is alive. Only [refused] means the
/// port is closed. [dead] means nothing answered — it is the default for every
/// error shape this classifier does not positively recognise as a refusal.
enum TcpProbeOutcome {
  /// Handshake completed — host alive, port listening.
  open,

  /// RST / reset — host ALIVE, port closed. Counts as a round trip.
  refused,

  /// Timeout, unreachable, host-down, lookup failure, unknown — NO answer.
  dead,
}

/// Why a TCP connect failed. Finer-grained than [TcpProbeOutcome], for tools
/// that must distinguish *how* a probe failed (Ping's error label, Packet
/// Sender's typed error kinds, SSL Inspect's guidance copy).
///
/// Exactly one reason — [refused] — maps to a live host. Everything else is
/// [TcpProbeOutcome.dead].
enum TcpFailureReason {
  /// ECONNREFUSED / ECONNRESET — the host answered. ALIVE, port closed.
  refused,

  /// The connect deadline expired (ours or the stack's) — no answer.
  timedOut,

  /// EHOSTUNREACH / ENETUNREACH / EHOSTDOWN — no route, or the host is down.
  unreachable,

  /// DNS could not resolve the name — we never got as far as a SYN.
  lookupFailure,

  /// Anything else. Treated as dead: we will not invent a host from an error
  /// we do not understand.
  unknown,
}

/// A classified TCP connect failure: the reason, the best human-readable
/// message, and the platform errno when one was surfaced.
class TcpProbeFailure {
  const TcpProbeFailure({
    required this.reason,
    required this.message,
    this.errorCode,
  });

  /// Why the connect failed.
  final TcpFailureReason reason;

  /// The most specific message available — the OS-level message when the
  /// platform gave us one, otherwise the exception's own message. Callers use
  /// this for display copy so they never need to touch `osError` themselves.
  final String message;

  /// The platform errno, or null when the platform surfaced none. Diagnostics
  /// only — never re-classify from this in a caller; that is this file's job.
  final int? errorCode;

  /// The three-outcome verdict. A refusal is the ONLY failure that proves the
  /// host is alive; everything else is dead.
  TcpProbeOutcome get outcome => reason == TcpFailureReason.refused
      ? TcpProbeOutcome.refused
      : TcpProbeOutcome.dead;

  /// True when the failure itself proves the host answered (a RST).
  bool get hostAnswered => outcome == TcpProbeOutcome.refused;

  @override
  String toString() =>
      'TcpProbeFailure($reason, errno: $errorCode, "$message")';
}

/// errno values that prove the host ANSWERED — the only two errors that mean
/// "alive". They differ across the BSD family (macOS/iOS), Linux (Android), and
/// Winsock (Windows), so all three are matched. Every shipped platform, not
/// just the one the author happened to be sitting at.
///
///   ECONNREFUSED — our SYN was answered with a RST: host alive, port closed.
///   ECONNRESET   — an established connection was reset by the peer.
const Set<int> kRefusedErrno = <int>{
  61, // ECONNREFUSED    — macOS / iOS (BSD)
  54, // ECONNRESET      — macOS / iOS (BSD)
  111, // ECONNREFUSED   — Linux / Android
  104, // ECONNRESET     — Linux / Android
  10061, // WSAECONNREFUSED — Windows
  10054, // WSAECONNRESET   — Windows
};

/// errno values that mean the deadline expired with no answer.
///
/// 110 is the one that caused the bug: it is Linux's ETIMEDOUT AND the
/// synthetic code Dart stamps on its own `Socket.connect` timeout on EVERY
/// platform, macOS included. It is DEAD, not alive.
const Set<int> kTimedOutErrno = <int>{
  110, // ETIMEDOUT (Linux) + Dart's synthetic connect-timeout on all platforms
  60, // ETIMEDOUT      — macOS / iOS (BSD)
  10060, // WSAETIMEDOUT — Windows
};

/// errno values that mean there is no route, or the host is down.
const Set<int> kUnreachableErrno = <int>{
  51, // ENETUNREACH    — macOS / iOS (BSD)
  64, // EHOSTDOWN      — macOS / iOS (BSD)
  65, // EHOSTUNREACH   — macOS / iOS (BSD)
  101, // ENETUNREACH   — Linux / Android
  112, // EHOSTDOWN     — Linux / Android
  113, // EHOSTUNREACH  — Linux / Android
  10051, // WSAENETUNREACH  — Windows
  10064, // WSAEHOSTDOWN    — Windows
  10065, // WSAEHOSTUNREACH — Windows
};

/// Classify any error thrown by a TCP connect attempt.
///
/// The errno is authoritative when the platform gives us one. The message is a
/// belt-and-braces fallback for platforms or locales that do not surface an
/// errno — and it explicitly refuses to read "refused" out of a message that
/// also says unreachable / down / timed out.
///
/// Anything unrecognised → [TcpFailureReason.unknown] → [TcpProbeOutcome.dead].
/// Never guess a host into existence.
TcpProbeFailure classifyTcpFailure(Object error) {
  if (error is! SocketException) {
    // TimeoutException, HandshakeException, TlsException, StateError… none of
    // them prove a host answered a SYN.
    return TcpProbeFailure(
      reason: TcpFailureReason.unknown,
      message: error.toString(),
    );
  }

  final OSError? os = error.osError;
  final int? code = os?.errorCode;
  final String message = os?.message.trim().isNotEmpty ?? false
      ? os!.message.trim()
      : error.message;

  // 1. errno first — authoritative wherever the platform surfaces one.
  if (code != null) {
    if (kRefusedErrno.contains(code)) {
      return TcpProbeFailure(
        reason: TcpFailureReason.refused,
        message: message,
        errorCode: code,
      );
    }
    if (kTimedOutErrno.contains(code)) {
      return TcpProbeFailure(
        reason: TcpFailureReason.timedOut,
        message: message,
        errorCode: code,
      );
    }
    if (kUnreachableErrno.contains(code)) {
      return TcpProbeFailure(
        reason: TcpFailureReason.unreachable,
        message: message,
        errorCode: code,
      );
    }
  }

  // 2. Message fallback. Order matters: a timeout / unreachable / host-down
  //    message is NEVER read as a refusal, no matter what else it contains.
  final String haystack =
      '${error.message} ${os?.message ?? ''}'.toLowerCase().trim();

  if (haystack.contains('timed out') || haystack.contains('timeout')) {
    return TcpProbeFailure(
      reason: TcpFailureReason.timedOut,
      message: message,
      errorCode: code,
    );
  }
  if (haystack.contains('unreachable') ||
      haystack.contains('no route') ||
      haystack.contains('host is down')) {
    return TcpProbeFailure(
      reason: TcpFailureReason.unreachable,
      message: message,
      errorCode: code,
    );
  }
  if (haystack.contains('failed host lookup') ||
      haystack.contains('nodename') ||
      haystack.contains('name or service not known') ||
      haystack.contains('lookup')) {
    return TcpProbeFailure(
      reason: TcpFailureReason.lookupFailure,
      message: message,
      errorCode: code,
    );
  }
  if (haystack.contains('refused') || haystack.contains('reset')) {
    return TcpProbeFailure(
      reason: TcpFailureReason.refused,
      message: message,
      errorCode: code,
    );
  }

  // 3. Default: DEAD. An error we cannot positively read as a refusal does not
  //    get to invent a live host.
  return TcpProbeFailure(
    reason: TcpFailureReason.unknown,
    message: message,
    errorCode: code,
  );
}

/// The three-outcome verdict for an error thrown by a connect attempt.
/// Convenience over [classifyTcpFailure] for callers that only need the verdict.
TcpProbeOutcome classifyTcpError(Object error) =>
    classifyTcpFailure(error).outcome;

/// True when the error itself proves the host answered our SYN (a RST).
/// This — NOT `osError != null` — is the liveness test.
bool tcpErrorProvesHostAlive(Object error) =>
    classifyTcpFailure(error).hostAnswered;

/// Connector seam: returns an open socket or throws. Injectable for tests, so
/// no probe in this repo needs a real network to be tested.
typedef TcpConnector = Future<Socket> Function(
  String host,
  int port,
  Duration timeout,
);

/// Run one TCP connect probe against (host, port) and classify it into the
/// three honest outcomes. The one place a probe outcome is decided.
Future<TcpProbeOutcome> probeTcp(
  TcpConnector connect,
  String host,
  int port,
  Duration timeout,
) async {
  try {
    final Socket socket = await connect(host, port, timeout);
    socket.destroy();
    return TcpProbeOutcome.open;
  } catch (e) {
    return classifyTcpError(e);
  }
}
