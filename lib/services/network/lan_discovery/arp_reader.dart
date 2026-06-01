// SPIKE-HSD-01 — ARP-cache reader seam (THROWAWAY spike).
//
// Gate 2 (the pivot): can a SANDBOXED macOS build read IP → MAC for LAN hosts
// WITHOUT spawning a subprocess? This is the Dart side of that read. The actual
// kernel read happens in Swift (macos/Runner/ArpTableChannel.swift) via
// `sysctl(CTL_NET, AF_ROUTE, …, NET_RT_FLAGS, RTF_LLINFO)` — NO `Process.run`,
// NO `arp -a` shell-out (the App Sandbox kills subprocesses; that trap blocked
// System Traceroute). This file just invokes the method channel and normalizes
// the result.
//
// PLATFORM HONESTY (GL-005 / GL-008):
//  - macOS: invoke the channel; surface whatever the kernel returned, including
//    a clear "sandbox blocked it" state when sysctl fails (EPERM/empty).
//  - iOS / Android / Windows / web: a sandboxed app on those targets cannot
//    read the ARP table, so the reader returns a clean `unavailable` result
//    with a reason. Nothing is faked. (Windows would use a different native
//    API — out of scope for this macOS-focused gate; TICKET-HSD-02.)
//
// The reader is an injectable seam (mirrors MulticastLock / MdnsBrowser) so the
// engine and the IP→MAC mapping logic stay unit-testable with no platform
// channel and no real network.

import 'dart:io';

import 'package:flutter/services.dart';

/// One IP → MAC entry read from the ARP cache. Plain data; pure.
class ArpEntry {
  const ArpEntry({required this.ip, required this.mac});

  /// IPv4 dotted-quad.
  final String ip;

  /// Lower-case colon-separated MAC (e.g. `b8:27:eb:01:23:45`).
  final String mac;
}

/// The structured outcome of one ARP-cache read. Always returned — never
/// thrown — so the debug screen renders one consistent surface and can tell
/// "sandbox blocked it" apart from "cache was empty".
class ArpReadResult {
  const ArpReadResult({
    required this.available,
    this.entries = const <ArpEntry>[],
    this.error,
  });

  /// An unavailable result for a platform that cannot read the ARP table, with
  /// an honest reason.
  const ArpReadResult.unavailable(String reason)
      : available = false,
        entries = const <ArpEntry>[],
        error = reason;

  /// True when the underlying read SUCCEEDED. Note: `available == true` with an
  /// empty [entries] list is a valid result (the cache was warm for no hosts),
  /// NOT a failure — distinct from `available == false` (the read itself was
  /// blocked or errored).
  final bool available;

  /// IP → MAC entries actually present in the cache. Empty when the cache held
  /// none, or when [available] is false.
  final List<ArpEntry> entries;

  /// Short, user-facing reason when [available] is false (e.g. an EPERM string
  /// under sandbox, or "not supported on this platform"). Null on success.
  final String? error;

  /// Convenience IP → MAC map for folding onto host records.
  Map<String, String> get byIp => <String, String>{
        for (final ArpEntry e in entries) e.ip: e.mac,
      };
}

/// Reads the platform ARP cache. Injectable so tests supply a fake.
abstract interface class ArpReader {
  /// Reads the cache. Never throws. MUST be called AFTER the connect-scan, so
  /// the cache is warm for the hosts just probed.
  Future<ArpReadResult> read();
}

/// The reader for platforms that cannot read the ARP table from a sandboxed
/// app (iOS, Android, web — and any non-macOS desktop for this spike). Returns
/// a clean unavailable result; never fabricates a MAC.
class UnavailableArpReader implements ArpReader {
  const UnavailableArpReader(this._reason);

  final String _reason;

  @override
  Future<ArpReadResult> read() async => ArpReadResult.unavailable(_reason);
}

/// macOS reader over the `com.wlanpros.toolbox/arp_table` method channel
/// (Swift sysctl read). Any channel failure becomes an honest unavailable
/// result rather than a thrown exception, so the gate stays interpretable.
class MethodChannelArpReader implements ArpReader {
  const MethodChannelArpReader();

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/arp_table');

  @override
  Future<ArpReadResult> read() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('readArpTable');
      return parsePayload(raw);
    } on MissingPluginException {
      return const ArpReadResult.unavailable(
        'ARP channel not registered (native side missing).',
      );
    } on PlatformException catch (e) {
      return ArpReadResult.unavailable('ARP read error: ${e.message ?? e.code}');
    } catch (e) {
      return ArpReadResult.unavailable('ARP read failed: $e');
    }
  }

  /// Parse the Swift payload `{available, entries:[{ip,mac}], error}` into an
  /// [ArpReadResult]. Pure (no channel) so it is unit-testable with a literal
  /// map shaped like the platform-channel response.
  static ArpReadResult parsePayload(Object? raw) {
    if (raw is! Map) {
      return const ArpReadResult.unavailable(
        'ARP read returned an unexpected payload.',
      );
    }
    final bool available = raw['available'] == true;
    if (!available) {
      final Object? err = raw['error'];
      return ArpReadResult.unavailable(
        err is String && err.isNotEmpty
            ? 'ARP read unavailable (sandbox-blocked): $err'
            : 'ARP read unavailable (sandbox-blocked).',
      );
    }
    final List<ArpEntry> entries = <ArpEntry>[];
    final Object? rawEntries = raw['entries'];
    if (rawEntries is List) {
      for (final Object? item in rawEntries) {
        if (item is Map) {
          final Object? ip = item['ip'];
          final Object? mac = item['mac'];
          if (ip is String && mac is String && ip.isNotEmpty && mac.isNotEmpty) {
            entries.add(ArpEntry(ip: ip, mac: mac.toLowerCase()));
          }
        }
      }
    }
    return ArpReadResult(available: true, entries: entries);
  }
}

/// Picks the right reader for the current platform. macOS gets the real sysctl
/// channel; every other platform gets an honest unavailable reader (web is
/// excluded from dart:io Platform checks, so it is handled first).
ArpReader platformArpReader() {
  // Web has no dart:io Platform; the engine never runs there (kIsWeb guard in
  // the debug screen), but be defensive.
  if (Platform.isMacOS) return const MethodChannelArpReader();
  if (Platform.isIOS) {
    return const UnavailableArpReader(
      'iOS sandbox cannot read the ARP table — MAC/vendor is desktop-only.',
    );
  }
  if (Platform.isAndroid) {
    return const UnavailableArpReader(
      'Android sandbox cannot read the ARP table — MAC/vendor is desktop-only.',
    );
  }
  // Windows/Linux: a different native API (GetIpNetTable / /proc/net/arp) would
  // be needed; out of scope for this macOS-focused gate (TICKET-HSD-02).
  return const UnavailableArpReader(
    'ARP read not implemented on this platform in the spike.',
  );
}
