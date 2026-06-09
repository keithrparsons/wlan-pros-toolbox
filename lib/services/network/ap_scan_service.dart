import 'dart:async';
// Conditional import: dart:io provides Platform on native targets and is stubbed
// out on web, mirroring wifi_info_service.dart. Platform is only read off web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One visible access point (BSS) from an Android Wi-Fi scan.
///
/// CLEAN fields only — SSID, BSSID, channel, band, RSSI. The Android scan API
/// does NOT expose a per-BSS noise floor, SNR, or MCS for a scanned (not
/// connected) BSS, so those are never modeled here and never shown. Reporting
/// them would be a fabrication (GL-005 / GL-008).
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
  final List<ScannedAp> accessPoints;

  /// Whether the Wi-Fi radio is on. Scanning needs it on.
  final bool poweredOn;

  /// Whether ACCESS_FINE_LOCATION is granted. Android gates scan results behind
  /// it; without it [accessPoints] is empty and the UI shows the Location card.
  final bool locationAuthorized;

  /// Whether a requested fresh scan was throttled by the OS, so [accessPoints]
  /// are from the last cached scan rather than a brand-new one. The UI labels
  /// the list as "last scan" when this is true.
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
  /// The current platform has no nearby-AP scan (iOS and macOS block it).
  unsupportedPlatform,

  /// The native channel returned an error or a null payload.
  channelError,
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

/// Reads nearby APs through the Android native scan bridge.
///
/// ANDROID-ONLY. iOS and macOS block nearby-AP scanning at the platform level,
/// so [isSupportedPlatform] is true only on Android and [scan] throws
/// [ApScanUnavailable] everywhere else rather than fabricating a list.
///
/// The [invoke] seam is injectable so tests exercise the mapping without a real
/// platform channel.
class ApScanService {
  /// Creates an AP-scan service.
  ///
  /// [invoke] defaults to the real method channel; tests pass a fake.
  /// [platformOverride] defaults to the host operating system.
  ApScanService({
    Future<Object?> Function(String method, [dynamic args])? invoke,
    String? platformOverride,
  })  : _invoke = invoke ?? _defaultInvoke,
        _platform = platformOverride ?? _hostOperatingSystem();

  /// Returns the host OS name, or an empty string on web. Never throws.
  static String _hostOperatingSystem() {
    if (kIsWeb) return '';
    return platform_io.Platform.operatingSystem;
  }

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/ap_scan');

  static Future<Object?> _defaultInvoke(String method, [dynamic args]) =>
      _channel.invokeMethod<Object?>(method, args);

  final Future<Object?> Function(String method, [dynamic args]) _invoke;
  final String _platform;

  /// Whether this platform supports a nearby-AP scan. Android only.
  bool get isSupportedPlatform => !kIsWeb && _platform == 'android';

  /// Requests a fresh scan and returns the resulting snapshot.
  ///
  /// The OS rate-limits fresh scans; when it throttles one, the snapshot carries
  /// the last cached scan with [ApScanSnapshot.scanThrottled] set. Throws
  /// [ApScanUnavailable] off Android (never touches the channel there).
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

  /// Whether ACCESS_FINE_LOCATION is currently granted (no prompt).
  Future<bool> isLocationAuthorized() async {
    final result = await _invoke('isLocationAuthorized');
    return (result as bool?) ?? false;
  }

  /// Requests ACCESS_FINE_LOCATION. Returns whether it is granted afterward.
  /// Android gates scan results behind it.
  Future<bool> requestLocationPermission() async {
    final result = await _invoke('requestLocationPermission');
    return (result as bool?) ?? false;
  }

  /// Opens this app's system settings page so the user can enable Location
  /// after a permanent denial. Returns whether the settings page opened.
  Future<bool> openLocationSettings() async {
    final result = await _invoke('openLocationSettings');
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
