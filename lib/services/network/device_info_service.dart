// DeviceInfoService — reads the device's own model / memory / uptime / cellular
// IP for the Device Info tool (Batch 6).
//
// DATA SOURCES:
//   * model + total memory → device_info_plus (BSD-3). iOS exposes `modelName`
//     (the package maps utsname.machine → marketing name, e.g. "iPhone16,2" →
//     "iPhone 15 Pro") plus the raw `utsname.machine` identifier, and
//     `physicalRamSize` (bytes). macOS exposes `model` (identifier, e.g.
//     "Mac15,3"), `modelName`, and `memorySize` (bytes). No bundled lookup
//     table is needed — the package owns the iOS marketing-name map.
//   * uptime → a tiny native channel (SystemUptimeBridge →
//     ProcessInfo.processInfo.systemUptime). No package does this.
//   * cellular IP → dart:io NetworkInterface.list(includeLinkLocal: true),
//     finding the conventional iOS cellular interface `pdp_ip0`. Apple does NOT
//     treat interface names as stable API, so this is a documented heuristic
//     (Pax brief §K): `pdp_ip0` is the conventional cellular name and works in
//     practice, but is labeled honestly and degrades to "No cellular interface"
//     when absent (Wi-Fi-only, airplane mode, or macOS which has none).
//
// Every field is nullable; a platform that cannot supply a value yields null and
// the UI renders the honest "Not available on this platform" / per-field state —
// never a fabricated 0 or placeholder (GL-005 / Truthfulness Audit).
//
// Web safety: imports `dart:io`, which does not exist on web. The screen guards
// construction behind `NetworkSupport.interfaceInfoSupported` (a `!kIsWeb`
// flag), so this code is never reached on web.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'device_info_format.dart';
import 'system_uptime_bridge.dart';

/// The conventional iOS cellular (PDP) interface name. Apple does not guarantee
/// interface-name stability, so this is a heuristic match (see Pax brief §K).
const String kCellularInterfaceName = 'pdp_ip0';

/// One IP address found on the cellular interface, with its family.
class CellularAddress {
  const CellularAddress({required this.ip, required this.isIPv4});

  final String ip;
  final bool isIPv4;
}

/// Immutable snapshot of the device's system facts at read time. Every field is
/// nullable so a platform (or permission) that cannot supply it yields null and
/// the UI shows the honest unavailable state.
class DeviceInfoSnapshot {
  const DeviceInfoSnapshot({
    this.modelName,
    this.modelIdentifier,
    this.osVersion,
    this.totalMemoryBytes,
    this.uptimeSeconds,
    this.cellularInterfaceName,
    this.cellularAddresses = const <CellularAddress>[],
    this.cellularInterfacePresent = false,
  });

  /// Human marketing model name where the platform exposes it (iOS
  /// `modelName` / macOS `modelName`), else null.
  final String? modelName;

  /// Raw model identifier (iOS `utsname.machine` e.g. "iPhone16,2"; macOS
  /// `model` e.g. "Mac15,3"). Shown beneath the marketing name as the precise
  /// identifier, else null.
  final String? modelIdentifier;

  /// Human OS version where the platform exposes a clean one — iOS
  /// `systemVersion` (e.g. "26.1"), macOS product major.minor[.patch] from
  /// NSProcessInfo (e.g. "26.1"), Android `version.release` (e.g. "14"),
  /// Windows `displayVersion` (e.g. "23H2") — else null. On macOS this is the
  /// PRODUCT version, never the Darwin kernel string (`osRelease`), which would
  /// misreport the OS.
  final String? osVersion;

  /// Total physical RAM in bytes (iOS `physicalRamSize` / macOS `memorySize`),
  /// or null when the platform does not report it.
  final int? totalMemoryBytes;

  /// Seconds since the device last booted, from the native uptime channel, or
  /// null where the platform has no handler.
  final double? uptimeSeconds;

  /// The cellular interface name matched (always [kCellularInterfaceName] when
  /// present), retained so the UI can name the heuristic honestly.
  final String? cellularInterfaceName;

  /// IP addresses bound to the cellular interface (usually one IPv4, sometimes
  /// an IPv6 too). Empty when no cellular interface is present.
  final List<CellularAddress> cellularAddresses;

  /// True when an interface named [kCellularInterfaceName] exists at all — even
  /// with no usable address — so the UI can distinguish "no cellular interface"
  /// from "cellular interface up but addressless".
  final bool cellularInterfacePresent;

  /// Convenience: total memory formatted human-readable (e.g. "8 GB"), or null.
  String? get totalMemoryLabel =>
      DeviceInfoFormat.formatBytes(totalMemoryBytes);

  /// Convenience: uptime formatted (e.g. "3d 4h 12m"), or null.
  String? get uptimeLabel => DeviceInfoFormat.formatUptime(uptimeSeconds);

  /// The first cellular IPv4, or null when none.
  String? get cellularIPv4 {
    for (final CellularAddress a in cellularAddresses) {
      if (a.isIPv4) return a.ip;
    }
    return null;
  }
}

/// Reads the device's system facts. Pure I/O, no UI — unit-testable by injecting
/// a fake interface lister and a fake uptime reader. The device_info_plus read
/// is platform-dispatched and individually guarded so one failing source never
/// blanks the whole screen.
class DeviceInfoService {
  DeviceInfoService({
    DeviceInfoPlugin? deviceInfo,
    SystemUptimeBridge? uptimeBridge,
    Future<List<NetworkInterface>> Function()? interfaceLister,
  })  : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _uptimeBridge = uptimeBridge ?? SystemUptimeBridge(),
        _interfaceLister = interfaceLister ?? _defaultLister;

  final DeviceInfoPlugin _deviceInfo;
  final SystemUptimeBridge _uptimeBridge;
  final Future<List<NetworkInterface>> Function() _interfaceLister;

  static Future<List<NetworkInterface>> _defaultLister() {
    // includeLinkLocal so the cellular interface is enumerated even when it only
    // holds a link-local address; includeLoopback false (lo0 is irrelevant).
    return NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );
  }

  /// Take a snapshot. Each sub-read is independently guarded so one failing
  /// source (e.g. the uptime channel on an unbuilt runner) never blanks the
  /// whole screen — that field comes back null and the rest still render.
  Future<DeviceInfoSnapshot> read() async {
    final ({String? name, String? id, int? memoryBytes, String? osVersion})
        model = await _readModelAndMemory();
    final double? uptime = await _readUptime();
    final ({
      String? name,
      List<CellularAddress> addrs,
      bool present
    }) cellular = await _readCellular();

    return DeviceInfoSnapshot(
      modelName: model.name,
      modelIdentifier: model.id,
      osVersion: model.osVersion,
      totalMemoryBytes: model.memoryBytes,
      uptimeSeconds: uptime,
      cellularInterfaceName: cellular.name,
      cellularAddresses: cellular.addrs,
      cellularInterfacePresent: cellular.present,
    );
  }

  /// Reads model + total memory + OS version from device_info_plus, dispatched
  /// per platform. Any failure yields all-null rather than throwing.
  Future<({String? name, String? id, int? memoryBytes, String? osVersion})>
      _readModelAndMemory() async {
    try {
      if (Platform.isIOS) {
        final IosDeviceInfo i = await _deviceInfo.iosInfo;
        return (
          name: _blankToNull(i.modelName),
          id: _blankToNull(i.utsname.machine),
          // physicalRamSize is bytes; 0 is not a real reading → null.
          memoryBytes: i.physicalRamSize > 0 ? i.physicalRamSize : null,
          // systemVersion is already the human iOS version (e.g. "26.1").
          osVersion: _blankToNull(i.systemVersion),
        );
      }
      if (Platform.isMacOS) {
        final MacOsDeviceInfo m = await _deviceInfo.macOsInfo;
        return (
          name: _blankToNull(m.modelName),
          id: _blankToNull(m.model),
          memoryBytes: m.memorySize > 0 ? m.memorySize : null,
          // The NSProcessInfo product version (e.g. "26.1"), NOT the Darwin
          // kernel string — see [formatMacOsVersion].
          osVersion: formatMacOsVersion(
              m.majorVersion, m.minorVersion, m.patchVersion),
        );
      }
      if (Platform.isAndroid) {
        final AndroidDeviceInfo a = await _deviceInfo.androidInfo;
        final String marketing = <String?>[a.manufacturer, a.model]
            .where((String? s) => s != null && s.trim().isNotEmpty)
            .map((String? s) => s!.trim())
            .join(' ');
        return (
          name: marketing.isEmpty ? null : marketing,
          id: _blankToNull(a.device),
          // Android total RAM is not surfaced by device_info_plus; honest null.
          memoryBytes: null,
          // version.release is the human Android version (e.g. "14").
          osVersion: _blankToNull(a.version.release),
        );
      }
      if (Platform.isWindows) {
        final WindowsDeviceInfo w = await _deviceInfo.windowsInfo;
        return (
          // productName is the human OS name (e.g. "Windows 11 Pro"); fall back
          // to the machine name when the registry value is blank. computerName
          // is the human-meaningful identifier — preferred over the opaque
          // MachineGuid `deviceId`.
          name: _blankToNull(w.productName) ?? _blankToNull(w.computerName),
          id: _blankToNull(w.computerName),
          // systemMemoryInMegabytes is MB → bytes; 0 is not a real reading.
          memoryBytes: w.systemMemoryInMegabytes > 0
              ? w.systemMemoryInMegabytes * 1024 * 1024
              : null,
          // displayVersion is the feature-update label (e.g. "23H2").
          osVersion: _blankToNull(w.displayVersion),
        );
      }
    } on Object {
      // Plugin missing / platform exception → all-null, honest unavailable.
    }
    return (name: null, id: null, memoryBytes: null, osVersion: null);
  }

  /// Formats the macOS PRODUCT version from device_info_plus's NSProcessInfo
  /// components (major.minor[.patch]) — the human OS version (e.g. "26.1"),
  /// NOT the Darwin kernel string (`osRelease` / `kernelVersion`), which would
  /// misreport the OS to a user comparing devices. A ".0" patch is dropped
  /// ("26.1.0" → "26.1"). Returns null when the components are unavailable
  /// (major <= 0, as on an unbuilt runner or non-macOS host) so the label
  /// degrades to the bare platform word rather than fabricating "0.0". Pure and
  /// static → unit-testable without the plugin, exactly like [parseCellular].
  static String? formatMacOsVersion(int major, int minor, int patch) {
    if (major <= 0) return null;
    final StringBuffer b = StringBuffer('$major.$minor');
    if (patch > 0) b.write('.$patch');
    return b.toString();
  }

  Future<double?> _readUptime() async {
    try {
      return await _uptimeBridge.read();
    } on Object {
      return null;
    }
  }

  /// Finds the cellular interface ([kCellularInterfaceName]) and its addresses.
  /// Absent interface → present:false, empty addresses (the honest "no cellular
  /// interface" state, expected on Wi-Fi-only / airplane-mode / macOS).
  Future<({String? name, List<CellularAddress> addrs, bool present})>
      _readCellular() async {
    final List<NetworkInterface> raw;
    try {
      raw = await _interfaceLister();
    } on Object {
      return (name: null, addrs: const <CellularAddress>[], present: false);
    }
    return parseCellular(raw);
  }

  /// Pure parse of an interface list → the cellular interface result. Exposed
  /// (not private) so it is unit-testable with a synthetic [NetworkInterface]
  /// list without touching `dart:io`'s real enumeration. Matches the cellular
  /// interface by exact name [kCellularInterfaceName] (the iOS convention).
  static ({String? name, List<CellularAddress> addrs, bool present})
      parseCellular(List<NetworkInterface> interfaces) {
    for (final NetworkInterface iface in interfaces) {
      if (iface.name != kCellularInterfaceName) continue;
      final List<CellularAddress> addrs = iface.addresses
          .map(
            (InternetAddress a) => CellularAddress(
              ip: a.address,
              isIPv4: a.type == InternetAddressType.IPv4,
            ),
          )
          .toList(growable: false);
      return (name: iface.name, addrs: addrs, present: true);
    }
    return (name: null, addrs: const <CellularAddress>[], present: false);
  }

  static String? _blankToNull(String? v) {
    if (v == null) return null;
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }
}
