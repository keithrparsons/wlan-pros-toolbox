// IcmpService — the SHARED native ICMP foundation for two tools:
//   1. Real ICMP Ping  (icmp_ping_screen.dart) — the documented fast-follow to
//      the existing TCP-handshake Ping (ping_screen.dart, kept as the desktop
//      path).
//   2. Mobile Traceroute (built on a TTL-walk over this same layer) — extends
//      the desktop-only system Traceroute (traceroute_screen.dart, untouched)
//      to mobile *where the platform genuinely supports it*.
//
// Build the native layer once, expose both on it. This file owns the honest
// per-platform capability matrix and the method/sequencing logic; the two
// screens are thin renderers over it.
//
// ──────────────────────────────────────────────────────────────────────────
// PLATFORM MATRIX (GL-008 — honest, no fabrication):
//
//   iOS:      real ICMP echo via SimplePing/GBPing (`dart_ping_ios` →
//             `flutter_icmp_ping`). Needs NSLocalNetworkUsageDescription
//             (already present) + the Bonjour entries added for the device
//             pass. TTL-WALK TRACEROUTE IS *NOT* FEASIBLE on iOS through this
//             stack: GBPing.m sets IP_TTL on the socket (so probes can expire
//             early) but its receive path only accepts ICMP EchoReply (type 0)
//             — it never parses ICMP TimeExceeded (type 11), which is the
//             message intermediate routers send when TTL expires and the one a
//             traceroute needs to name each hop. Setting a low TTL there just
//             makes the echo time out with no hop IP. So iOS ICMP ping = yes;
//             iOS TTL-walk traceroute = honest "unavailable", never faked.
//             >>> THIS CODE PATH CANNOT BE VERIFIED WITHOUT A REAL DEVICE. <<<
//
//   Android:  real ICMP echo via `dart_ping` (spawns the system `ping`; no
//             sandbox blocks it on Android). `dart_ping`'s `ttl` maps to
//             `ping -t <ttl>` (Linux/Android) which sets the OUTBOUND TTL, and
//             the busybox/toybox `ping` prints the responding hop on a
//             "From <ip> ... Time to live exceeded" line — so a TTL-walk IS
//             feasible on Android. (Device-pending verification.)
//
//   macOS/    `dart_ping` would spawn `/sbin/ping`, which the macOS App Sandbox
//   desktop:  (enabled in this project) BLOCKS — the documented GL-008 trap.
//             Real ICMP echo → honest "not available in the sandboxed desktop
//             build" state. The existing TCP-handshake Ping stays the desktop
//             path. Desktop system Traceroute (traceroute_service.dart) is the
//             desktop traceroute path and is left untouched.
//
//   Web:      no dart:io, no raw sockets → NetworkUnavailableView, same as the
//             other socket tools.
// ──────────────────────────────────────────────────────────────────────────
//
// TESTABILITY: every decision in this file (capability gating, method labels,
// reply/summary mapping, TTL sequencing, malformed-input handling) is pure or
// driven through an injected [IcmpBackend], so it is fully unit-testable
// WITHOUT the `dart_ping` package and WITHOUT a live ICMP round-trip. The real
// backend (`DartPingIcmpBackend`) is the only device-pending piece; it is a
// thin adapter with no logic of its own.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// How a given platform can run *ICMP echo* (the ping primitive).
enum IcmpEchoCapability {
  /// Real ICMP echo is available (iOS via SimplePing, Android via system ping).
  available,

  /// Desktop under the macOS App Sandbox: the only ICMP path is spawning
  /// `/sbin/ping`, which the sandbox blocks. The UI points the user at the
  /// TCP-handshake Ping instead.
  sandboxedDesktop,

  /// Web — no raw sockets / no dart:io. Routed to NetworkUnavailableView.
  web,
}

/// How a given platform can run a *TTL-walk traceroute* on the ICMP layer.
/// Deliberately separate from [IcmpEchoCapability]: iOS can echo but cannot
/// TTL-walk (see file header), so the two capabilities must not be conflated.
enum IcmpTracerouteCapability {
  /// TTL-walk is feasible: the platform's ICMP layer both sets an outbound TTL
  /// AND surfaces the responding hop on TimeExceeded. (Android.)
  available,

  /// The platform has ICMP echo but its ICMP layer does not surface
  /// TimeExceeded hops, so a TTL-walk cannot name intermediate routers. (iOS,
  /// via GBPing.) The desktop system traceroute is the path on desktop; here
  /// the honest answer is "not on this device".
  noTimeExceeded,

  /// Desktop under the App Sandbox: ICMP subprocess blocked. The desktop
  /// *system* traceroute tool covers desktop; this ICMP TTL-walk does not run.
  sandboxedDesktop,

  /// Web.
  web,
}

/// Precise, never-fabricated method label for a measurement, surfaced verbatim
/// in the UI so a TCP probe is never presented as ICMP (GL-005 honesty bar).
class IcmpMethod {
  const IcmpMethod._(this.label);

  /// Real ICMP echo request/reply.
  static const IcmpMethod icmpEcho = IcmpMethod._('ICMP echo');

  /// A TTL-walk built on ICMP echo (mobile traceroute).
  static const IcmpMethod ttlWalk = IcmpMethod._('ICMP TTL-walk');

  final String label;

  @override
  String toString() => label;
}

/// One ICMP echo reply (one "ping"), backend-agnostic.
class IcmpReply {
  const IcmpReply({
    required this.sequence,
    required this.success,
    this.rttMs,
    this.fromIp,
    this.ttl,
    this.errorLabel,
  });

  /// 1-based sequence number.
  final int sequence;

  /// True when an EchoReply landed within the timeout.
  final bool success;

  /// Round-trip time in milliseconds, or null on loss.
  final double? rttMs;

  /// Source IP of the reply, when the backend reports it.
  final String? fromIp;

  /// TTL field of the reply packet, when reported.
  final int? ttl;

  /// Short reason this probe failed ('timeout', 'unknownHost', 'error'), or
  /// null on success.
  final String? errorLabel;
}

/// One discovered hop on a TTL-walk traceroute.
class IcmpHop {
  const IcmpHop({
    required this.ttl,
    this.fromIp,
    this.rttMs,
    this.timedOut = false,
  });

  /// Hop number == the outbound TTL used for this probe.
  final int ttl;

  /// IP that answered at this TTL (a TimeExceeded source, or the target on the
  /// final hop), or null when the hop did not answer.
  final String? fromIp;

  /// Best RTT seen at this hop, or null when it timed out.
  final double? rttMs;

  /// True when every probe at this TTL timed out (`* * *`).
  final bool timedOut;

}

/// Running aggregate over ICMP replies — mirrors the TCP PingStats shape so the
/// Real-ICMP-Ping screen can reuse the same min/avg/max/loss + sparkline UI.
class IcmpStats {
  const IcmpStats({
    required this.sent,
    required this.received,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.rttsMs,
  });

  final int sent;
  final int received;
  final double? minMs;
  final double? avgMs;
  final double? maxMs;
  final List<double> rttsMs;

  int get lost => sent - received;
  double get lossFraction => sent == 0 ? 0 : lost / sent;

  static const IcmpStats empty = IcmpStats(
    sent: 0,
    received: 0,
    minMs: null,
    avgMs: null,
    maxMs: null,
    rttsMs: <double>[],
  );

  IcmpStats accumulate(IcmpReply reply) {
    final List<double> rtts = List<double>.of(rttsMs);
    if (reply.success && reply.rttMs != null) rtts.add(reply.rttMs!);
    double? mn;
    double? mx;
    double? av;
    if (rtts.isNotEmpty) {
      mn = rtts.first;
      mx = rtts.first;
      double sum = 0;
      for (final double v in rtts) {
        if (v < mn!) mn = v;
        if (v > mx!) mx = v;
        sum += v;
      }
      av = sum / rtts.length;
    }
    return IcmpStats(
      sent: sent + 1,
      received: received + (reply.success ? 1 : 0),
      minMs: mn,
      avgMs: av,
      maxMs: mx,
      rttsMs: rtts,
    );
  }
}

/// A streamed ICMP-ping tick: the reply that just landed + running stats.
class IcmpProgress {
  const IcmpProgress({required this.reply, required this.stats});

  final IcmpReply reply;
  final IcmpStats stats;
}

/// A streamed traceroute event: a hop landed, or the run reached a terminal
/// state.
class IcmpTraceEvent {
  const IcmpTraceEvent._({this.hop, this.done = false, this.reachedTarget = false});

  final IcmpHop? hop;
  final bool done;
  final bool reachedTarget;

  factory IcmpTraceEvent.hop(IcmpHop hop) => IcmpTraceEvent._(hop: hop);
  factory IcmpTraceEvent.complete({required bool reachedTarget}) =>
      IcmpTraceEvent._(done: true, reachedTarget: reachedTarget);
}

/// The native ICMP backend abstraction. The real implementation
/// ([DartPingIcmpBackend]) wraps `dart_ping`/`dart_ping_ios`; tests inject a
/// fake so all logic above is verifiable without the package or a device.
///
/// A single echo "session" emits a stream of [IcmpReply]s for one `(host, ttl)`
/// pair and completes when [count] replies have been delivered (or it is
/// cancelled). Setting [ttl] low is what makes a TTL-walk possible on backends
/// that surface the responding hop.
abstract class IcmpBackend {
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  });
}

/// The shared ICMP foundation. Both Real-ICMP-Ping and Mobile-Traceroute call
/// into this one service.
class IcmpService {
  IcmpService({
    IcmpBackend? backend,
    String? platformOverride,
    bool? isWebOverride,
  })  : _backend = backend, // ignore: prefer_initializing_formals
        _platform = platformOverride,
        _isWeb = isWebOverride ?? kIsWeb;

  final IcmpBackend? _backend;

  /// Operating system string ('ios','android','macos','windows','linux'), or
  /// null to defer to the real platform. Injected in tests.
  final String? _platform;
  final bool _isWeb;

  /// Operating system used for capability gating. Off-web this reads the real
  /// platform; in tests it is the injected override. Never read on web — the
  /// screen's `NetworkSupport` gate routes web to NetworkUnavailableView before
  /// this service is constructed, and [echoCapability]/[tracerouteCapability]
  /// short-circuit on [_isWeb] first regardless.
  String get _os => _platform ?? (_isWeb ? 'web' : Platform.operatingSystem);

  bool get _isMobile => _os == 'ios' || _os == 'android';

  // ── Capability gating ────────────────────────────────────────────────────

  /// Whether real ICMP echo can run on the current target.
  IcmpEchoCapability get echoCapability {
    if (_isWeb) return IcmpEchoCapability.web;
    if (_isMobile) return IcmpEchoCapability.available;
    // macOS/Windows/Linux desktop: the ICMP path is a subprocess the macOS
    // sandbox blocks. Honest sandboxed-desktop state; TCP Ping is the path.
    return IcmpEchoCapability.sandboxedDesktop;
  }

  /// Whether a TTL-walk traceroute can run on the current target. iOS is
  /// explicitly [noTimeExceeded] (GBPing drops TimeExceeded) even though it can
  /// echo — the two capabilities are deliberately decoupled.
  IcmpTracerouteCapability get tracerouteCapability {
    if (_isWeb) return IcmpTracerouteCapability.web;
    if (_os == 'android') return IcmpTracerouteCapability.available;
    if (_os == 'ios') return IcmpTracerouteCapability.noTimeExceeded;
    return IcmpTracerouteCapability.sandboxedDesktop;
  }

  // ── Input validation (pure, unit-tested) ─────────────────────────────────

  /// Returns an error string for an invalid host, or null when acceptable.
  /// Intentionally permissive (the backend does the real resolve) but rejects
  /// the obvious malformed cases so we never hand junk to the native layer.
  static String? validateHost(String raw) {
    final String host = raw.trim();
    if (host.isEmpty) return 'Enter a host or IP.';
    if (host.contains(' ')) return 'Host cannot contain spaces.';
    if (host.length > 253) return 'Host is too long.';
    // Reject control characters / shell-ish metacharacters defensively even
    // though no shell is ever spawned from here.
    if (RegExp(r'[\x00-\x1f;|&`$<>]').hasMatch(host)) {
      return 'Host contains invalid characters.';
    }
    return null;
  }

  // ── Real ICMP Ping ───────────────────────────────────────────────────────

  /// Stream [count] ICMP echo probes to [host], emitting an [IcmpProgress] per
  /// reply with running stats. Mirrors the TCP PingService.ping contract so the
  /// screen layer is near-identical.
  ///
  /// Throws [StateError] if called where [echoCapability] is not `available`;
  /// the screen gates on capability first and never reaches this.
  Stream<IcmpProgress> ping({
    required String host,
    int count = 10,
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 2),
    Future<void>? cancel,
  }) {
    if (echoCapability != IcmpEchoCapability.available) {
      throw StateError('ICMP echo not available on this platform');
    }
    final IcmpBackend backend = _requireBackend();
    final StreamController<IcmpProgress> controller =
        StreamController<IcmpProgress>();
    StreamSubscription<IcmpReply>? sub;
    IcmpStats stats = IcmpStats.empty;

    controller.onListen = () {
      sub = backend
          .echo(
        host: host,
        count: count,
        interval: interval,
        timeout: timeout,
        cancel: cancel,
      )
          .listen(
        (IcmpReply reply) {
          stats = stats.accumulate(reply);
          if (!controller.isClosed) {
            controller.add(IcmpProgress(reply: reply, stats: stats));
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
      await sub?.cancel();
    };
    return controller.stream;
  }

  // ── Mobile Traceroute (TTL-walk on the same ICMP layer) ──────────────────

  /// Walk the TTL from 1..[maxHops], sending one (or [probesPerHop]) ICMP echo
  /// at each TTL and surfacing the hop that answered (a TimeExceeded source, or
  /// the target on the final hop). Stops when the target is reached or maxHops
  /// is hit.
  ///
  /// Throws [StateError] if [tracerouteCapability] is not `available`; the
  /// screen gates first. The sequencing logic (one session per TTL, advancing
  /// on reply or timeout, stop-on-target) is pure-ish and unit-tested via a
  /// fake backend.
  Stream<IcmpTraceEvent> traceroute({
    required String host,
    int maxHops = 30,
    int probesPerHop = 1,
    Duration interval = const Duration(milliseconds: 200),
    Duration timeout = const Duration(seconds: 2),
    Future<void>? cancel,
  }) {
    if (tracerouteCapability != IcmpTracerouteCapability.available) {
      throw StateError('TTL-walk traceroute not available on this platform');
    }
    final IcmpBackend backend = _requireBackend();
    final StreamController<IcmpTraceEvent> controller =
        StreamController<IcmpTraceEvent>();
    bool cancelled = false;
    cancel?.then((_) => cancelled = true);

    Future<void> run() async {
      bool reached = false;
      for (int ttl = 1; ttl <= maxHops && !cancelled; ttl++) {
        // One echo "session" capped at probesPerHop, with this TTL. The backend
        // emits a reply per probe; a TimeExceeded from a router shows up as a
        // success with a fromIp != host, the target shows up as fromIp == host.
        final List<IcmpReply> replies = await backend
            .echo(
              host: host,
              count: probesPerHop,
              interval: interval,
              timeout: timeout,
              ttl: ttl,
              cancel: cancel,
            )
            .toList();
        if (cancelled) break;

        final IcmpHop hop = _foldHop(ttl, host, replies);
        if (controller.isClosed) return;
        controller.add(IcmpTraceEvent.hop(hop));

        if (hop.fromIp == host && !hop.timedOut) {
          reached = true;
          break;
        }
      }
      if (!controller.isClosed) {
        controller.add(IcmpTraceEvent.complete(reachedTarget: reached));
        await controller.close();
      }
    }

    controller.onListen = run;
    return controller.stream;
  }

  /// Pure fold: collapse the replies seen at one TTL into a single [IcmpHop].
  /// Picks the first answering source and the best RTT; marks timedOut when no
  /// probe answered.
  @visibleForTesting
  static IcmpHop foldHop(int ttl, String target, List<IcmpReply> replies) =>
      _foldHop(ttl, target, replies);

  static IcmpHop _foldHop(int ttl, String target, List<IcmpReply> replies) {
    String? fromIp;
    double? best;
    for (final IcmpReply r in replies) {
      if (r.success) {
        fromIp ??= r.fromIp;
        if (r.rttMs != null && (best == null || r.rttMs! < best)) {
          best = r.rttMs;
        }
      }
    }
    final bool timedOut = fromIp == null && best == null;
    return IcmpHop(ttl: ttl, fromIp: fromIp, rttMs: best, timedOut: timedOut);
  }

  IcmpBackend _requireBackend() {
    final IcmpBackend? b = _backend;
    if (b == null) {
      // No real backend wired in this build. This is the device-pending seam:
      // DartPingIcmpBackend is constructed by the screen on a supported native
      // target. Reaching here without one is a programmer error, surfaced
      // loudly rather than silently faking data.
      throw StateError(
        'No IcmpBackend wired. The real dart_ping backend is only constructed '
        'on a supported native target; this build has none.',
      );
    }
    return b;
  }
}
