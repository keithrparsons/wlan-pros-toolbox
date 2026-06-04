// System Uptime bridge — Dart side of the tiny native uptime channel.
//
// No Flutter package exposes "seconds since boot", so this reads
// `ProcessInfo.processInfo.systemUptime` (iOS + macOS) over a minimal
// MethodChannel. The native glue mirrors the existing app-owned channels
// (ArpTableChannel on macOS, the Shortcuts bridge on iOS): a single method,
// no event stream, no entitlement, unprivileged.
//
//   channel: com.wlanpros.toolbox/system_info
//   method : systemUptime → Double (seconds since last boot)
//
// HONESTY (GL-005 / GL-008): off-iOS/macOS the channel has no handler, so the
// call throws MissingPluginException and [read] returns null — the screen then
// renders the honest "Not available on this platform" row, never a fake 0.
// A negative or non-finite native value is also treated as unavailable.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges the native `systemUptime` read to Dart. Returns seconds since the
/// device last booted, or null where the platform does not answer.
class SystemUptimeBridge {
  SystemUptimeBridge({MethodChannel? methodChannel})
      : _method = methodChannel ??
            const MethodChannel('com.wlanpros.toolbox/system_info');

  final MethodChannel _method;

  /// Reads the device uptime in seconds since boot, or null when the platform
  /// has no handler (non-iOS/macOS, or the runner is not yet built) or returns
  /// a value that is not a finite, non-negative number. Never throws.
  Future<double?> read() async {
    try {
      final double? seconds =
          await _method.invokeMethod<double>('systemUptime');
      if (seconds == null || !seconds.isFinite || seconds < 0) return null;
      return seconds;
    } on MissingPluginException {
      // Channel not registered (non-iOS/macOS, or runner not yet built). Honest.
      return null;
    } on PlatformException catch (e) {
      debugPrint('SystemUptimeBridge.read failed: $e');
      return null;
    }
  }
}
