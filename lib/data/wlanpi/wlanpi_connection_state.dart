// WLAN Pi companion — connection / discovery state machine (UI-facing).
//
// Every state below is a FIRST-CLASS, friendly screen — never an error dump
// (design spec §1.1, §2.5). The session service drives these; the discovery
// screen renders one card per phase.

import 'wlanpi_models.dart';

/// The discovery + connection phases the UI renders.
enum WlanPiConnPhase {
  /// Nothing attempted yet — show the "find my Pi" entry with mDNS + manual IP.
  initial,

  /// mDNS browse in progress ("searching for wlanpi-*.local on :31415…").
  searching,

  /// One or more candidates found; user picks/confirms.
  found,

  /// A candidate was selected but its /openapi.json reports an OS/core version
  /// below the supported floor (assume OS 3.x; 2.x has no core API).
  wrongVersion,

  /// Reachable wlanpi-core, but no valid session yet — needs the token handshake.
  authNeeded,

  /// Authenticated session established; reads/profiler available.
  connected,

  /// Browse finished (or manual entry failed) with nothing reachable.
  noPiFound,
}

/// A discovered (or manually-entered) WLAN Pi candidate.
class WlanPiCandidate {
  const WlanPiCandidate({
    required this.host,
    required this.port,
    this.hostname,
    this.coreVersion,
    this.discoveredViaMdns = false,
  });

  /// IP or hostname (e.g. `192.168.1.42` or `wlanpi-cda.local`).
  final String host;

  /// Always 31415 on production units (the nginx-fronted core port).
  final int port;

  /// Friendly hostname if mDNS supplied one.
  final String? hostname;

  /// wlanpi-core version read from `/openapi.json` validation, when known.
  final String? coreVersion;

  /// True if found via mDNS, false if hand-entered.
  final bool discoveredViaMdns;

  /// Base URL for the v1 API. The version base path (`/api/v1`) is carried here
  /// once, never hardcoded at call sites (design spec §2.2).
  String get apiBaseUrl => 'http://$host:$port/api/v1';

  /// The OpenAPI document URL used to validate + version-gate (design spec §1.1).
  String get openApiUrl => 'http://$host:$port/openapi.json';

  String get label => hostname?.isNotEmpty == true ? hostname! : '$host:$port';
}

/// The full UI state the discovery/connection screen renders.
class WlanPiConnState {
  const WlanPiConnState({
    required this.phase,
    this.candidates = const <WlanPiCandidate>[],
    this.selected,
    this.deviceInfo,
    this.message,
  });

  final WlanPiConnPhase phase;
  final List<WlanPiCandidate> candidates;
  final WlanPiCandidate? selected;

  /// Populated once connected and `system/device/info` has been read.
  final WlanPiDeviceInfo? deviceInfo;

  /// A one-line, friendly explanation for the current phase (the "why" hint on
  /// noPiFound: same SSID? mDNS blocked? Pi on?).
  final String? message;

  const WlanPiConnState.initial() : this(phase: WlanPiConnPhase.initial);

  WlanPiConnState copyWith({
    WlanPiConnPhase? phase,
    List<WlanPiCandidate>? candidates,
    WlanPiCandidate? selected,
    WlanPiDeviceInfo? deviceInfo,
    String? message,
  }) =>
      WlanPiConnState(
        phase: phase ?? this.phase,
        candidates: candidates ?? this.candidates,
        selected: selected ?? this.selected,
        deviceInfo: deviceInfo ?? this.deviceInfo,
        message: message ?? this.message,
      );
}
