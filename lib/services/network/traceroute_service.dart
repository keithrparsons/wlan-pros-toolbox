// TracerouteService — hop-by-hop path discovery via the system traceroute.
//
// WHY DESKTOP-ONLY, AND WHY SUBPROCESS (deliberate, documented decision):
//
// A real traceroute needs to read ICMP TIME_EXCEEDED replies from intermediate
// routers. That requires a raw ICMP socket (root / entitlement Dart can't open)
// OR the system traceroute binary, which already holds the necessary
// privileges. There is no clean cross-platform Dart package for this and no
// pure-`dart:io` path: `Socket` can *set* IP_TTL via setRawOption, but it
// cannot *receive* the ICMP TIME_EXCEEDED that identifies each hop without a
// raw socket. So faking hops from TCP timing is not a traceroute — it would be
// a lie, and the brief (§10) forbids that.
//
// The honest matrix:
//   - macOS / Windows / Linux desktop: spawn the OS traceroute/tracert and
//     parse it. This is the genuine tool. NOTE: under the macOS App Sandbox
//     (enabled in this project) spawning a binary outside the app bundle can be
//     blocked; we attempt it and, on failure, return an explicit
//     `TracerouteUnavailable` verdict rather than hanging or pretending.
//   - iOS / Android: arbitrary subprocess execution is sandboxed out entirely.
//     The tool reports `unsupportedPlatform` and the UI says, plainly,
//     "Traceroute runs on desktop — use Ping here."
//   - Web: never reached (gated by NetworkSupport.tracerouteSupported).
//
// Live streaming: traceroute emits one line per hop as it probes. We read
// stdout line-by-line and surface each hop the moment it resolves, so the UI
// fills in hop-by-hop and the run is cancellable mid-flight (we kill the
// process).
//
// Web safety: imports dart:io (Process/Platform). Gated behind
// `NetworkSupport.tracerouteSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'network_target.dart';

/// One discovered hop on the path.
class TracerouteHop {
  const TracerouteHop({
    required this.ttl,
    this.host,
    this.ip,
    this.rttsMs = const <double>[],
    this.timedOut = false,
  });

  /// Hop number (TTL).
  final int ttl;

  /// Reverse-DNS name of the hop, if traceroute resolved one.
  final String? host;

  /// IP address of the hop, or null when the hop did not answer.
  final String? ip;

  /// Per-probe RTTs at this hop (traceroute sends 3 by default), in ms.
  final List<double> rttsMs;

  /// True when every probe at this TTL timed out (a `* * *` line).
  final bool timedOut;

  /// Best (minimum) RTT at this hop, or null when it timed out.
  double? get bestRttMs {
    if (rttsMs.isEmpty) return null;
    double m = rttsMs.first;
    for (final double v in rttsMs) {
      if (v < m) m = v;
    }
    return m;
  }
}

/// Why traceroute is not running, distinct from a normal "no result yet".
enum TracerouteUnavailableReason {
  /// iOS/Android — subprocess execution is sandboxed out.
  unsupportedPlatform,

  /// Desktop, but the OS binary could not be launched (sandbox denial, missing
  /// binary, PATH issue). The UI shows the precise reason.
  binaryUnavailable,

  /// The supplied host failed validation (empty, malformed, or a `-`-leading
  /// value that would be parsed as a flag). Never reaches the binary.
  invalidHost,
}

/// Terminal outcome of a traceroute run.
sealed class TracerouteResult {
  const TracerouteResult();
}

/// The run completed (reached the target or hit max hops).
class TracerouteComplete extends TracerouteResult {
  const TracerouteComplete({required this.reachedTarget});

  /// True if the final hop was the requested target.
  final bool reachedTarget;
}

/// The run could not start on this platform / in this sandbox.
class TracerouteUnavailable extends TracerouteResult {
  const TracerouteUnavailable({required this.reason, this.detail});

  final TracerouteUnavailableReason reason;

  /// Human-readable detail (e.g. the OS error) for the UI.
  final String? detail;
}

/// The run was cancelled by the user before completing.
class TracerouteCancelled extends TracerouteResult {
  const TracerouteCancelled();
}

/// A streamed event: either a hop landed, or the run reached a terminal state.
class TracerouteEvent {
  const TracerouteEvent._({this.hop, this.result});

  /// A newly-discovered hop, or null when this event is a terminal [result].
  final TracerouteHop? hop;

  /// Terminal result, or null when this event carries a [hop].
  final TracerouteResult? result;

  factory TracerouteEvent.hop(TracerouteHop hop) =>
      TracerouteEvent._(hop: hop);
  factory TracerouteEvent.done(TracerouteResult result) =>
      TracerouteEvent._(result: result);
}

/// Spawns and parses the system traceroute. The [processStarter] and
/// [platformOverride] seams keep parsing unit-testable without a real network
/// or a real subprocess.
class TracerouteService {
  TracerouteService({
    Future<Process> Function(String executable, List<String> args)?
        processStarter,
    String? platformOverride,
  })  : _start = processStarter ?? Process.start,
        _platform = platformOverride ?? Platform.operatingSystem;

  final Future<Process> Function(String executable, List<String> args) _start;
  final String _platform;

  bool get _isWindows => _platform == 'windows';
  bool get _isDesktop =>
      _platform == 'macos' || _platform == 'windows' || _platform == 'linux';

  /// Whether this platform can run traceroute at all (desktop only). The UI
  /// reads this to choose between the form and the "use Ping" state.
  bool get isSupportedPlatform => _isDesktop;

  /// Runtime sandbox/capability probe — distinct from [isSupportedPlatform].
  ///
  /// [isSupportedPlatform] answers "is this an OS where traceroute *could*
  /// run" (desktop yes, mobile no). [isLaunchable] answers the sharper
  /// question the App Store target forces on us: "can THIS BUILD actually
  /// spawn the binary right now?" The macOS App Store build ships with the App
  /// Sandbox enabled, which denies launching the system traceroute
  /// ("Operation not permitted"), while a non-sandboxed Developer ID
  /// (direct-download) macOS build, and the Windows and Linux builds, launch it
  /// fine. So the screen probes the live capability instead of hard-coding
  /// "macOS = unavailable", and adapts to whichever build it is running in.
  ///
  /// Implementation: a side-effect-free launch of the binary with no arguments.
  /// traceroute/tracert with no args just print usage and exit non-zero, so no
  /// actual trace runs. The exit code is irrelevant; the only question is
  /// whether the PROCESS LAUNCHES at all. A [ProcessException] (sandbox denial,
  /// missing binary, PATH issue) or a timeout means not launchable. This method
  /// never throws.
  Future<bool> isLaunchable() async {
    if (!_isDesktop) return false;
    final String binary = _isWindows ? 'tracert' : 'traceroute';
    try {
      // Use the same start seam as a real run so tests can drive this without
      // a real subprocess. We only care that the launch did not throw.
      final Process process = await _start(binary, const <String>[])
          .timeout(const Duration(seconds: 3));
      // Drain and reap so we never leave a zombie or an unread pipe.
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode);
      return true;
    } on Object {
      // ProcessException (sandbox denial / missing binary), TimeoutException,
      // or anything else: this build cannot launch the binary.
      return false;
    }
  }

  /// Run traceroute against [host], streaming each hop as it resolves and a
  /// terminal [TracerouteResult] at the end.
  ///
  /// - [maxHops] caps the TTL range (default 30).
  /// - [cancel] kills the process and ends the stream.
  Stream<TracerouteEvent> trace({
    required String host,
    int maxHops = 30,
    Future<void>? cancel,
  }) {
    final StreamController<TracerouteEvent> controller =
        StreamController<TracerouteEvent>();

    if (!_isDesktop) {
      // Mobile: no subprocess. Emit the precise unavailable verdict and close.
      controller.onListen = () {
        controller.add(
          TracerouteEvent.done(
            const TracerouteUnavailable(
              reason: TracerouteUnavailableReason.unsupportedPlatform,
            ),
          ),
        );
        controller.close();
      };
      return controller.stream;
    }

    // Validate the host BEFORE it can reach Process.start. A `-`/`--`-leading
    // value would otherwise be parsed by the binary as a flag (argument
    // injection); a malformed value is a no-op spawn. Either way, never spawn.
    final NetworkTargetResult target = NetworkTarget.validateHostOrIp(host);
    if (target is! ValidNetworkTarget) {
      final String detail = (target as InvalidNetworkTarget).message;
      controller.onListen = () {
        controller.add(
          TracerouteEvent.done(
            TracerouteUnavailable(
              reason: TracerouteUnavailableReason.invalidHost,
              detail: detail,
            ),
          ),
        );
        controller.close();
      };
      return controller.stream;
    }
    final String validatedHost = target.value;

    Process? process;
    bool cancelled = false;
    bool reachedTarget = false;

    cancel?.then((_) {
      cancelled = true;
      process?.kill(ProcessSignal.sigterm);
    });

    final (String exe, List<String> args) = _command(validatedHost, maxHops);

    Future<void> run() async {
      try {
        process = await _start(exe, args);
      } on Object catch (e) {
        // Sandbox denial / missing binary / PATH issue — be explicit, never
        // hang or pretend.
        if (!controller.isClosed) {
          controller.add(
            TracerouteEvent.done(
              TracerouteUnavailable(
                reason: TracerouteUnavailableReason.binaryUnavailable,
                detail: e.toString(),
              ),
            ),
          );
          await controller.close();
        }
        return;
      }

      final Process proc = process!;
      // tracert (Windows) prints to stdout; traceroute (Unix) prints hop lines
      // to stderr on some systems and stdout on others — read both.
      final Stream<String> lines = StreamGroup.merge(<Stream<String>>[
        proc.stdout.transform(utf8.decoder).transform(const LineSplitter()),
        proc.stderr.transform(utf8.decoder).transform(const LineSplitter()),
      ]);

      await for (final String line in lines) {
        if (cancelled) break;
        final TracerouteHop? hop =
            _isWindows ? _parseWindowsLine(line) : _parseUnixLine(line);
        if (hop != null) {
          if (hop.ip == validatedHost) reachedTarget = true;
          if (!controller.isClosed) {
            controller.add(TracerouteEvent.hop(hop));
          }
        }
      }

      await proc.exitCode;

      if (controller.isClosed) return;
      if (cancelled) {
        controller.add(TracerouteEvent.done(const TracerouteCancelled()));
      } else {
        controller.add(
          TracerouteEvent.done(
            TracerouteComplete(reachedTarget: reachedTarget),
          ),
        );
      }
      await controller.close();
    }

    controller.onListen = run;
    controller.onCancel = () {
      cancelled = true;
      process?.kill(ProcessSignal.sigterm);
    };
    return controller.stream;
  }

  (String, List<String>) _command(String host, int maxHops) {
    if (_isWindows) {
      // tracert -d (no rDNS, faster) -h maxHops -w 2000ms. tracert has no `--`
      // argument terminator; the NetworkTarget allow-list (which rejects any
      // `-`-leading host) is the guard here.
      return ('tracert', <String>['-d', '-h', '$maxHops', '-w', '2000', host]);
    }
    // Unix traceroute: -m maxHops, -q 3 probes, -w 2s wait. No -n so we get
    // rDNS names where available. The literal `--` terminates option parsing:
    // everything after it is positional, so even if a dash-leading value ever
    // got this far it could not be parsed as a flag (defense in depth atop the
    // NetworkTarget validation in trace()).
    return (
      'traceroute',
      <String>['-m', '$maxHops', '-q', '3', '-w', '2', '--', host],
    );
  }

  /// Parse a Unix `traceroute` hop line, e.g.:
  ///   ` 1  router.local (192.168.1.1)  1.234 ms  1.111 ms  1.050 ms`
  ///   ` 5  * * *`
  ///   ` 7  10.0.0.1 (10.0.0.1)  9.9 ms  *  10.1 ms`
  /// Returns null for non-hop lines (the header, blank lines).
  static TracerouteHop? _parseUnixLine(String raw) {
    final String line = raw.trimRight();
    final RegExpMatch? lead = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
    if (lead == null) return null;
    final int ttl = int.parse(lead.group(1)!);
    final String rest = lead.group(2)!;

    if (RegExp(r'^\*(\s+\*)*\s*$').hasMatch(rest.trim())) {
      return TracerouteHop(ttl: ttl, timedOut: true);
    }

    String? host;
    String? ip;
    // `name (ip)` or bare `ip`.
    final RegExpMatch? named =
        RegExp(r'([^\s()]+)\s+\(([0-9a-fA-F:.]+)\)').firstMatch(rest);
    if (named != null) {
      host = named.group(1);
      ip = named.group(2);
    } else {
      final RegExpMatch? bare =
          RegExp(r'(\d{1,3}(?:\.\d{1,3}){3}|[0-9a-fA-F:]{2,})').firstMatch(rest);
      ip = bare?.group(1);
    }

    final List<double> rtts = RegExp(r'([\d.]+)\s*ms')
        .allMatches(rest)
        .map((Match m) => double.tryParse(m.group(1)!))
        .whereType<double>()
        .toList();

    return TracerouteHop(
      ttl: ttl,
      host: host,
      ip: ip,
      rttsMs: rtts,
      timedOut: rtts.isEmpty && ip == null,
    );
  }

  /// Parse a Windows `tracert -d` hop line, e.g.:
  ///   `  1     1 ms     1 ms     1 ms  192.168.1.1`
  ///   `  3     *        *        *     Request timed out.`
  /// Returns null for header/footer lines.
  static TracerouteHop? _parseWindowsLine(String raw) {
    final String line = raw.trimRight();
    final RegExpMatch? lead = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
    if (lead == null) return null;
    final int ttl = int.parse(lead.group(1)!);
    final String rest = lead.group(2)!;

    if (rest.toLowerCase().contains('request timed out')) {
      return TracerouteHop(ttl: ttl, timedOut: true);
    }

    final List<double> rtts = RegExp(r'(<?\d+)\s*ms')
        .allMatches(rest)
        .map((Match m) {
          final String v = m.group(1)!.replaceAll('<', '');
          return double.tryParse(v);
        })
        .whereType<double>()
        .toList();

    final RegExpMatch? ipMatch =
        RegExp(r'(\d{1,3}(?:\.\d{1,3}){3}|[0-9a-fA-F:]{2,}:[0-9a-fA-F:]+)')
            .firstMatch(rest);
    final String? ip = ipMatch?.group(1);

    if (ip == null && rtts.isEmpty) return null;

    return TracerouteHop(
      ttl: ttl,
      ip: ip,
      rttsMs: rtts,
      timedOut: rtts.isEmpty,
    );
  }
}

/// Test seam — exposes the otherwise-private line parsers to unit tests
/// without widening the service's public API. Parsing is the load-bearing,
/// regression-prone logic, so it must be directly testable.
@visibleForTesting
class TracerouteServiceTestHook {
  TracerouteServiceTestHook._();

  static TracerouteHop? parseUnix(String line) =>
      TracerouteService._parseUnixLine(line);

  static TracerouteHop? parseWindows(String line) =>
      TracerouteService._parseWindowsLine(line);
}

/// Minimal stream merge so we can read stdout+stderr as one ordered line
/// stream without pulling in `package:async`. Emits events from all sources as
/// they arrive; closes when every source is done.
class StreamGroup {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    final StreamController<T> controller = StreamController<T>();
    int open = streams.length;
    final List<StreamSubscription<T>> subs = <StreamSubscription<T>>[];

    void maybeClose() {
      if (open == 0 && !controller.isClosed) controller.close();
    }

    controller.onCancel = () async {
      for (final StreamSubscription<T> s in subs) {
        await s.cancel();
      }
    };

    for (final Stream<T> s in streams) {
      subs.add(
        s.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            open--;
            maybeClose();
          },
        ),
      );
    }
    if (streams.isEmpty) controller.close();
    return controller.stream;
  }
}
