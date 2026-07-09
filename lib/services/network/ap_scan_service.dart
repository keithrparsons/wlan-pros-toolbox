import 'dart:async';
// Conditional import: dart:io provides Platform on native targets and is stubbed
// out on web, mirroring wifi_info_service.dart. Platform is only read off web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/channel_frequency_data.dart';
import 'pi_backend.dart';
import 'pi_backend_client.dart';

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
  /// This build has no wired nearby-AP scan for the current platform. iOS and
  /// macOS block it at the OS level; the Windows Native Wifi path exists but is
  /// not wired into this tool yet. Only Android is wired today.
  unsupportedPlatform,

  /// The native channel returned an error or a null payload.
  channelError,
}

/// Why a nearby-AP scan is or isn't available on the current platform.
///
/// Drives honest per-platform copy in the UI. This is about what THIS tool has
/// wired up today, not a permanent claim about each OS's capabilities.
enum ApScanPlatformStatus {
  /// The scan is wired and runs here (Android).
  supported,

  /// iOS and macOS block nearby-AP scanning at the OS level.
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

/// Reads nearby APs through the Android native scan bridge.
///
/// Wired for Android only today: [isSupportedPlatform] is true only on Android
/// and [scan] throws [ApScanUnavailable] everywhere else rather than fabricating
/// a list. iOS and macOS block nearby-AP scanning at the OS level. Windows can
/// enumerate nearby APs through its Native Wifi API (`WlanGetNetworkBssList`),
/// but that path is not wired into this tool yet. [platformStatus] reports which
/// case applies so the UI can show honest per-platform copy.
///
/// The [invoke] seam is injectable so tests exercise the mapping without a real
/// platform channel.
class ApScanService {
  /// Creates an AP-scan service.
  ///
  /// [invoke] defaults to the real method channel; tests pass a fake.
  /// [platformOverride] defaults to the host operating system.
  ///
  /// PI-HOSTED WEB: when this bundle is served from a WLAN Pi, the scan runs on
  /// the Pi's radio via `/toolboxapi/scan` (a genuine off-channel neighbor scan
  /// the browser cannot do). [piBackedOverride] / [piClient] / [piInterface] are
  /// test seams; in production `_piBacked` is `kIsWeb && PiBackend.available`, so
  /// native behavior is byte-for-byte unchanged and Netlify web stays unsupported.
  ApScanService({
    Future<Object?> Function(String method, [dynamic args])? invoke,
    String? platformOverride,
    bool? piBackedOverride,
    PiBackendClient? piClient,
    String piInterface = 'wlan0',
  })  : _invoke = invoke ?? _defaultInvoke,
        _platform = platformOverride ?? _hostOperatingSystem(),
        _piBacked = piBackedOverride ?? (kIsWeb && PiBackend.available) {
    _piClient = piClient;
    _piInterface = piInterface;
  }

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

  /// True when the scan is served by the Pi hosting backend (web only).
  final bool _piBacked;

  /// The Pi's scan-radio interface. Lazily-created client so native builds never
  /// construct an http.Client they will not use.
  PiBackendClient? _piClient;
  String _piInterface = 'wlan0';

  PiBackendClient get _pi => _piClient ??= PiBackendClient();

  /// Whether this platform supports a nearby-AP scan. Android natively, OR any
  /// browser served from a WLAN Pi (the scan runs on the Pi's radio).
  bool get isSupportedPlatform =>
      _piBacked || (!kIsWeb && _platform == 'android');

  /// Categorizes why the scan is or isn't available here, for honest UI copy.
  ///
  /// Reports what THIS tool has wired up today. Windows genuinely can enumerate
  /// nearby APs via Native Wifi; that path just isn't wired here yet, so it maps
  /// to [ApScanPlatformStatus.windowsNotWired] rather than a false OS-block.
  ApScanPlatformStatus get platformStatus {
    if (isSupportedPlatform) return ApScanPlatformStatus.supported;
    if (_platform == 'windows') return ApScanPlatformStatus.windowsNotWired;
    if (_platform == 'ios' || _platform == 'macos') {
      return ApScanPlatformStatus.appleRestricted;
    }
    return ApScanPlatformStatus.unavailable;
  }

  /// Requests a fresh scan and returns the resulting snapshot.
  ///
  /// The OS rate-limits fresh scans; when it throttles one, the snapshot carries
  /// the last cached scan with [ApScanSnapshot.scanThrottled] set. Throws
  /// [ApScanUnavailable] off Android (never touches the channel there).
  Future<ApScanSnapshot> scan() => _read('scan');

  /// Returns the last cached scan without requesting a fresh one.
  Future<ApScanSnapshot> lastResults() => _read('lastResults');

  Future<ApScanSnapshot> _read(String method) async {
    // Pi-hosted web: fetch a neighbor scan from the Pi's radio and map it into
    // the same snapshot shape. The Pi has no Location gate or scan throttle, so
    // those flags are true/false accordingly; a backend failure surfaces as the
    // same channelError the native path uses.
    if (_piBacked) {
      try {
        final List<PiScanNet> nets =
            await _pi.scan(interface: _piInterface);
        return ApScanSnapshot(
          accessPoints:
              nets.map(_scannedApFromPi).toList(growable: false),
          poweredOn: true,
          locationAuthorized: true,
          scanThrottled: false,
        );
      } on PiBackendException catch (e) {
        throw ApScanUnavailable(
          ApScanUnavailableReason.channelError,
          e.message,
        );
      }
    }
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

  /// Whether ACCESS_FINE_LOCATION is currently granted (no prompt). Always true
  /// on the Pi-hosted path — the scan runs on the Pi, not behind an Android
  /// Location gate, so the Location card never shows there.
  Future<bool> isLocationAuthorized() async {
    if (_piBacked) return true;
    final result = await _invoke('isLocationAuthorized');
    return (result as bool?) ?? false;
  }

  /// Requests ACCESS_FINE_LOCATION. Returns whether it is granted afterward.
  /// Android gates scan results behind it. No-op (already authorized) on the
  /// Pi-hosted path.
  Future<bool> requestLocationPermission() async {
    if (_piBacked) return true;
    final result = await _invoke('requestLocationPermission');
    return (result as bool?) ?? false;
  }

  /// Maps one Pi BSS into a [ScannedAp], deriving the channel + band from the
  /// reported center frequency via the verified channel-plan converter. Falls
  /// back to arithmetic band/channel derivation only when the frequency does not
  /// snap to a known 20 MHz primary (rare), so a scanned AP is always shown.
  static ScannedAp _scannedApFromPi(PiScanNet net) {
    final ({WifiBand band, int channel})? match =
        frequencyToChannel(net.freqMhz.toDouble());
    final int channel;
    final String band;
    if (match != null) {
      channel = match.channel;
      band = match.band.label;
    } else {
      final (int ch, String b) = _deriveChannelBand(net.freqMhz);
      channel = ch;
      band = b;
    }
    return ScannedAp(
      ssid: net.ssid,
      bssid: net.bssid,
      rssiDbm: net.signalDbm,
      channel: channel,
      band: band,
      frequencyMhz: net.freqMhz,
    );
  }

  /// Arithmetic fallback (channel, band) from a center frequency (MHz), using
  /// the universal channel<->frequency formula. Only reached when
  /// [frequencyToChannel] returns null.
  static (int, String) _deriveChannelBand(int freq) {
    if (freq == 2484) return (14, '2.4 GHz');
    if (freq >= 2401 && freq <= 2495) {
      return (((freq - 2407) / 5).round(), '2.4 GHz');
    }
    if (freq >= 5150 && freq <= 5895) {
      return (((freq - 5000) / 5).round(), '5 GHz');
    }
    if (freq >= 5925 && freq <= 7125) {
      return (((freq - 5950) / 5).round(), '6 GHz');
    }
    return (0, '$freq MHz');
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
