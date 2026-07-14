// WifiConnectionService — the honest "is this device on Wi-Fi?" probe.
//
// WHY THIS EXISTS (2026-06-25, Keith): a user spent hours debugging "no live
// data" in Wi-Fi Information / Test My Connection when the real cause was simply
// that the iPhone was on CELLULAR, not Wi-Fi. The live surfaces showed nothing
// (or a perpetual "Waiting for the first reading…") and gave no hint. Every
// tester on cellular, or stuck on a half-joined captive portal, hits the same
// wall. This service surfaces a clear, honest "you're not connected to Wi-Fi"
// state so the live tools stop looking broken when the device is off Wi-Fi.
//
// THE SIGNALS, AND WHAT EACH ONE ACTUALLY PROVES:
//
//   1. A resolved native SSID (NEHotspotNetwork / CoreWLAN, caller-supplied).
//      A resolved SSID can only come from an active association → DEFINITIVE
//      `onWifi`. Its ABSENCE proves nothing (it is null whenever Location is
//      ungranted), so it is never used to assert `notOnWifi`.
//
//   2. `network_info_plus.getWifiIP()` — a NATIVE method-channel call, not a
//      subprocess, so it is safe in the sandboxed macOS/iOS builds (GL-008).
//      A non-empty address means the Wi-Fi interface is up and addressed →
//      `onWifi`, and it needs no Location grant.
//
//      IT ENUMERATES IPv4 ONLY. Verified in the plugin source at
//      network_info_plus-6.1.4/ios/network_info_plus/Sources/network_info_plus/
//      FPPNetworkInfoPlusPlugin.m:68 — `getWifiIP` calls
//      `enumerateWifiAddresses:AF_INET`. An iPhone joined to an IPv6-ONLY Wi-Fi
//      network (NAT64/DNS64 — common on carrier and CONFERENCE SSIDs) therefore
//      gets a CLEAN NULL here while fully associated. A null IPv4 alone is NOT
//      proof of "no Wi-Fi", and treating it as proof declared a device
//      NOT-ON-WI-FI WHILE ON WI-FI (cold-eyes review, 2026-07-13, F3).
//
//   3. `network_info_plus.getWifiIPv6()` — the same native call over AF_INET6
//      (same file, :78, same `en*`-interface filter; the Dart side maps to the
//      `wifiIPv6Address` method channel). This is what closes the IPv6-only gap:
//      a ROUTABLE IPv6 address on the Wi-Fi interface is an active Wi-Fi join.
//
//   THREE HONEST STATES — never fake a value:
//     * onWifi    — a positive association signal: a caller-supplied native SSID,
//                   a Wi-Fi IPv4 address, or a routable Wi-Fi IPv6 address.
//     * notOnWifi — iOS ONLY, and ONLY when BOTH address families come back clean
//                   and empty: no Wi-Fi IPv4 AND no routable Wi-Fi IPv6. iOS
//                   surfaces no wired Ethernet to confuse this, so that pair is
//                   the honest cellular-only / radio-off signal.
//     * unknown   — the state could not be determined: a read threw (denied
//                   permission / absent method channel), or the platform cannot
//                   answer (a wired-only Mac legitimately has no Wi-Fi IP). The
//                   caller treats `unknown` as "carry on as before", NEVER as
//                   "not on Wi-Fi".
//
//   GL-005: a null/ambiguous read resolves to [unknown], never to [notOnWifi].
//   `notOnWifi` is only ever returned from reads that SUCCEEDED and came back
//   empty on both address families.
//
// KNOWN LIMITS OF THE NEGATIVE VERDICT (stated, not hidden — the previous round
// shipped a comment claiming this "can never over-suppress", which is exactly how
// the IPv6 hole survived review):
//
//   * A link-local-only IPv6 (`fe80::/10`) on the Wi-Fi interface is deliberately
//     NOT counted as a positive on-Wi-Fi signal. A link-local address is
//     self-assigned and does not prove an association with a working network, and
//     an idle/unassociated interface can carry one. Counting it would make
//     `notOnWifi` unreachable and re-open the stale-reading bug this probe exists
//     to close. The cost: a Wi-Fi network that hands out NO IPv4 and NO routable
//     IPv6 (a broken or entirely un-provisioned SSID) reads as `notOnWifi`. On
//     such a network there is no working Wi-Fi path anyway, and a resolved native
//     SSID (signal 1) still overrides to `onWifi` when Location is granted.
//   * If a future plugin/OS revision stops answering `wifiIPv6Address`, the read
//     throws and every iOS verdict degrades to `unknown` — the live tools revert
//     to their pre-2026-07-13 behavior rather than making a false claim.
//
// Web safety: no `dart:io`. `network_info_plus` is a method-channel plugin whose
// channel is absent off the supported native platforms; the calls are guarded and
// resolve to [unknown] there. The screens only construct this behind their
// existing platform gates regardless.

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// The honest three-way Wi-Fi connection verdict. See [WifiConnectionService].
enum WifiConnectionStatus {
  /// The device is connected to a Wi-Fi network (an active Wi-Fi IPv4 address, a
  /// routable Wi-Fi IPv6 address, or a caller-supplied native SSID). The live
  /// read should proceed.
  onWifi,

  /// The device is demonstrably NOT on Wi-Fi (e.g. cellular-only on iOS): BOTH
  /// address families read clean and empty. Drives the "Connect to a Wi-Fi
  /// network to see live Wi-Fi data" state.
  notOnWifi,

  /// The probe could not determine the state. Treated by callers as "carry on as
  /// before" — NEVER as "not on Wi-Fi" (GL-005: no false negatives from missing
  /// data).
  unknown,
}

/// Probes whether the device is connected to a Wi-Fi network, honestly.
///
/// Pure I/O, no UI. The [networkInfo] seam keeps it unit-testable without a live
/// network. Construct it behind the same platform gate the live Wi-Fi surfaces
/// already sit behind.
class WifiConnectionService {
  WifiConnectionService({
    NetworkInfo? networkInfo,
    TargetPlatform? platformOverride,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _platform = platformOverride ?? defaultTargetPlatform;

  final NetworkInfo _networkInfo;
  final TargetPlatform _platform;

  /// Reads the current Wi-Fi connection status.
  ///
  /// [nativeSsid] is an optional caller-supplied SSID from a native read
  /// (NEHotspotNetwork on iOS, CoreWLAN on macOS). A non-empty value is a
  /// DEFINITIVE [WifiConnectionStatus.onWifi] — a resolved SSID can only come
  /// from an active Wi-Fi association. Its ABSENCE is NOT used to assert
  /// `notOnWifi` (it can be null because Location is ungranted, not because Wi-Fi
  /// is off), so the negative verdict rests solely on the permission-free
  /// Wi-Fi-address signals below.
  Future<WifiConnectionStatus> status({String? nativeSsid}) async {
    // A resolved native SSID proves an active Wi-Fi join — strongest positive.
    if (nativeSsid != null && nativeSsid.trim().isNotEmpty) {
      return WifiConnectionStatus.onWifi;
    }

    final ({String? ip, bool threw}) v4 = await _readWifiIp();
    if (v4.threw) {
      // The read FAILED (denied permission / unsupported platform). That is
      // ambiguous, never a positive not-on-Wi-Fi signal — resolve to `unknown`
      // so a denied read is NEVER surfaced as a false "not on Wi-Fi" (GL-005).
      return WifiConnectionStatus.unknown;
    }
    if (v4.ip != null) {
      // An active Wi-Fi interface has an IPv4 address: on Wi-Fi.
      return WifiConnectionStatus.onWifi;
    }

    // No Wi-Fi IPv4 from a SUCCESSFUL read. Whether that can EVER prove "not on
    // Wi-Fi" depends on the platform:
    //   * iOS: no wired Ethernet exists to confuse the read, so an empty Wi-Fi
    //     interface is meaningful — but see the IPv6 check below, because the
    //     IPv4 read alone is blind to an IPv6-only SSID.
    //   * Everywhere else: an empty Wi-Fi IPv4 is AMBIGUOUS (a wired-only Mac, a
    //     desktop with Wi-Fi off, a platform that does not report the Wi-Fi IP),
    //     so we resolve to `unknown` rather than falsely tell a wired user to
    //     "connect to Wi-Fi" (GL-005).
    if (_platform != TargetPlatform.iOS) {
      return WifiConnectionStatus.unknown;
    }

    // iOS, no Wi-Fi IPv4. THE SECOND ADDRESS FAMILY DECIDES IT (cold-eyes F3).
    // `getWifiIP()` enumerates AF_INET only, so an iPhone on an IPv6-only Wi-Fi
    // network (NAT64/DNS64 — carrier and CONFERENCE SSIDs) reaches this line
    // while fully associated. Asserting `notOnWifi` here would blank a live
    // Wi-Fi link, tear down its stream, and tell a connected user they are not
    // connected. Require the IPv6 family to ALSO come back empty.
    final ({String? ip, bool threw}) v6 = await _readWifiIpv6();
    if (v6.threw) {
      // The IPv6 read failed, so "no Wi-Fi address at all" is unproven. Honest
      // answer: unknown. Callers keep their prior behavior; nothing is blanked.
      return WifiConnectionStatus.unknown;
    }
    if (v6.ip != null) {
      // A routable IPv6 address on the Wi-Fi interface: the device IS associated.
      return WifiConnectionStatus.onWifi;
    }

    // Both families read clean and empty on iOS: no Wi-Fi link. This is the
    // cellular-only case the probe exists for.
    return WifiConnectionStatus.notOnWifi;
  }

  /// Reads the Wi-Fi IPv4 address, normalizing the "no address" placeholders to
  /// null.
  ///
  /// Returns a record so the caller can tell a CLEAN null (the read succeeded but
  /// there is no Wi-Fi IPv4 address) apart from a FAILED read ([threw] == true:
  /// denied permission / absent method channel). A failed read is always
  /// `unknown` (GL-005: a denied/errored read is never a false negative).
  Future<({String? ip, bool threw})> _readWifiIp() async {
    try {
      final String? v = await _networkInfo.getWifiIP();
      if (v == null) return (ip: null, threw: false);
      final String t = v.trim();
      // Guard against the all-zeros placeholder some platforms return for "no
      // address" — treat it as null (no Wi-Fi IP), never as a real address.
      if (t.isEmpty || t == '0.0.0.0') return (ip: null, threw: false);
      return (ip: t, threw: false);
    } on Object catch (e) {
      // A denied permission / unsupported platform throws; report the failure so
      // the caller resolves to `unknown`, never a false `notOnWifi`.
      debugPrint('WifiConnectionService.getWifiIP failed: $e');
      return (ip: null, threw: true);
    }
  }

  /// Reads the Wi-Fi IPv6 address, keeping ONLY a ROUTABLE one.
  ///
  /// [ip] is non-null only for an address that proves an active Wi-Fi join:
  /// link-local (`fe80::/10`), loopback (`::1`), and the unspecified address
  /// (`::`) are discarded to null (see [isRoutableIpv6] and the KNOWN LIMITS note
  /// at the top of this file). [threw] == true means the read itself failed, which
  /// the caller must resolve to `unknown` — never to `notOnWifi`.
  Future<({String? ip, bool threw})> _readWifiIpv6() async {
    try {
      final String? v = await _networkInfo.getWifiIPv6();
      if (v == null) return (ip: null, threw: false);
      final String t = v.trim();
      if (t.isEmpty || !_isRoutableIpv6(t)) return (ip: null, threw: false);
      return (ip: t, threw: false);
    } on Object catch (e) {
      debugPrint('WifiConnectionService.getWifiIPv6 failed: $e');
      return (ip: null, threw: true);
    }
  }

  /// Whether [raw] is an IPv6 address that PROVES an active Wi-Fi association.
  ///
  /// False for the unspecified address (`::`), loopback (`::1`), and link-local
  /// (`fe80::/10`, i.e. first hextet `fe80`–`febf`, with any `%zone` suffix
  /// stripped first). Everything else — a global unicast (`2000::/3`) or a ULA
  /// (`fc00::/7`) — is a real, provisioned address on the Wi-Fi interface and is
  /// treated as a positive on-Wi-Fi signal.
  ///
  /// Visible for testing: the IPv6-only-Wi-Fi case (F3) is asserted against this
  /// classification directly, not only through the plugin seam.
  @visibleForTesting
  static bool isRoutableIpv6(String raw) => _isRoutableIpv6(raw);

  static bool _isRoutableIpv6(String raw) {
    String s = raw.trim().toLowerCase();
    if (s.isEmpty) return false;
    // Strip any scope/zone identifier: `fe80::1c9a:...%en0`.
    final int zone = s.indexOf('%');
    if (zone >= 0) s = s.substring(0, zone);
    if (s.isEmpty) return false;
    if (s == '::' || s == '::1') return false;
    // fe80::/10 → the first hextet runs fe80..febf.
    if (s.startsWith('fe8') ||
        s.startsWith('fe9') ||
        s.startsWith('fea') ||
        s.startsWith('feb')) {
      return false;
    }
    return true;
  }
}
