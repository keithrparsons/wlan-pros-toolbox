// NetworkTransportProbe — the RAW facts ANDROID reports about which transport the
// device's ACTIVE network runs over.
//
// WHY THIS EXISTS (round-4 cold review, ANDROID GATE, 2026-07-14).
//
// The cellular-data consent gate shipped iOS-only, and NOT by design — by
// STRUCTURE. `WifiConnectionService` could not return `notOnWifi` off iOS at all
// (`if (_platform != TargetPlatform.iOS) return unknown`), so on Android —
// LIVE on Google Play, and the one platform where "on cellular" is the DEFAULT
// assumption — `notOnWifi` was UNREACHABLE, `spendData` was unconditionally true,
// and the home hero's `autoStart: true` push ran a full ~30 s throughput measure
// plus the RPM load generator (50-500 MB) with ZERO taps and nothing to consent to.
//
// THE DISTINCTION THAT DECIDES THIS DESIGN: that was "WE NEVER ASKED", not "WE
// CANNOT KNOW".
//
// The existing GL-005 rationale in `WifiConnectionService` — an ambiguous read is
// never proof of cellular; never nag a wired desktop — was written for platforms
// where the transport genuinely cannot be told from an IP address. IT DOES NOT
// COVER ANDROID. Android reports the transport DEFINITIVELY:
//
//     ConnectivityManager.getNetworkCapabilities(activeNetwork)
//       .hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)   // and _WIFI, _ETHERNET
//
// That is a MEASURED signal from the OS about the network that is actually
// carrying the bytes, not an inference from an address. Treating a KNOWABLE fact
// as unknowable is the two-kinds-of-null error pointed the wrong way
// ([[feedback_unsourced_is_not_invalid]]): "we could not read it" and "we never
// read it" are not the same null, and only the first one licenses silence.
//
// PERMISSION-FREE, AND THAT IS VERIFIED, NOT ASSUMED. The transport TYPE of the
// active network is readable with `ACCESS_NETWORK_STATE` alone. That permission is
// `protectionLevel="normal"` (install-time; it is NOT in any runtime-permission
// group and NEVER shows a dialog), and it is ALREADY DECLARED in this app's
// AndroidManifest.xml (line 9) — it has shipped since the DNS/link-properties read
// in `MainActivity.readDnsServers()`. So this probe adds NO new permission, NO new
// dependency, and NO new user-facing prompt. The Location grant that gates SSID and
// scan results is NOT required here: we ask "what KIND of link is this", never
// "which network is it".
//
// WHY A PLATFORM CHANNEL AND NOT `connectivity_plus`: it is not in `pubspec.yaml`
// (verified, not assumed — the brief said it "may already be there"; it is not).
// Adding a plugin to reach an API this app's `MainActivity` ALREADY imports and
// calls (`ConnectivityManager`, for `readDnsServers`) would buy a six-platform
// dependency and a version-solve risk to avoid ~20 lines of Kotlin. It would also
// interpose the plugin's own coarse enum between us and the raw capability bits,
// which is exactly the layer this design refuses to add.
//
// THE NATIVE SIDE DECIDES NOTHING. It hands back four booleans. The decision table
// lives in [WifiConnectionService], in Dart, where every branch is unit-tested and
// mutation-proven — deliberately, and for the same reason `WifiPathProbe` does it:
// a decision made in the native channel is a decision made in the one place the
// test suite cannot reach.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The raw transport facts for the device's ACTIVE (default) network. No
/// interpretation; see [WifiConnectionService] for the decision table that reads
/// them.
///
/// These are the `NetworkCapabilities.hasTransport(...)` bits verbatim. More than
/// one can be true at once (a VPN whose underlying networks include both Wi-Fi and
/// cellular is the real case), and ALL can be false (no active network at all — a
/// device in airplane mode — or an exotic transport such as Bluetooth tethering or
/// USB). Neither shape is a verdict; both are facts the caller must resolve.
@immutable
class NetworkTransportFacts {
  const NetworkTransportFacts({
    required this.cellular,
    required this.wifi,
    required this.ethernet,
    required this.vpn,
  });

  /// `TRANSPORT_CELLULAR` — the active network runs over the mobile radio. The
  /// user is paying per byte. This is the ONLY signal in this codebase that can
  /// license a definitive "you are on cellular", and it is a MEASURED one.
  final bool cellular;

  /// `TRANSPORT_WIFI` — the active network runs over Wi-Fi. A definitive positive:
  /// a device cannot route over a Wi-Fi interface it is not joined to.
  final bool wifi;

  /// `TRANSPORT_ETHERNET` — a wired link (an Android TV in a rack, a tablet in a
  /// dock). NOT cellular, so it must never be nagged; NOT Wi-Fi, so it must never
  /// be reported as a Wi-Fi association either.
  final bool ethernet;

  /// `TRANSPORT_VPN` — the active network is a VPN. Android usually MERGES the
  /// underlying network's transports into the VPN network's capabilities, so a VPN
  /// over cellular normally reports `cellular: true` here as well. USUALLY is not
  /// ALWAYS (it depends on the VPN app calling `setUnderlyingNetworks`), so a VPN
  /// with NO underlying transport visible is genuinely AMBIGUOUS and the decision
  /// table resolves it to `unknown` — never to a guessed cellular.
  final bool vpn;

  @override
  String toString() => 'NetworkTransportFacts(cellular: $cellular, '
      'wifi: $wifi, ethernet: $ethernet, vpn: $vpn)';
}

/// Reads [NetworkTransportFacts] from the platform. The seam that keeps the
/// decision table testable without a device.
abstract class NetworkTransportProbe {
  /// The current transport facts, or null when the platform cannot answer (the
  /// channel is absent off Android, the read threw, the payload was malformed, the
  /// call timed out).
  ///
  /// Null is NOT a negative verdict and NOT a positive one. The caller falls back
  /// to its secondary signal; it never reads null as "on cellular" or as "on
  /// Wi-Fi" (GL-005).
  Future<NetworkTransportFacts?> read();
}

/// The Android implementation, over the method channel `MainActivity` registers.
/// Fails to null on ANY error, never throws.
class MethodChannelNetworkTransportProbe implements NetworkTransportProbe {
  const MethodChannelNetworkTransportProbe({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  /// The SAME channel name `MainActivity.kt` registers. It exists only on Android:
  /// every other platform throws [MissingPluginException] here, which is caught and
  /// returned as null (→ the caller's fallback).
  static const MethodChannel _defaultChannel =
      MethodChannel('com.wlanpros.toolbox/network_transport');

  final MethodChannel _channel;

  /// A Dart-side ceiling on the native call. `getNetworkCapabilities` is a fast,
  /// local, in-process-ish read (no radio round-trip), so this deadline should
  /// never fire — but every caller of [WifiConnectionService.status] is on a
  /// screen's load path AND on the auto-start path, and a wedged channel must never
  /// be able to hang either. On timeout we return null (→ fallback), never a
  /// verdict. Mirrors [MethodChannelWifiPathProbe]'s belt-and-braces deadline.
  static const Duration _deadline = Duration(seconds: 3);

  @override
  Future<NetworkTransportFacts?> read() async {
    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>('getTransport')
          .timeout(_deadline, onTimeout: () => null);
      if (payload == null) return null;
      // The native side answers `available: false` when it could not read the
      // capabilities at all (the service was missing, the read threw, the SDK is
      // below API 23). Honest-unavailable, not a verdict.
      if (payload['available'] != true) return null;
      return NetworkTransportFacts(
        cellular: payload['cellular'] == true,
        wifi: payload['wifi'] == true,
        ethernet: payload['ethernet'] == true,
        vpn: payload['vpn'] == true,
      );
    } on Object catch (e) {
      // MissingPluginException off Android, or any platform error. Never a verdict.
      debugPrint('NetworkTransportProbe.getTransport failed: $e');
      return null;
    }
  }
}
