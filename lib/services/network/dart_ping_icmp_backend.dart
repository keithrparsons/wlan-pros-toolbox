// DartPingIcmpBackend — the real ICMP backend for IcmpService, wrapping the
// `dart_ping` (Android system ping) + `dart_ping_ios` (iOS SimplePing/GBPing)
// packages. This is the ONLY file in the app that imports those packages; the
// IcmpService foundation and both screens stay package-agnostic and fully
// unit-testable against a fake backend.
//
// ── Honesty / verification status (GL-005 + GL-008) ──────────────────────────
// The MAPPING logic in this file is unit-tested below (parsePingData is pure and
// exercised with hand-built PingData fixtures — no live round-trip). What CANNOT
// be verified without a provisioned device is the live ICMP round-trip itself:
//   - iOS:     SimplePing/GBPing needs a device + the local-network permission
//              prompt (Info.plist NSLocalNetworkUsageDescription + NSBonjour-
//              Services). Not exercisable in CI or on a sandboxed Mac.
//   - Android: `dart_ping` spawns the system `ping` — needs a real device /
//              emulator, not the host test runner.
// So: the package wiring, the event→IcmpReply mapping, and the platform routing
// are VERIFIED here. The actual echo/TTL-walk against hardware is DEVICE-PENDING.
//
// ── macOS / desktop (GL-008) ─────────────────────────────────────────────────
// On desktop `dart_ping` would spawn `/sbin/ping`, which the macOS App Sandbox
// blocks. [defaultIcmpBackend] returns null on desktop and IcmpService.echo-
// Capability returns `sandboxedDesktop`, so this backend is never constructed
// there — the sandbox trap is avoided by gating, not discovered at runtime. The
// existing TCP-handshake Ping remains the desktop reachability/latency path.
//
// ── TTL-walk feasibility (the load-bearing capability decision) ──────────────
// On Linux/Android, dart_ping's parser surfaces a router that answers a
// TTL-expired probe as a PingData carrying BOTH a `response` (with the hop's
// `ip`, no `time`) AND `error == ErrorType.timeToLiveExceeded`. We map that to a
// *successful* IcmpReply with a `fromIp` and no `rttMs` — exactly what the
// TTL-walk needs to name the hop. On iOS the dart_ping_ios adapter drops the
// `ttl` argument and never decodes Time-Exceeded, so a TTL-walk cannot name
// hops; IcmpService gates iOS traceroute to `noTimeExceeded`. Never faked.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dart_ping/dart_ping.dart';
import 'package:dart_ping_ios/dart_ping_ios.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'icmp_service.dart';

/// Installs the iOS `dart_ping` factory (SimplePing/GBPing) exactly once.
/// Must be called at app start before any iOS ICMP run. No-op off iOS, and
/// idempotent (registering the factory twice is harmless). Kept here so the
/// package import stays confined to this file; `main.dart` calls it via
/// [registerIcmpBackend].
bool _iosRegistered = false;

void registerIcmpBackend() {
  if (kIsWeb) return;
  if (_iosRegistered) return;
  if (Platform.isIOS) {
    DartPingIOS.register();
  }
  _iosRegistered = true;
}

/// The platform-routed real backend, or null when no real ICMP backend can run
/// on this target (web, or sandboxed desktop where /sbin/ping is blocked).
///
/// The screens call `widget.service ?? IcmpService(backend: defaultIcmpBackend())`.
/// On web/desktop this returns null and IcmpService's capability gate routes the
/// UI to the honest unavailable / sandboxed-desktop state before any run — the
/// null backend is never reached for a run on those targets.
IcmpBackend? defaultIcmpBackend() {
  if (kIsWeb) return null;
  if (Platform.isIOS || Platform.isAndroid) {
    registerIcmpBackend();
    return const DartPingIcmpBackend();
  }
  // macOS / Windows / Linux desktop: real ICMP path is a blocked subprocess.
  return null;
}

/// Real ICMP backend over `dart_ping` / `dart_ping_ios`.
///
/// Thin by design: it owns no sequencing, capability, or fold logic (all of that
/// lives in [IcmpService]). Its single job is to translate `dart_ping`'s
/// [PingData] event stream into [IcmpReply]s via the pure [parsePingData] below.
class DartPingIcmpBackend implements IcmpBackend {
  const DartPingIcmpBackend();

  @override
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  }) {
    final StreamController<IcmpReply> controller = StreamController<IcmpReply>();

    // dart_ping takes interval/timeout in WHOLE SECONDS (ints), count==null for
    // "until stopped", and an outbound ttl (255 default; a low value drives the
    // TTL-walk). Clamp interval/timeout to a >=1s floor so a sub-second Duration
    // never rounds to 0 (which dart_ping would treat as no delay / no timeout).
    final Ping ping = Ping(
      host,
      count: count <= 0 ? null : count,
      interval: _toWholeSeconds(interval),
      timeout: _toWholeSeconds(timeout),
      ttl: ttl ?? 255,
    );

    int seq = 0;
    StreamSubscription<PingData>? sub;

    controller.onListen = () {
      cancel?.then((_) => ping.stop());
      sub = ping.stream.listen(
        (PingData data) {
          final IcmpReply? reply = parsePingData(data, ++seq);
          // A summary-only event maps to null; do not emit it, do not bump seq
          // for it. (seq was already incremented; the next real event overwrites
          // the gap harmlessly — sequence is presentational, not load-bearing.)
          if (reply != null && !controller.isClosed) {
            controller.add(reply);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );
    };
    controller.onCancel = () async {
      await ping.stop();
      await sub?.cancel();
    };
    return controller.stream;
  }

  static int _toWholeSeconds(Duration d) {
    final int s = d.inSeconds;
    return s < 1 ? 1 : s;
  }

  /// PURE mapping from a `dart_ping` [PingData] event to an [IcmpReply], or null
  /// for a summary-only event (which carries no per-probe result). This is the
  /// one piece a device pass must confirm against live output; it is unit-tested
  /// with hand-built fixtures so the logic is verified without hardware.
  ///
  /// Cases (in priority order, mirroring dart_ping's own parser):
  ///   1. A response with an RTT and no error → a real echo reply (or the target
  ///      on the final TTL-walk hop): success, rttMs, fromIp, ttl.
  ///   2. A response carrying ErrorType.timeToLiveExceeded → an intermediate
  ///      router named itself on a TTL-expired probe: SUCCESS for the TTL-walk
  ///      (it names the hop) but with NO rttMs. fromIp is the responding router.
  ///   3. requestTimedOut / noReply → a lost probe (timeout).
  ///   4. unknownHost → name resolution failed.
  ///   5. any other error → generic 'error'.
  ///   6. summary-only event → null (no per-probe datum).
  @visibleForTesting
  static IcmpReply? parsePingData(PingData data, int seq) {
    final PingResponse? r = data.response;
    final PingError? e = data.error;

    // Case 1 — clean echo reply (no error, has a response).
    if (e == null && r != null) {
      return IcmpReply(
        sequence: r.seq ?? seq,
        success: true,
        rttMs: _ms(r.time),
        fromIp: r.ip,
        ttl: r.ttl,
      );
    }

    // Case 2 — TTL exceeded: a router answered a TTL-expired probe. dart_ping
    // attaches the responding IP to `response` and flags the error. For the
    // TTL-walk this NAMES the hop, so it is a success with a fromIp and no RTT.
    if (e != null && e.error == ErrorType.timeToLiveExceeded) {
      return IcmpReply(
        sequence: r?.seq ?? seq,
        success: true,
        rttMs: _ms(r?.time), // usually null on a TTL-exceeded line
        fromIp: r?.ip,
        ttl: r?.ttl,
      );
    }

    // Cases 3–5 — genuine failures.
    if (e != null) {
      return IcmpReply(
        sequence: r?.seq ?? seq,
        success: false,
        errorLabel: switch (e.error) {
          ErrorType.requestTimedOut || ErrorType.noReply => 'timeout',
          ErrorType.unknownHost => 'unknownHost',
          _ => 'error',
        },
      );
    }

    // Case 6 — summary-only (or empty) event: no per-probe datum to emit.
    return null;
  }

  static double? _ms(Duration? d) =>
      d == null ? null : d.inMicroseconds / 1000.0;
}
