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
// ============================================================================
// ROUND 4 (2026-07-13): ASK iOS THE QUESTION. STOP INFERRING IT FROM ADDRESSES.
// ============================================================================
//
// For three rounds this service answered "is the device on Wi-Fi?" by asking
// `network_info_plus` for an IP ADDRESS and inferring the link from whether one
// came back. That was the wrong question, and EVERY bug in rounds 2 and 3 was a
// consequence of asking it:
//
//   * The plugin's interface filter is `strncmp(name, "en", 2)`. It is not
//     Wi-Fi-specific — it matches ANY `en*` interface, including the `en*` a
//     USB-tethered iPhone brings up — and it returns the FIRST match.
//   * `getWifiIPv6()` therefore hands back the interface's LINK-LOCAL `fe80::`,
//     so round 2's "routable IPv6" check was dead code and declared a phone on an
//     IPv6-only SSID to be off Wi-Fi WHILE ON WI-FI.
//   * Round 3 fixed that by widening the ambiguity, which left three known holes
//     open: IPv6-only SSID, USB tether, and Personal Hotspot.
//
// iOS answers the actual question directly, and has since iOS 12. `NWPathMonitor`
// reports the interface TYPES a network path runs over, and `nw_interface_type_wifi`
// is a DISTINCT type from `nw_interface_type_cellular` and `nw_interface_type_wired`
// (pinned in the SDK: Network.framework/Headers/interface.h:47-52 — "A Wi-Fi
// link"). It requires no entitlement and no Location grant. A USB `en*` is
// `.wiredEthernet`, not `.wifi`, so it cannot be mistaken for a Wi-Fi link. An
// IPv6-only SSID is still a Wi-Fi path, so it reads as Wi-Fi.
//
// So the NATIVE PATH IS NOW THE PRIMARY SIGNAL. The address probe is kept ONLY as
// the FALLBACK for where the native answer is unavailable (every non-iOS platform,
// and an iOS read that times out or fails). The fail-safe `unknown` architecture
// is UNCHANGED and still governs both paths.
//
// WHAT WAS MEASURED, AND WHAT WAS NOT (the last three rounds each shipped a
// comment asserting a property nobody had demonstrated, and each one became the
// finding — so this block is explicit about the line between the two):
//
//   MEASURED (2026-07-13, a live NWPathMonitor run against the real Network
//   framework on macOS 15; the same framework and the same C API iOS uses):
//     * On an ASSOCIATED Wi-Fi link — default path `status = satisfied`,
//       `usesInterfaceType(.wifi) = true`, `availableInterfaces = [en0:wifi]`.
//       This held while `networksetup` simultaneously reported "You are not
//       associated with an AirPort network" (the Location-gated SSID read coming
//       back empty). The path monitor is definitive exactly where the SSID read is
//       blind — which is the whole point.
//     * For an interface that CANNOT CARRY A PATH (`requiredInterfaceType:
//       .wiredEthernet` on a machine with no wired NIC) — `status = unsatisfied`,
//       `usesInterfaceType = false`, `availableInterfaces = []`. That is the shape
//       an iPhone's Wi-Fi path takes with the radio off, and the ONLY shape this
//       service reads as `notOnWifi`.
//
//   NOT MEASURED — no iPhone was in this loop. The behavior on a real device, on a
//   powered-but-unassociated Wi-Fi radio, and while hosting a Personal Hotspot is
//   REASONED, not demonstrated. That is why every ambiguous shape below resolves
//   to `unknown`: an unmeasured shape degrades to the caller's PRIOR behavior (a
//   possible stale reading), never to a false "you have no Wi-Fi". See KNOWN
//   LIMITS.
//
// THE DECISION TABLE (primary — the native path, every platform that answers):
//
//   | Native facts                                          | Verdict     |
//   |-------------------------------------------------------|-------------|
//   | default route runs over Wi-Fi (`usesWifi`)             | `onWifi`    |
//   | a Wi-Fi-required path is satisfied (`wifiSatisfied`)   | `onWifi`    |
//   | a Wi-Fi interface is present but carries no route      | `unknown`   |
//   | no Wi-Fi interface, no Wi-Fi route                     | `notOnWifi` |
//   | the platform did not answer (null)                     | ↓ fallback  |
//
// THE DECISION TABLE (fallback — the address probe; iOS-only for the negative):
//
//   | Device state              | IPv4    | IPv6 on en*   | Verdict      |
//   |---------------------------|---------|---------------|--------------|
//   | Normal Wi-Fi              | present | any           | `onWifi`     |
//   | Cellular only / Wi-Fi off | null    | NONE          | `notOnWifi`  |
//   | IPv6-only Wi-Fi, joined   | null    | any (fe80/GUA)| `unknown`    |
//
//   THREE HONEST STATES — never fake a value:
//     * onWifi    — a positive association signal: the native path runs over Wi-Fi,
//                   a caller-supplied native SSID, or a Wi-Fi IPv4 address.
//     * notOnWifi — the native path reports NO Wi-Fi interface at all; or (fallback,
//                   iOS only) the Wi-Fi interface carries NO ADDRESS OF EITHER
//                   FAMILY.
//     * unknown   — the state could not be determined: a read threw, the platform
//                   cannot answer, or the evidence is AMBIGUOUS. The caller treats
//                   `unknown` as "carry on as before", NEVER as "not on Wi-Fi".
//
//   GL-005: a null/ambiguous read resolves to [unknown], never to [notOnWifi].
//
// KNOWN LIMITS (stated, not hidden):
//
//   * NO iPHONE WAS IN THIS LOOP. The native path logic is compiled and its API
//     semantics were measured on the same framework on macOS, but it has NOT been
//     executed on an iOS device. The three shapes it is expected to fix — IPv6-only
//     SSID, USB tether, Personal Hotspot — are REASONED from the SDK's interface-type
//     contract, not observed on a phone. Treat them as fixed only after a device run.
//   * A POWERED-BUT-UNASSOCIATED Wi-Fi radio is expected to present no usable Wi-Fi
//     path and therefore read `notOnWifi`. If instead iOS lists the interface as
//     available, this service returns `unknown` and the caller keeps its prior
//     behavior — a possible stale reading, not a false negative. Fails safe either
//     way, by construction, which is why the unmeasured case is tolerable.
//   * HOSTING A PERSONAL HOTSPOT may present a satisfied Wi-Fi path (the phone's own
//     AP interface). If it does, this reads `onWifi`. That is the SAME answer the old
//     address probe gave (the hotspot interface carries 172.20.10.1), so it is not a
//     regression — but it is not a proven fix either, and it is not claimed as one.
//   * WHERE THE NATIVE PATH IS UNAVAILABLE the fallback's older limits still apply in
//     full: on an IPv6-only SSID the address probe returns `unknown`, not `onWifi`,
//     so a live surface may still show a STALE reading there. This is the cost of the
//     fallback, and it is strictly better than telling a connected user they have no
//     Wi-Fi.
//
// Web safety: no `dart:io`. Both probes are method-channel calls whose channels are
// absent off the supported native platforms; the calls are guarded and resolve to
// [unknown] there.

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'wifi_path_probe.dart';

/// The honest three-way Wi-Fi connection verdict. See [WifiConnectionService].
enum WifiConnectionStatus {
  /// The device is connected to a Wi-Fi network. The live read should proceed.
  onWifi,

  /// The device is demonstrably NOT on Wi-Fi (e.g. cellular-only on iOS). Drives
  /// the "Connect to a Wi-Fi network to see live Wi-Fi data" state.
  notOnWifi,

  /// The probe could not determine the state. Treated by callers as "carry on as
  /// before" — NEVER as "not on Wi-Fi" (GL-005: no false negatives from missing
  /// data).
  unknown,
}

/// Probes whether the device is connected to a Wi-Fi network, honestly.
///
/// Pure I/O, no UI. The [networkInfo] and [pathProbe] seams keep it unit-testable
/// without a live network.
class WifiConnectionService {
  WifiConnectionService({
    NetworkInfo? networkInfo,
    TargetPlatform? platformOverride,
    WifiPathProbe? pathProbe,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _platform = platformOverride ?? defaultTargetPlatform,
        _pathProbe = pathProbe ?? const MethodChannelWifiPathProbe();

  final NetworkInfo _networkInfo;
  final TargetPlatform _platform;
  final WifiPathProbe _pathProbe;

  /// Reads the current Wi-Fi connection status.
  ///
  /// [nativeSsid] is an optional caller-supplied SSID from a native read
  /// (NEHotspotNetwork on iOS, CoreWLAN on macOS). A non-empty value is a
  /// DEFINITIVE [WifiConnectionStatus.onWifi] — a resolved SSID can only come
  /// from an active Wi-Fi association. Its ABSENCE is NOT used to assert
  /// `notOnWifi` (it can be null because Location is ungranted, not because Wi-Fi
  /// is off).
  Future<WifiConnectionStatus> status({String? nativeSsid}) async {
    // A resolved native SSID proves an active Wi-Fi join — strongest positive.
    if (nativeSsid != null && nativeSsid.trim().isNotEmpty) {
      return WifiConnectionStatus.onWifi;
    }

    // ========================================================================
    // PRIMARY: ask iOS what interface the path actually runs over.
    //
    // iOS ONLY, because the channel is iOS-only: `WifiSecurityChannel` is
    // registered in ios/Runner/AppDelegate.swift and NOWHERE else. On every other
    // platform the call is a guaranteed MissingPluginException, so skipping it is
    // not an optimization, it is the removal of a round-trip that cannot succeed.
    // (When macOS gains a path channel, widen this gate — and delete this note.)
    // ========================================================================
    final WifiPathFacts? path =
        _platform == TargetPlatform.iOS ? await _pathProbe.read() : null;
    if (path != null) {
      // The default route runs over Wi-Fi, or a Wi-Fi-required path has a usable
      // route. Either is a definitive association — a device cannot route over a
      // Wi-Fi interface it is not joined to.
      if (path.usesWifi || path.wifiSatisfied) {
        return WifiConnectionStatus.onWifi;
      }
      // A Wi-Fi interface exists on the path but carries no usable route. Could be
      // a captive portal mid-join, a radio powered but unassociated, or a hotspot
      // the phone is hosting rather than joined to. AMBIGUOUS — refuse to guess.
      if (path.wifiInterfacePresent) {
        return WifiConnectionStatus.unknown;
      }
      // No Wi-Fi interface on the path at all, and no satisfiable Wi-Fi route.
      // This is the cellular-only / radio-off device the probe exists for, and
      // it is the one Keith hit. Note this needs NO platform gate: the native
      // channel only answers where it is registered.
      return WifiConnectionStatus.notOnWifi;
    }

    // ========================================================================
    // FALLBACK: the address probe. Reached only where the native path did not
    // answer — every non-iOS platform, and an iOS read that timed out or failed.
    // Its limits are real and are documented in KNOWN LIMITS above.
    // ========================================================================
    final ({String? ip, bool threw}) v4 = await _readWifiIp();
    if (v4.threw) {
      // The read FAILED (denied permission / unsupported platform). Ambiguous,
      // never a positive not-on-Wi-Fi signal (GL-005).
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

    // iOS, no Wi-Fi IPv4, and the native path did not answer. The IPv6 read
    // answers exactly one question, and only its NEGATIVE answer is trustworthy:
    // "does the Wi-Fi interface carry ANY address at all?"
    //
    //   * NO  → the interface has no active link. That is the cellular-only /
    //           radio-off device, and the ONLY shape that may assert `notOnWifi`.
    //   * YES → SOMETHING is on the interface, but an IPv6-only association cannot
    //           be told from an idle interface holding a link-local. Refuse to
    //           guess: `unknown` keeps the caller's prior behavior.
    final ({bool present, bool threw}) v6 = await _readWifiIpv6();
    if (v6.threw) {
      // The IPv6 read failed, so "no Wi-Fi address at all" is unproven.
      return WifiConnectionStatus.unknown;
    }
    if (v6.present) {
      return WifiConnectionStatus.unknown;
    }

    // No IPv4 and NO IPv6 anywhere on the Wi-Fi interface: it has no active link.
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
      debugPrint('WifiConnectionService.getWifiIP failed: $e');
      return (ip: null, threw: true);
    }
  }

  /// Whether the Wi-Fi interface carries ANY IPv6 address.
  ///
  /// DELIBERATELY UNCLASSIFIED. The plugin returns the FIRST AF_INET6 address on
  /// `en*`, which is the LINK-LOCAL, so classifying it cannot prove association.
  /// This reports PRESENCE only, and the caller uses only the negative: no address
  /// of either family ⇒ no active link ⇒ `notOnWifi`. Any address ⇒ `unknown`.
  ///
  /// The all-zeros IPv6 placeholder (`::`, and its `0:0:0:0:0:0:0:0` long form) is
  /// normalized to "absent", exactly as [_readWifiIp] normalizes `0.0.0.0` — an
  /// unspecified address is not an address, and reading it as one would suppress a
  /// legitimate `notOnWifi` on a cellular-only phone.
  ///
  /// [present] is false for a null/blank/all-zeros read. [threw] == true means the
  /// read itself failed, which the caller must resolve to `unknown` — never
  /// `notOnWifi`.
  Future<({bool present, bool threw})> _readWifiIpv6() async {
    try {
      final String? v = await _networkInfo.getWifiIPv6();
      if (v == null) return (present: false, threw: false);
      final String t = v.trim();
      if (t.isEmpty || _isUnspecifiedIpv6(t)) {
        return (present: false, threw: false);
      }
      return (present: true, threw: false);
    } on Object catch (e) {
      debugPrint('WifiConnectionService.getWifiIPv6 failed: $e');
      return (present: false, threw: true);
    }
  }

  /// True for the IPv6 unspecified address in any spelling: `::`, the fully
  /// expanded `0:0:0:0:0:0:0:0`, and zero-padded forms. Case-insensitive, and any
  /// zone suffix (`%en0`) is stripped first.
  static bool _isUnspecifiedIpv6(String raw) {
    final String addr = raw.split('%').first.trim();
    if (addr.isEmpty) return false;
    if (addr == '::') return true;
    // Every group must be present and zero. `::` shorthand anywhere else (e.g.
    // `::1`, the loopback) has a non-zero group and is correctly NOT unspecified.
    final List<String> groups = addr.split(':');
    bool sawDigit = false;
    for (final String g in groups) {
      if (g.isEmpty) continue; // the `::` elision
      sawDigit = true;
      if (int.tryParse(g, radix: 16) != 0) return false;
    }
    return sawDigit;
  }
}
