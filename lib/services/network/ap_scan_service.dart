import 'dart:async';
// Conditional import: dart:io provides Platform on native targets and is stubbed
// out on web, mirroring wifi_info_service.dart. Platform is only read off web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One visible access point (BSS) from a native Wi-Fi scan.
///
/// ONE model for every platform. Android (`WifiManager.getScanResults()`) and
/// macOS (CoreWLAN `scanForNetworks`) both fill exactly these fields; neither is
/// forked or extended per platform.
///
/// CLEAN fields only — SSID, BSSID, channel, band, RSSI. NEITHER platform's scan
/// API exposes a per-BSS noise floor, SNR, or MCS for a scanned (not connected)
/// BSS, so those are never modeled here and never shown. Reporting them would be
/// a fabrication (GL-005 / GL-008).
@immutable
class ScannedAp {
  /// Creates a scanned-AP record.
  const ScannedAp({
    required this.ssid,
    required this.bssid,
    required this.rssiDbm,
    required this.channel,
    required this.band,
    required this.frequencyMhz,
  });

  /// The network name, or null for a hidden network (empty SSID). The UI shows
  /// "(hidden network)" for null rather than a blank or a fabricated name.
  final String? ssid;

  /// The AP MAC address (BSSID). Null only if the OS withheld it.
  final String? bssid;

  /// Received signal strength in dBm (negative; closer to 0 is stronger).
  final int rssiDbm;

  /// The Wi-Fi channel number derived from the center frequency.
  final int channel;

  /// The band label: "2.4 GHz", "5 GHz", or "6 GHz".
  final String band;

  /// The center frequency in MHz the channel/band were derived from.
  final int frequencyMhz;

  /// Builds a record from the native channel payload. Returns null when a
  /// required field is missing, so a malformed entry is dropped, never guessed.
  static ScannedAp? fromMap(Map<dynamic, dynamic> map) {
    final int? rssi = (map['rssiDbm'] as num?)?.toInt();
    final int? channel = (map['channel'] as num?)?.toInt();
    final String? band = map['band'] as String?;
    final int? freq = (map['frequencyMhz'] as num?)?.toInt();
    if (rssi == null || channel == null || band == null || freq == null) {
      return null;
    }
    return ScannedAp(
      ssid: map['ssid'] as String?,
      bssid: map['bssid'] as String?,
      rssiDbm: rssi,
      channel: channel,
      band: band,
      frequencyMhz: freq,
    );
  }

  @override
  String toString() => 'ScannedAp(ssid: $ssid, bssid: $bssid, '
      'rssiDbm: $rssiDbm, channel: $channel, band: $band, '
      'frequencyMhz: $frequencyMhz)';
}

/// A full nearby-AP scan: the visible APs plus the OS-state flags the UI needs
/// to render its gate/empty states honestly.
@immutable
class ApScanSnapshot {
  /// Creates a scan snapshot.
  const ApScanSnapshot({
    required this.accessPoints,
    required this.poweredOn,
    required this.locationAuthorized,
    required this.scanThrottled,
  });

  /// The visible access points. Empty when Wi-Fi is off, Location is not
  /// granted, or no BSS is in range.
  ///
  /// TWO KINDS OF NULL: an empty list means "the scan could not run" whenever
  /// [poweredOn] is false or [locationAuthorized] is false, and only means
  /// "the scan ran and found nothing" when BOTH are true. The UI must render
  /// those differently — an empty list under a missing grant that implied there
  /// are no APs nearby would be a false verdict
  /// ([[feedback_app_blames_the_wifi]]).
  final List<ScannedAp> accessPoints;

  /// Whether the Wi-Fi radio is on. Scanning needs it on.
  final bool poweredOn;

  /// Whether the Location grant that gates scan results is held. Android gates
  /// results behind ACCESS_FINE_LOCATION; macOS gates the SSID and BSSID of
  /// every scanned BSS behind Location Services (macOS 14+). Without it
  /// [accessPoints] is empty and the UI shows the Location card.
  final bool locationAuthorized;

  /// Whether a fresh scan was declined, so [accessPoints] are from the last
  /// cached scan rather than a brand-new one. On Android the OS throttles
  /// `startScan()`; on macOS the app imposes its own floor between active
  /// CoreWLAN scans (they take the radio off-channel for seconds). The UI
  /// labels the list as "last scan" when this is true.
  final bool scanThrottled;

  /// Builds a snapshot from the native channel payload.
  factory ApScanSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final List<dynamic> rawAps =
        (map['accessPoints'] as List<dynamic>?) ?? const <dynamic>[];
    final List<ScannedAp> aps = rawAps
        .whereType<Map<dynamic, dynamic>>()
        .map(ScannedAp.fromMap)
        .whereType<ScannedAp>()
        .toList();
    return ApScanSnapshot(
      accessPoints: aps,
      poweredOn: (map['poweredOn'] as bool?) ?? false,
      locationAuthorized: (map['locationAuthorized'] as bool?) ?? false,
      scanThrottled: (map['scanThrottled'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'ApScanSnapshot(accessPoints: ${accessPoints.length}, '
      'poweredOn: $poweredOn, locationAuthorized: $locationAuthorized, '
      'scanThrottled: $scanThrottled)';
}

/// Why a nearby-AP scan could not run.
enum ApScanUnavailableReason {
  /// This build has no wired nearby-AP scan for the current platform. iOS blocks
  /// it at the OS level (no scan API); Windows CAN scan but that path is not
  /// wired into this tool yet. Android and macOS are wired.
  unsupportedPlatform,

  /// The native channel returned an error or a null payload.
  channelError,
}

/// Why a nearby-AP scan is or isn't available on the current platform.
///
/// Drives honest per-platform copy in the UI. This is about what THIS tool has
/// wired up today, not a permanent claim about each OS's capabilities.
enum ApScanPlatformStatus {
  /// The scan is wired and runs here (Android and macOS).
  supported,

  /// iOS blocks nearby-AP scanning at the OS level — there is no public scan
  /// API at all. This is a true OS hard-no, not an unwired path.
  appleRestricted,

  /// Windows can enumerate nearby APs through its Native Wifi API
  /// (`WlanGetNetworkBssList`), but that path is not wired into this tool yet.
  windowsNotWired,

  /// Any other platform (web, Linux) where the scan is not available.
  unavailable,
}

/// Thrown when a nearby-AP scan cannot run on this platform.
@immutable
class ApScanUnavailable implements Exception {
  /// Creates a typed unavailability.
  const ApScanUnavailable(this.reason, [this.detail]);

  /// Why the scan is unavailable.
  final ApScanUnavailableReason reason;

  /// Optional human-readable detail.
  final String? detail;

  @override
  String toString() => 'ApScanUnavailable(reason: $reason, detail: $detail)';
}

/// Reads nearby APs through the native scan bridge.
///
/// Wired for Android and macOS: [isSupportedPlatform] is true on both and [scan]
/// throws [ApScanUnavailable] everywhere else rather than fabricating a list.
/// Both platforms answer on the SAME channel name with the SAME payload shape,
/// so this service has no per-platform branch in its mapping. iOS blocks
/// nearby-AP scanning at the OS level (no scan API). Windows CAN enumerate
/// nearby APs (`WlanGetNetworkBssList`), but that path is deliberately NOT
/// wired here yet — see [ApScanPlatformStatus.windowsNotWired].
/// [platformStatus] reports which case applies so the UI can show honest
/// per-platform copy.
///
/// The [invoke] and [invokeWifiInfo] seams are injectable so tests exercise the
/// mapping without a real platform channel.
class ApScanService {
  /// Creates an AP-scan service.
  ///
  /// [invoke] defaults to the real ap_scan method channel; tests pass a fake.
  /// [invokeWifiInfo] defaults to the real wifi_info channel and carries the
  /// macOS Location-permission calls (see [_invokePermission]); when a test
  /// injects only [invoke], both seams route to it so no test can reach a real
  /// channel. [platformOverride] defaults to the host operating system.
  ApScanService({
    Future<Object?> Function(String method, [dynamic args])? invoke,
    Future<Object?> Function(String method, [dynamic args])? invokeWifiInfo,
    String? platformOverride,
  })  : _invoke = invoke ?? _defaultInvoke,
        _invokeWifiInfo = invokeWifiInfo ?? invoke ?? _defaultWifiInfoInvoke,
        _platform = platformOverride ?? _hostOperatingSystem();

  /// Returns the host OS name, or an empty string on web. Never throws.
  static String _hostOperatingSystem() {
    if (kIsWeb) return '';
    return platform_io.Platform.operatingSystem;
  }

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/ap_scan');

  /// The Wi-Fi Information channel. On macOS it already owns the shipped
  /// Location-authorization flow (grant prompt, the "Location Services is off
  /// system-wide" guard, and the Privacy-pane deep link), so the macOS AP-scan
  /// channel does not reimplement any of it and this service routes the
  /// permission calls there instead.
  static const MethodChannel _wifiInfoChannel =
      MethodChannel('com.wlanpros.toolbox/wifi_info');

  static Future<Object?> _defaultInvoke(String method, [dynamic args]) =>
      _channel.invokeMethod<Object?>(method, args);

  static Future<Object?> _defaultWifiInfoInvoke(String method,
          [dynamic args]) =>
      _wifiInfoChannel.invokeMethod<Object?>(method, args);

  /// The platforms whose native nearby-AP scan is wired into this tool.
  ///
  /// Windows is deliberately absent. Its enumeration path exists
  /// ([WindowsWifiReader.scanNearbyBss]) but is written-not-executed against
  /// real hardware, and unverified code does not go live
  /// ([[feedback_gate_until_clean]]).
  static const Set<String> _wiredPlatforms = <String>{'android', 'macos'};

  final Future<Object?> Function(String method, [dynamic args]) _invoke;
  final Future<Object?> Function(String method, [dynamic args])
      _invokeWifiInfo;
  final String _platform;

  /// Whether this platform supports a nearby-AP scan. Android and macOS.
  bool get isSupportedPlatform =>
      !kIsWeb && _wiredPlatforms.contains(_platform);

  /// The platform name used in user-visible copy, so the UI can attribute a
  /// Location gate or a throttled scan to the right OS. Null off the wired
  /// platforms, where no such copy is shown.
  String? get platformName {
    switch (_platform) {
      case 'android':
        return 'Android';
      case 'macos':
        return 'macOS';
      default:
        return null;
    }
  }

  /// Categorizes why the scan is or isn't available here, for honest UI copy.
  ///
  /// Reports what THIS tool has wired up today. Windows genuinely can enumerate
  /// nearby APs via Native Wifi; that path just isn't wired here yet, so it maps
  /// to [ApScanPlatformStatus.windowsNotWired] rather than a false OS-block.
  ApScanPlatformStatus get platformStatus {
    if (isSupportedPlatform) return ApScanPlatformStatus.supported;
    if (_platform == 'windows') return ApScanPlatformStatus.windowsNotWired;
    // iOS is the only true OS hard-no: no public scan API at all.
    if (_platform == 'ios') return ApScanPlatformStatus.appleRestricted;
    return ApScanPlatformStatus.unavailable;
  }

  /// Requests a fresh scan and returns the resulting snapshot.
  ///
  /// Fresh scans are rate-limited (by the OS on Android, by the app on macOS
  /// where an active CoreWLAN scan takes the radio off-channel for seconds);
  /// when one is declined, the snapshot carries the last cached scan with
  /// [ApScanSnapshot.scanThrottled] set. Throws [ApScanUnavailable] on an
  /// unwired platform (never touches the channel there).
  Future<ApScanSnapshot> scan() => _read('scan');

  /// Returns the last cached scan without requesting a fresh one.
  Future<ApScanSnapshot> lastResults() => _read('lastResults');

  Future<ApScanSnapshot> _read(String method) async {
    if (!isSupportedPlatform) {
      throw const ApScanUnavailable(
        ApScanUnavailableReason.unsupportedPlatform,
      );
    }
    try {
      final result = await _invoke(method);
      final map = result as Map<dynamic, dynamic>?;
      if (map == null) {
        throw const ApScanUnavailable(
          ApScanUnavailableReason.channelError,
          'Native channel returned no payload.',
        );
      }
      return ApScanSnapshot.fromMap(map);
    } on PlatformException catch (e) {
      throw ApScanUnavailable(ApScanUnavailableReason.channelError, e.message);
    }
  }

  /// Routes a Location-permission call to the channel that owns it.
  ///
  /// Android's ap_scan channel implements the permission methods itself. macOS
  /// does not duplicate them: the wifi_info channel already owns the shipped
  /// authorization flow for exactly the same TCC grant, so the macOS AP scan
  /// reuses it rather than standing up a second, unproven copy.
  Future<Object?> _invokePermission(String method) =>
      _platform == 'macos' ? _invokeWifiInfo(method) : _invoke(method);

  /// Whether the Location grant that gates scan results is currently held (no
  /// prompt). ACCESS_FINE_LOCATION on Android; Location Services on macOS.
  Future<bool> isLocationAuthorized() async {
    final result = await _invokePermission('isLocationAuthorized');
    return (result as bool?) ?? false;
  }

  /// Requests the Location grant. Returns whether it is held afterward. Both
  /// platforms gate scan results behind it: Android withholds the results
  /// entirely, macOS withholds every SSID and BSSID.
  Future<bool> requestLocationPermission() async {
    final result = await _invokePermission('requestLocationPermission');
    return (result as bool?) ?? false;
  }

  /// Opens the system settings page so the user can enable Location after a
  /// denial (the app's own page on Android, the Location Services Privacy pane
  /// on macOS). Returns whether the settings page opened.
  Future<bool> openLocationSettings() async {
    final result = await _invokePermission('openLocationSettings');
    return (result as bool?) ?? false;
  }
}

/// Sort orders for the nearby-AP list.
enum ApSortOrder {
  /// Strongest signal first (RSSI closest to 0).
  signalDesc,

  /// Lowest channel number first.
  channelAsc,

  /// Network name A→Z (hidden networks last).
  ssidAsc,
}

/// Pure sort helper, unit-testable without a widget. Returns a new sorted list.
List<ScannedAp> sortAps(List<ScannedAp> aps, ApSortOrder order) {
  final List<ScannedAp> out = List<ScannedAp>.of(aps);
  switch (order) {
    case ApSortOrder.signalDesc:
      out.sort((a, b) => b.rssiDbm.compareTo(a.rssiDbm));
    case ApSortOrder.channelAsc:
      out.sort((a, b) {
        final int c = a.channel.compareTo(b.channel);
        return c != 0 ? c : b.rssiDbm.compareTo(a.rssiDbm);
      });
    case ApSortOrder.ssidAsc:
      out.sort((a, b) {
        final String an = a.ssid ?? '￿'; // hidden sorts last
        final String bn = b.ssid ?? '￿';
        final int c = an.toLowerCase().compareTo(bn.toLowerCase());
        return c != 0 ? c : b.rssiDbm.compareTo(a.rssiDbm);
      });
  }
  return out;
}

/// One channel's occupancy: how many APs sit on it and the strongest RSSI seen.
@immutable
class ChannelOccupancy {
  /// Creates a channel-occupancy bucket.
  const ChannelOccupancy({
    required this.channel,
    required this.apCount,
    required this.strongestRssiDbm,
  });

  /// The channel number.
  final int channel;

  /// How many visible APs are on this channel.
  final int apCount;

  /// The strongest RSSI (closest to 0) among APs on this channel.
  final int strongestRssiDbm;
}

/// Builds the per-channel occupancy buckets for one band, sorted by channel.
/// Pure and unit-testable. [bandLabel] selects which APs feed it (e.g.
/// "2.4 GHz" or "5 GHz") so the UI can render one chart per band.
List<ChannelOccupancy> channelOccupancy(
  List<ScannedAp> aps,
  String bandLabel,
) {
  final Map<int, List<ScannedAp>> byChannel = <int, List<ScannedAp>>{};
  for (final ScannedAp ap in aps) {
    if (ap.band != bandLabel) continue;
    byChannel.putIfAbsent(ap.channel, () => <ScannedAp>[]).add(ap);
  }
  final List<ChannelOccupancy> out = byChannel.entries.map((entry) {
    final int strongest = entry.value
        .map((ScannedAp a) => a.rssiDbm)
        .reduce((int a, int b) => a > b ? a : b);
    return ChannelOccupancy(
      channel: entry.key,
      apCount: entry.value.length,
      strongestRssiDbm: strongest,
    );
  }).toList()
    ..sort((a, b) => a.channel.compareTo(b.channel));
  return out;
}
