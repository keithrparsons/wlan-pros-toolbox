// WifiSecurityService — Dart side of the iOS NEHotspotNetwork security + BSSID
// channel (TICKET-BATCH7).
//
// Reads the connected network's COARSE security token and BSSID directly from
// the app via the native `com.wlanpros.toolbox/wifi_security` method channel
// (ios/Runner/WifiSecurityChannel.swift). This is the iOS-only enrichment path:
// the iOS RF metrics arrive through the Shortcut bridge, but the security type
// and BSSID are app-readable via NEHotspotNetwork given the Access Wi-Fi
// Information entitlement + Location permission.
//
// HONESTY (GL-005): every off-iOS or permission-denied path resolves to an
// explicit unavailable result with a reason — never a fabricated token. The
// [invoke] seam is injectable so the result mapping is unit-testable without a
// real platform channel.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wifi_info_service.dart' show LocationAuthStatus;

// LocationAuthStatus is part of WifiSecurityInfo's public surface, so it
// travels with it. Re-exported (rather than redeclared) on purpose: ONE enum
// and one token vocabulary for this TCC grant across macOS, Android and iOS.
export 'wifi_info_service.dart' show LocationAuthStatus;

/// A native NEHotspotNetwork read: the coarse security token + BSSID, with an
/// explicit availability flag and an honest reason when unavailable.
@immutable
class WifiSecurityInfo {
  const WifiSecurityInfo({
    required this.available,
    this.reason,
    this.securityToken,
    this.bssid,
    this.ssid,
    required this.locationAuth,
  });

  /// True only when a real connected network resolved.
  final bool available;

  /// Why the read was unavailable (missing entitlement / permission / no
  /// network), for the honest UI state. Null when [available].
  final String? reason;

  /// The coarse iOS security token ("open"/"wep"/"personal"/"enterprise"/
  /// "unknown"), or null. Classified to a label by [WifiSecurityClassifier].
  final String? securityToken;

  /// The connected AP MAC (BSSID), for the offline OUI vendor lookup. Null when
  /// unavailable.
  final String? bssid;

  /// The network name (context only). Null when unavailable.
  final String? ssid;

  /// The shared Location gate's current state, as the platform's own TRI-STATE.
  ///
  /// THE load-bearing input, and the one this class used to lack. It replaced a
  /// `bool locationAuthorized`, which could not distinguish "never asked" from
  /// "asked and refused" — and iOS re-prompts only in the former. A UI reading
  /// the bool therefore rendered a Grant button under `denied` that
  /// `requestWhenInUseAuthorization` is guaranteed to ignore.
  /// See [[feedback_ui_rendered_a_decision_it_lacked]].
  ///
  /// `required` on purpose, on BOTH constructors: a call site cannot forget to
  /// carry the authorization state, because this class will not compile without
  /// it. There is deliberately no derived `locationAuthorized` bool here —
  /// [LocationAuthStatus.isAuthorized] is the single derivation, and a second
  /// name for the same fact is how the two representations drift apart.
  final LocationAuthStatus locationAuth;

  /// An unavailable result with a [reason]. [locationAuth] is required rather
  /// than defaulted so each unavailable path states the status it actually
  /// observed; the off-platform paths (no channel at all) pass
  /// [LocationAuthStatus.notDetermined] as the documented safe default.
  const WifiSecurityInfo.unavailable(this.reason, {required this.locationAuth})
      : available = false,
        securityToken = null,
        bssid = null,
        ssid = null;

  /// Builds from the native channel payload. Tolerant of a null map.
  factory WifiSecurityInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const WifiSecurityInfo.unavailable(
        'The Wi-Fi security channel returned no payload.',
        locationAuth: LocationAuthStatus.notDetermined,
      );
    }
    return WifiSecurityInfo(
      available: (map['available'] as bool?) ?? false,
      reason: map['reason'] as String?,
      securityToken: map['securityToken'] as String?,
      bssid: map['bssid'] as String?,
      ssid: map['ssid'] as String?,
      // The tri-state token is authoritative. The legacy `locationAuthorized`
      // bool is deliberately NOT consulted: it cannot express `denied` vs
      // `notDetermined`, and reading both would reintroduce the two-
      // representations drift this change exists to remove. An absent or
      // unrecognized token resolves to `notDetermined` per fromToken's
      // documented safe default.
      locationAuth: LocationAuthStatus.fromToken(
        map['locationAuthStatus'] as String?,
      ),
    );
  }
}

/// Reads the connected network's security type + BSSID through the native iOS
/// channel. Off-iOS (where the channel has no handler) every call resolves to an
/// honest unavailable result rather than throwing.
class WifiSecurityService {
  /// [invoke] defaults to the real method channel; tests pass a fake.
  WifiSecurityService({
    Future<Object?> Function(String method, [dynamic args])? invoke,
  }) : _invoke = invoke ?? _defaultInvoke;

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/wifi_security');

  static Future<Object?> _defaultInvoke(String method, [dynamic args]) =>
      _channel.invokeMethod<Object?>(method, args);

  final Future<Object?> Function(String method, [dynamic args]) _invoke;

  /// Reads the current security token + BSSID. Never throws: a missing channel
  /// (off iOS) or a platform error resolves to an honest unavailable result.
  Future<WifiSecurityInfo> fetch() async {
    try {
      final Object? result = await _invoke('getSecurityInfo');
      return WifiSecurityInfo.fromMap(result as Map<dynamic, dynamic>?);
    } on MissingPluginException {
      // Off iOS there is no CoreLocation gate to report at all. notDetermined is
      // the documented safe default; nothing renders the iOS gate off-iOS.
      return const WifiSecurityInfo.unavailable(
        'Not available on this platform.',
        locationAuth: LocationAuthStatus.notDetermined,
      );
    } on PlatformException catch (e) {
      debugPrint('WifiSecurityService.fetch failed: $e');
      return WifiSecurityInfo.unavailable(
        e.message ?? 'Channel error.',
        locationAuth: LocationAuthStatus.notDetermined,
      );
    }
  }

  /// Whether Location is currently authorized (no prompt). False off iOS.
  Future<bool> isLocationAuthorized() async {
    try {
      return await _invoke('isLocationAuthorized') as bool? ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WifiSecurityService.isLocationAuthorized failed: $e');
      return false;
    }
  }

  /// The Location gate as the platform's TRI-STATE, with no prompt.
  ///
  /// Unlike [isLocationAuthorized] (a bool), this distinguishes the promptable
  /// `notDetermined` from `denied`/`restricted`, where iOS will never surface
  /// the system prompt again and only a Settings deep-link can work. Off iOS
  /// (no channel) it resolves to `notDetermined`, the documented safe default.
  Future<LocationAuthStatus> locationAuthorizationStatus() async {
    try {
      final Object? token = await _invoke('locationAuthorizationStatus');
      return LocationAuthStatus.fromToken(token as String?);
    } on MissingPluginException {
      return LocationAuthStatus.notDetermined;
    } on PlatformException catch (e) {
      debugPrint('WifiSecurityService.locationAuthorizationStatus failed: $e');
      return LocationAuthStatus.notDetermined;
    }
  }

  /// Requests Location-When-In-Use authorization (the gate NEHotspotNetwork
  /// shares with the BSSID read). Returns the authorization state after the
  /// prompt resolves. False off iOS.
  Future<bool> requestLocationPermission() async {
    try {
      return await _invoke('requestLocationPermission') as bool? ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WifiSecurityService.requestLocationPermission failed: $e');
      return false;
    }
  }

  /// Opens the app's Settings page so the user can enable Location manually.
  Future<bool> openLocationSettings() async {
    try {
      return await _invoke('openLocationSettings') as bool? ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('WifiSecurityService.openLocationSettings failed: $e');
      return false;
    }
  }
}
