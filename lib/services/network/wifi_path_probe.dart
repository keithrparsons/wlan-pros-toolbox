// WifiPathProbe — the RAW facts iOS reports about the device's network path.
//
// The native side (ios/Runner/WifiSecurityChannel.swift, `WifiPathMonitor`) runs
// an `NWPathMonitor` and hands back three booleans. It decides NOTHING. The
// decision table lives in [WifiConnectionService], in Dart, where every branch is
// unit-tested and mutation-proven — deliberately, because a decision made in the
// native channel is a decision made in the one place the test suite cannot reach.
//
// PERMISSION-FREE. Unlike the NEHotspotNetwork read on the same channel
// (`getSecurityInfo`), the path monitor needs no Access-Wi-Fi-Information
// entitlement and no Location grant. `nw_interface_type_wifi` is its own interface
// type, distinct from `_cellular` and `_wired` (SDK: Network.framework
// Headers/interface.h:47-52), so a USB-tethered `en*` cannot be mistaken for Wi-Fi
// the way the `network_info_plus` address probe mistakes it.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The raw path facts. No interpretation; see [WifiConnectionService] for the
/// decision table that reads them.
@immutable
class WifiPathFacts {
  const WifiPathFacts({
    required this.usesWifi,
    required this.wifiSatisfied,
    required this.wifiInterfacePresent,
  });

  /// The DEFAULT route currently runs over a Wi-Fi interface
  /// (`nw_path_uses_interface_type(path, nw_interface_type_wifi)`). A definitive
  /// positive: the device cannot route over Wi-Fi without being associated.
  final bool usesWifi;

  /// A Wi-Fi-REQUIRED path has a usable route
  /// (`NWPathMonitor(requiredInterfaceType: .wifi).status == .satisfied`). Also a
  /// definitive positive, and it still holds when the default route runs
  /// elsewhere (a phone on Wi-Fi that is also up on cellular).
  final bool wifiSatisfied;

  /// A Wi-Fi interface appears on either path at all. NOT a positive — it is the
  /// AMBIGUITY flag. True with neither of the above means "something Wi-Fi-shaped
  /// is up but is not carrying a usable route", which the decision table refuses
  /// to resolve either way.
  final bool wifiInterfacePresent;

  @override
  String toString() => 'WifiPathFacts(usesWifi: $usesWifi, '
      'wifiSatisfied: $wifiSatisfied, '
      'wifiInterfacePresent: $wifiInterfacePresent)';
}

/// Reads [WifiPathFacts] from the platform. The seam that keeps the decision
/// table testable without a device.
abstract class WifiPathProbe {
  /// The current path facts, or null when the platform cannot answer (the channel
  /// is absent off iOS, the native monitor timed out, the payload was malformed).
  ///
  /// Null is NOT a negative verdict. The caller falls back to its secondary
  /// signal; it never reads null as "not on Wi-Fi" (GL-005).
  Future<WifiPathFacts?> read();
}

/// The iOS implementation, over the method channel `WifiSecurityChannel` already
/// registers. Fails to null on ANY error, never throws.
class MethodChannelWifiPathProbe implements WifiPathProbe {
  const MethodChannelWifiPathProbe({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  /// The SAME channel name `WifiSecurityChannel.swift` registers. It exists only
  /// on iOS: every other platform throws [MissingPluginException] here, which is
  /// caught and returned as null (→ the address-probe fallback).
  static const MethodChannel _defaultChannel =
      MethodChannel('com.wlanpros.toolbox/wifi_security');

  final MethodChannel _channel;

  /// A Dart-side ceiling on the native call, ABOVE the native side's own 1500ms
  /// deadline. Belt and braces: the native monitor already answers
  /// honest-unavailable if its path has not landed, but a wedged or unanswered
  /// channel must never be able to hang the Wi-Fi probe — every caller of
  /// [WifiConnectionService.status] is on a screen's load path. On timeout we
  /// return null (→ the address-probe fallback), never a verdict.
  static const Duration _deadline = Duration(seconds: 3);

  @override
  Future<WifiPathFacts?> read() async {
    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>('getWifiPath')
          .timeout(_deadline, onTimeout: () => null);
      if (payload == null) return null;
      // The native side answers `available: false` when its monitors had not
      // reported a path before the deadline. Honest-unavailable, not a verdict.
      if (payload['available'] != true) return null;
      return WifiPathFacts(
        usesWifi: payload['usesWifi'] == true,
        wifiSatisfied: payload['wifiSatisfied'] == true,
        wifiInterfacePresent: payload['wifiInterfacePresent'] == true,
      );
    } on Object catch (e) {
      // MissingPluginException off iOS, or any platform error. Never a verdict.
      debugPrint('WifiPathProbe.getWifiPath failed: $e');
      return null;
    }
  }
}
