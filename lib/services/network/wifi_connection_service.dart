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
// THE SIGNAL, AND WHY IT IS HONEST (GL-005):
//
//   The cross-platform, permission-free signal is `network_info_plus.getWifiIP()`
//   (a NATIVE method-channel call, NOT a subprocess — safe in the sandboxed
//   macOS/iOS builds, GL-008). It returns a non-empty IPv4 ONLY when the device
//   has an ACTIVE Wi-Fi interface bound to an address:
//     * On iOS it returns the Wi-Fi IP when joined to Wi-Fi, and NULL on
//       cellular-only — and, crucially, it needs NO Location permission (unlike
//       NEHotspotNetwork's SSID read), so it cannot be confused with a missing
//       Location grant. That is exactly the missing-Wi-Fi signal we want.
//     * On macOS/Android/Windows it returns the Wi-Fi adapter's IP when Wi-Fi is
//       up. A wired-only desktop legitimately returns null here — see the
//       three-state design below, which never CLAIMS "not on Wi-Fi" from a null
//       alone; a null is only ever the honest [WifiConnectionStatus.unknown].
//
//   THREE HONEST STATES — never fake a value:
//     * onWifi    — getWifiIP() returned a non-empty address (or a caller-supplied
//                   native SSID proves an active Wi-Fi join). The device is on
//                   Wi-Fi; the live read should proceed.
//     * notOnWifi — the platform exposes the active connection type AND it is
//                   demonstrably NOT Wi-Fi. Today this is asserted ONLY when the
//                   Wi-Fi IP is null on a platform where a null Wi-Fi IP reliably
//                   means "no Wi-Fi link" (iOS), so the "connect to Wi-Fi" copy is
//                   never shown to a wired desktop that simply has no Wi-Fi IP.
//     * unknown   — the probe could not determine the state (read threw, the
//                   platform does not expose it, or a null Wi-Fi IP on a platform
//                   where that is ambiguous — e.g. a wired Mac). The caller treats
//                   `unknown` as "carry on as before", NEVER as "not on Wi-Fi".
//
//   GL-005 GUARANTEE: a null/ambiguous read resolves to [unknown], never to
//   [notOnWifi]. We only ever tell the user "you're not on Wi-Fi" when we have a
//   positive signal that they are not — never as a guess from missing data.
//
// Web safety: no `dart:io`. `network_info_plus` is a method-channel plugin whose
// channel is absent off the supported native platforms; the calls are guarded and
// resolve to [unknown] there. The screens only construct this behind their
// existing platform gates regardless.

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// The honest three-way Wi-Fi connection verdict. See [WifiConnectionService].
enum WifiConnectionStatus {
  /// The device is connected to a Wi-Fi network (an active Wi-Fi IP, or a
  /// caller-supplied native SSID). The live read should proceed.
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
  /// is off), so the negative verdict rests solely on the permission-free Wi-Fi-IP
  /// signal below.
  Future<WifiConnectionStatus> status({String? nativeSsid}) async {
    // A resolved native SSID proves an active Wi-Fi join — strongest positive.
    if (nativeSsid != null && nativeSsid.trim().isNotEmpty) {
      return WifiConnectionStatus.onWifi;
    }

    final ({String? ip, bool threw}) read = await _readWifiIp();
    if (read.threw) {
      // The read FAILED (denied permission / unsupported platform). That is
      // ambiguous, never a positive not-on-Wi-Fi signal — resolve to `unknown`
      // so a denied read is NEVER surfaced as a false "not on Wi-Fi" (GL-005).
      // This is distinct from a CLEAN null below (an active read that returned no
      // address), which on iOS IS the honest cellular-only signal.
      return WifiConnectionStatus.unknown;
    }
    final String? wifiIp = read.ip;
    if (wifiIp != null && wifiIp.isNotEmpty) {
      // An active Wi-Fi interface has an address: on Wi-Fi.
      return WifiConnectionStatus.onWifi;
    }

    // No Wi-Fi IP from a SUCCESSFUL read. Whether that PROVES "not on Wi-Fi"
    // depends on the platform.
    //
    //   * iOS: a null Wi-Fi IP reliably means there is no Wi-Fi link (the device
    //     is on cellular or fully offline). iOS surfaces no wired Ethernet to
    //     confuse this, so a null here is the honest `notOnWifi` — the exact
    //     cellular-only case this service was built for.
    //   * Everywhere else: a null Wi-Fi IP is AMBIGUOUS (a wired-only Mac, a
    //     desktop with Wi-Fi off, a platform that does not report the Wi-Fi IP),
    //     so we resolve to `unknown` rather than falsely tell a wired user to
    //     "connect to Wi-Fi" (GL-005).
    if (_platform == TargetPlatform.iOS) {
      return WifiConnectionStatus.notOnWifi;
    }
    return WifiConnectionStatus.unknown;
  }

  /// Reads the Wi-Fi IP, normalizing the "no address" placeholders to null.
  ///
  /// Returns a record so the caller can tell a CLEAN null (the read succeeded but
  /// there is no Wi-Fi address — the honest cellular-only signal on iOS) apart
  /// from a FAILED read ([threw] == true: denied permission / unsupported
  /// platform). Only the clean null on iOS asserts `notOnWifi`; a failed read is
  /// always `unknown` (GL-005: a denied/errored read is never a false negative).
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
}
