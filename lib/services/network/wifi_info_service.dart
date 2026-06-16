import 'dart:async';
// Conditional import: dart:io provides Platform on native targets and is
// stubbed out on web, mirroring how the rest of the network layer guards
// against the missing dart:io on web (see network_support.dart, which gates on
// kIsWeb). Platform is only read when not on web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A snapshot of the connected Wi-Fi interface.
///
/// Every radio field is nullable because the corresponding CoreWLAN read can
/// be unavailable. [poweredOn] and [locationAuthorized] are always present.
///
/// Two fields are intentionally absent and never reported:
///   - The Rx (receive) rate, which public CoreWLAN does not expose.
///   - The Tx power, which public CoreWLAN does not expose.
/// The UI marks those as unavailable rather than estimating them.
@immutable
class WifiInfo {
  /// Creates a Wi-Fi snapshot.
  const WifiInfo({
    required this.interfaceName,
    required this.ssid,
    required this.bssid,
    required this.rssiDbm,
    required this.noiseDbm,
    required this.snrDb,
    required this.txRateMbps,
    this.rxRateMbps,
    required this.phyMode,
    required this.channel,
    required this.channelWidthMhz,
    required this.band,
    required this.countryCode,
    required this.hardwareAddress,
    this.securityToken,
    required this.poweredOn,
    required this.locationAuthorized,
  });

  /// The BSD interface name, such as "en0".
  final String? interfaceName;

  /// The connected network name. Null when not connected or when Location
  /// Services is not authorized (macOS hides the SSID without it).
  final String? ssid;

  /// The connected access point MAC address. Null without Location Services
  /// authorization, for the same reason as [ssid].
  final String? bssid;

  /// The received signal strength in dBm, or null if unavailable.
  final int? rssiDbm;

  /// The noise floor in dBm, or null if unavailable.
  final int? noiseDbm;

  /// The signal-to-noise ratio in dB, computed only when both RSSI and noise
  /// are present, otherwise null.
  final int? snrDb;

  /// The transmit rate in Mbps, or null if unavailable.
  final double? txRateMbps;

  /// The receive (Rx) link rate in Mbps, or null when the platform does not
  /// supply it in this reading. macOS public CoreWLAN never exposes it (always
  /// null there; the screen marks it "not exposed by macOS"). Android DOES
  /// expose it via `WifiInfo.getRxLinkSpeedMbps()` on API 30+ — but that call
  /// returns the unknown sentinel (-1) on many devices/links, in which case the
  /// native side passes null and the screen labels it a platform limit rather
  /// than fabricating a value (GL-005).
  final double? rxRateMbps;

  /// The active PHY mode as an 802.11 string, such as "802.11ax", or null.
  final String? phyMode;

  /// The primary channel number, or null if unavailable.
  final int? channel;

  /// The channel width in MHz (20, 40, 80, 160), or null if unknown.
  final int? channelWidthMhz;

  /// The band as a human-readable string ("2.4 GHz", "5 GHz", "6 GHz"), or
  /// null if unknown.
  final String? band;

  /// The regulatory country code, or null if unavailable.
  final String? countryCode;

  /// The interface hardware (MAC) address, or null if unavailable.
  final String? hardwareAddress;

  /// The CoreWLAN security token (e.g. "wpa2Personal", "wpa3Transition",
  /// "open"), or null when unavailable. The native channel maps `CWSecurity` to
  /// this string; Dart classifies it via [WifiSecurityClassifier].
  final String? securityToken;

  /// Whether the Wi-Fi interface is powered on.
  final bool poweredOn;

  /// Whether Location Services is authorized, which gates SSID and BSSID.
  final bool locationAuthorized;

  /// Builds a snapshot from the native channel payload.
  ///
  /// Numeric values may arrive as int or double; they are coerced safely.
  factory WifiInfo.fromMap(Map<dynamic, dynamic> map) {
    return WifiInfo(
      interfaceName: map['interfaceName'] as String?,
      ssid: map['ssid'] as String?,
      bssid: map['bssid'] as String?,
      rssiDbm: (map['rssiDbm'] as num?)?.toInt(),
      noiseDbm: (map['noiseDbm'] as num?)?.toInt(),
      snrDb: (map['snrDb'] as num?)?.toInt(),
      txRateMbps: (map['txRateMbps'] as num?)?.toDouble(),
      rxRateMbps: (map['rxRateMbps'] as num?)?.toDouble(),
      phyMode: map['phyMode'] as String?,
      channel: (map['channel'] as num?)?.toInt(),
      channelWidthMhz: (map['channelWidthMhz'] as num?)?.toInt(),
      band: map['band'] as String?,
      countryCode: map['countryCode'] as String?,
      hardwareAddress: map['hardwareAddress'] as String?,
      securityToken: map['securityToken'] as String?,
      poweredOn: (map['poweredOn'] as bool?) ?? false,
      locationAuthorized: (map['locationAuthorized'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'WifiInfo(interfaceName: $interfaceName, ssid: $ssid, bssid: $bssid, '
      'rssiDbm: $rssiDbm, noiseDbm: $noiseDbm, snrDb: $snrDb, '
      'txRateMbps: $txRateMbps, rxRateMbps: $rxRateMbps, phyMode: $phyMode, '
      'channel: $channel, '
      'channelWidthMhz: $channelWidthMhz, band: $band, '
      'countryCode: $countryCode, hardwareAddress: $hardwareAddress, '
      'securityToken: $securityToken, '
      'poweredOn: $poweredOn, locationAuthorized: $locationAuthorized)';
}

/// The tri-state Location (name-gating) authorization status.
///
/// The bool [WifiInfoService.isLocationAuthorized] collapses the two
/// unauthorized states into one `false`, but the UI must tell them apart:
///   - [notDetermined] is PROMPTABLE — the native system permission prompt can
///     still surface, so the app proactively requests it.
///   - [denied] / [restricted] are NOT promptable — the user must flip the
///     toggle in System Settings, so the app deep-links there instead of firing
///     a dialog that will never appear.
enum LocationAuthStatus {
  /// Granted (When-In-Use or Always on macOS; ACCESS_FINE_LOCATION on Android).
  /// SSID and BSSID resolve.
  authorized,

  /// Never asked yet — the native prompt can still be surfaced. Promptable.
  notDetermined,

  /// The user (or an admin/parental restriction) declined. Not promptable; the
  /// only path forward is the System Settings deep-link.
  denied,

  /// Restricted by device policy (MDM / parental controls). Treated like
  /// [denied] for UI purposes: not promptable, deep-link only.
  restricted;

  /// Resolves a native token string into a status. An unrecognized or null
  /// token defaults to [notDetermined] — the safe default that offers the
  /// (harmless) prompt path rather than a dead deep-link.
  static LocationAuthStatus fromToken(String? token) {
    switch (token) {
      case 'authorized':
        return LocationAuthStatus.authorized;
      case 'denied':
        return LocationAuthStatus.denied;
      case 'restricted':
        return LocationAuthStatus.restricted;
      case 'notDetermined':
      default:
        return LocationAuthStatus.notDetermined;
    }
  }

  /// Whether SSID / BSSID resolve in this state.
  bool get isAuthorized => this == LocationAuthStatus.authorized;

  /// Whether the native permission prompt can still be surfaced.
  bool get isPromptable => this == LocationAuthStatus.notDetermined;
}

/// Reason a Wi-Fi snapshot could not be read.
enum WifiInfoUnavailableReason {
  /// The current platform has no native Wi-Fi info bridge.
  unsupportedPlatform,

  /// The native channel returned an error or a null payload.
  channelError,
}

/// Thrown when Wi-Fi info cannot be read on this platform.
@immutable
class WifiInfoUnavailable implements Exception {
  /// Creates a typed unavailability.
  const WifiInfoUnavailable(this.reason, [this.detail]);

  /// Why the snapshot is unavailable.
  final WifiInfoUnavailableReason reason;

  /// Optional human-readable detail.
  final String? detail;

  @override
  String toString() =>
      'WifiInfoUnavailable(reason: $reason, detail: $detail)';
}

/// Reads live Wi-Fi metrics through a native platform bridge.
///
/// The [invoke] seam is injectable so tests can exercise the mapping logic
/// without a real platform channel. On any non-macOS platform the service
/// throws [WifiInfoUnavailable] rather than fabricating data.
class WifiInfoService {
  /// Creates a Wi-Fi info service.
  ///
  /// [invoke] defaults to the real method channel. Tests pass a fake.
  /// [platformOverride] defaults to the host operating system.
  WifiInfoService({
    Future<Object?> Function(String method, [dynamic args])? invoke,
    String? platformOverride,
  })  : _invoke = invoke ?? _defaultInvoke,
        _platform = platformOverride ?? _hostOperatingSystem();

  /// Returns the host OS name, or an empty string on web where there is no
  /// dart:io Platform. Never throws.
  static String _hostOperatingSystem() {
    if (kIsWeb) return '';
    return platform_io.Platform.operatingSystem;
  }

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/wifi_info');

  static Future<Object?> _defaultInvoke(String method, [dynamic args]) =>
      _channel.invokeMethod<Object?>(method, args);

  final Future<Object?> Function(String method, [dynamic args]) _invoke;
  final String _platform;

  /// Whether this platform has a native Wi-Fi info bridge.
  ///
  /// macOS reads CoreWLAN; Android reads WifiManager + ConnectivityManager
  /// (MainActivity.kt). Both back the same `com.wlanpros.toolbox/wifi_info`
  /// channel and the same [WifiInfo] payload shape.
  bool get isSupportedPlatform =>
      !kIsWeb && (_platform == 'macos' || _platform == 'android');

  /// Reads a live snapshot of the connected Wi-Fi interface.
  ///
  /// Throws [WifiInfoUnavailable] with [WifiInfoUnavailableReason.unsupportedPlatform]
  /// off macOS without touching the channel, or with
  /// [WifiInfoUnavailableReason.channelError] on a channel failure.
  Future<WifiInfo> fetch() async {
    if (!isSupportedPlatform) {
      throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.unsupportedPlatform,
      );
    }
    try {
      final result = await _invoke('getWifiInfo');
      final map = result as Map<dynamic, dynamic>?;
      if (map == null) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'Native channel returned no payload.',
        );
      }
      return WifiInfo.fromMap(map);
    } on PlatformException catch (e) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        e.message,
      );
    }
  }

  /// Requests Location Services authorization.
  ///
  /// Returns whether location is authorized after the request resolves. macOS
  /// requires this to expose the SSID and BSSID.
  Future<bool> requestLocationPermission() async {
    final result = await _invoke('requestLocationPermission');
    return (result as bool?) ?? false;
  }

  /// Returns whether Location Services is currently authorized, no prompt.
  Future<bool> isLocationAuthorized() async {
    final result = await _invoke('isLocationAuthorized');
    return (result as bool?) ?? false;
  }

  /// Returns the tri-state Location authorization status, no prompt.
  ///
  /// Unlike [isLocationAuthorized] (a bool), this distinguishes the promptable
  /// `notDetermined` from the deep-link-only `denied` / `restricted`, so the UI
  /// can fire the native prompt only when it can actually appear. Falls back to
  /// [LocationAuthStatus.notDetermined] if the native side returns nothing.
  Future<LocationAuthStatus> locationAuthorizationStatus() async {
    final result = await _invoke('locationAuthorizationStatus');
    return LocationAuthStatus.fromToken(result as String?);
  }

  /// Deep-links to the macOS Location Services privacy pane so the user can
  /// enable this app's Location access manually.
  ///
  /// macOS does not allow an app to toggle its own Location permission in code
  /// (TCC protection), so when the in-app prompt is unreliable (common in
  /// notarized non-App-Store builds) this opens the exact settings pane as the
  /// honest fallback. Returns whether the settings pane opened.
  Future<bool> openLocationSettings() async {
    final result = await _invoke('openLocationSettings');
    return (result as bool?) ?? false;
  }
}
