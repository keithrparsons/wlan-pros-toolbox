// Wi-Fi multicast lock seam — Network Discovery (TICKET-HSD-02).
//
// On Android the mDNS browse needs a held multicast lock or inbound multicast
// frames are dropped (see MainActivity.kt + the manifest's
// CHANGE_WIFI_MULTICAST_STATE). This is the Dart side: a tiny method-channel
// call around the browse. On every other platform it is a no-op (iOS/macOS/
// Windows do not require an app-held multicast lock).
//
// The seam is injectable so the engine and the mDNS browse stay testable with
// no platform channel (a [NoopMulticastLock] in tests).

import 'dart:io';

import 'package:flutter/services.dart';

/// Acquires/releases a platform multicast lock around an mDNS browse.
abstract interface class MulticastLock {
  Future<void> acquire();
  Future<void> release();
}

/// No-op lock — the default everywhere except Android, and the test default.
class NoopMulticastLock implements MulticastLock {
  const NoopMulticastLock();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}

/// Android multicast lock over the `lan_discovery/multicast` method channel
/// wired in MainActivity.kt. Acquire failures are swallowed — a missing lock
/// just means mDNS may return nothing, which is the gate Keith validates, not
/// a crash.
class AndroidMulticastLock implements MulticastLock {
  const AndroidMulticastLock();

  static const MethodChannel _channel =
      MethodChannel('lan_discovery/multicast');

  @override
  Future<void> acquire() async {
    try {
      await _channel.invokeMethod<void>('acquire');
    } catch (_) {/* non-fatal */}
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {/* non-fatal */}
  }
}

/// Picks the right lock for the current platform.
MulticastLock platformMulticastLock() {
  if (!Platform.isAndroid) return const NoopMulticastLock();
  return const AndroidMulticastLock();
}
