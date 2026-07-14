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
//      (same file, :78, same `en*`-interface filter). It answers ONE question
//      honestly: does the Wi-Fi interface carry ANY IPv6 address at all?
//
//      IT CANNOT BE USED TO PROVE ASSOCIATION, AND THE PREVIOUS ROUND'S ATTEMPT
//      TO DO SO WAS DEAD CODE. `getWifiIPv6` keeps the FIRST AF_INET6 address it
//      finds on an `en*` interface (`if (addr) return;`, :82) and `getifaddrs()`
//      walks the kernel's address list in order — which carries the interface's
//      LINK-LOCAL `fe80::` first. MEASURED, not inferred: reproducing
//      `enumerateWifiAddresses:AF_INET6` in C against the live BSD stack on an
//      associated en0 returned `fe80::10b4:5ba5:5d42:a691%en0` (2026-07-13).
//      So this accessor hands back a link-local on an associated interface, and a
//      round-2 fix that only accepted a ROUTABLE address here discarded it and
//      returned `notOnWifi` for an associated IPv6-only device — the exact
//      failure the check was added to prevent.
//
//      The honest response is NOT to reinterpret `fe80::` as proof of
//      association (it is not: it is self-assigned, and treating it as positive
//      would make `notOnWifi` unreachable and resurrect the stale-reading bug).
//      It is to admit the read is AMBIGUOUS and return [unknown]. See the table.
//
// THE DECISION TABLE (iOS; every other platform is [unknown] on a null IPv4):
//
//   | Device state              | IPv4    | IPv6 on en*   | Verdict      |
//   |---------------------------|---------|---------------|--------------|
//   | Normal Wi-Fi              | present | any           | `onWifi`     |
//   | Cellular only / Wi-Fi off | null    | NONE          | `notOnWifi`  |
//   | IPv6-only Wi-Fi, joined   | null    | any (fe80/GUA)| `unknown`    |
//
//   THREE HONEST STATES — never fake a value:
//     * onWifi    — a positive association signal: a caller-supplied native SSID
//                   or a Wi-Fi IPv4 address.
//     * notOnWifi — iOS ONLY, and ONLY when the Wi-Fi interface carries NO
//                   ADDRESS OF EITHER FAMILY. An interface with no active link
//                   has no addresses at all (measured: on macOS every `en*` with
//                   `status: inactive` carries neither an inet nor an inet6
//                   line, while the active en0 carries both), so "no IPv4 and no
//                   IPv6 anywhere on en*" is the honest cellular-only signal.
//     * unknown   — the state could not be determined: a read threw, the platform
//                   cannot answer (a wired-only Mac legitimately has no Wi-Fi IP),
//                   or the address evidence is AMBIGUOUS (an IPv6 exists but does
//                   not prove association). The caller treats `unknown` as "carry
//                   on as before", NEVER as "not on Wi-Fi".
//
//   GL-005: a null/ambiguous read resolves to [unknown], never to [notOnWifi].
//
// KNOWN LIMITS (stated, not hidden — the previous two rounds each shipped a
// comment asserting a property that had not been proven, and each one was the
// finding):
//
//   * ON AN IPv6-ONLY WI-FI NETWORK THIS PROBE RETURNS `unknown`, NOT `onWifi`.
//     It cannot distinguish "joined an IPv6-only SSID" from "Wi-Fi radio idle but
//     still holding a link-local", because the only IPv6 the plugin will hand back
//     is the link-local in both cases. `unknown` means callers keep their PRIOR
//     behavior, so on such a network a live surface may still show a STALE
//     reading. That is the cost, and it is deliberate: it is strictly better than
//     telling a connected user they have no Wi-Fi. Closing it properly needs an
//     association signal the plugin does not expose (NEHotspotNetwork, or an
//     `SCNetworkReachability` / `NWPathMonitor` interface-type check).
//   * The `notOnWifi` verdict rests on an interface with no active link carrying
//     no addresses. That was measured on macOS `en*` interfaces (above), and the
//     mechanism is the same on iOS (the link-local is assigned at link-up), but it
//     was NOT measured on an iOS en0 with Wi-Fi switched off. If that assumption
//     is ever wrong the verdict degrades to `unknown` — a stale reading, not a
//     false "you have no Wi-Fi". The design fails safe in that direction ON
//     PURPOSE.
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
  /// The device is connected to a Wi-Fi network (an active Wi-Fi IPv4 address or
  /// a caller-supplied native SSID). The live read should proceed.
  onWifi,

  /// The device is demonstrably NOT on Wi-Fi (e.g. cellular-only on iOS): the
  /// Wi-Fi interface carries NO address of EITHER family. Drives the "Connect to
  /// a Wi-Fi network to see live Wi-Fi data" state.
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
    // connected.
    //
    // But the IPv6 read CANNOT rescue that case into `onWifi` either: the plugin
    // hands back the interface's LINK-LOCAL (measured — see the header), which
    // proves nothing about association. So this read answers exactly one
    // question, and only the NEGATIVE answer is trustworthy:
    //
    //   "Does the Wi-Fi interface carry ANY address at all?"
    //
    //   * NO  → the interface has no active link. Nothing is addressed on it, in
    //           either family. That is the cellular-only / radio-off device, and
    //           it is the ONLY shape that may assert `notOnWifi`.
    //   * YES → SOMETHING is on the interface, but we cannot tell an IPv6-only
    //           association from an idle interface holding a link-local. Refuse
    //           to guess: `unknown` keeps the caller's prior behavior and, above
    //           all, never tells a connected user they have no Wi-Fi.
    final ({bool present, bool threw}) v6 = await _readWifiIpv6();
    if (v6.threw) {
      // The IPv6 read failed, so "no Wi-Fi address at all" is unproven. Honest
      // answer: unknown. Callers keep their prior behavior; nothing is blanked.
      return WifiConnectionStatus.unknown;
    }
    if (v6.present) {
      // AMBIGUOUS, and deliberately unresolved. See KNOWN LIMITS in the header:
      // the cost is a possible stale reading on an IPv6-only SSID; the thing we
      // refuse to do is claim a connected device is not connected.
      return WifiConnectionStatus.unknown;
    }

    // No IPv4 and NO IPv6 anywhere on the Wi-Fi interface: it has no active link.
    // This is the cellular-only case the probe exists for, and the one Keith hit.
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

  /// Whether the Wi-Fi interface carries ANY IPv6 address.
  ///
  /// DELIBERATELY UNCLASSIFIED. An earlier revision kept only a "routable" IPv6
  /// here (discarding `fe80::/10`) in order to read a global address as proof of
  /// an IPv6-only association. That was dead code in the positive direction: the
  /// plugin returns the FIRST AF_INET6 address on `en*`, which is the LINK-LOCAL
  /// (measured — see the header), so the routable branch was never taken on a real
  /// device and every associated IPv6-only phone fell through to `notOnWifi`.
  ///
  /// So this reports PRESENCE only, and the caller uses only the negative:
  /// no address of either family ⇒ no active link ⇒ `notOnWifi`. Any address at
  /// all ⇒ `unknown`. Classifying the address cannot make the ambiguity go away,
  /// so we do not pretend it can.
  ///
  /// [present] is false only for a null/blank read. [threw] == true means the read
  /// itself failed, which the caller must resolve to `unknown` — never `notOnWifi`.
  Future<({bool present, bool threw})> _readWifiIpv6() async {
    try {
      final String? v = await _networkInfo.getWifiIPv6();
      if (v == null) return (present: false, threw: false);
      return (present: v.trim().isNotEmpty, threw: false);
    } on Object catch (e) {
      debugPrint('WifiConnectionService.getWifiIPv6 failed: $e');
      return (present: false, threw: true);
    }
  }
}
