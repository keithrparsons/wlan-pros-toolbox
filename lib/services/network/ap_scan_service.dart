import 'dart:async';
// Conditional import: dart:io provides Platform on native targets and is stubbed
// out on web, mirroring wifi_info_service.dart. Platform is only read off web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a scan row's BSSID field tells us about that row.
///
/// THREE outcomes, not two. Collapsing the last two was a real defect: a single
/// malformed row with no `bssid` key revoked the grant for the whole scan,
/// destroying two good APs and blaming Location for a parse failure.
enum BssidIdentity {
  /// A real, parseable AP MAC.
  valid,

  /// The OS deliberately BLANKED it. A permission signal: the radio saw the AP,
  /// we lost the right to name it. Gates the snapshot.
  withheld,

  /// Absent or unparseable. A MALFORMED row and nothing more — it carries no
  /// statement about permission, so it must never gate the scan.
  unreadable,
}

/// Classifies a scan row's BSSID.
///
/// Withheld covers the forms this codebase already rejects in six other places
/// (MainActivity.kt `sanitizeBssid`, arp_ndp_service.dart, windows_arp_ffi.dart,
/// windows_wifi_ffi.dart `_decodeBssid`):
///   * an explicit null or a blank string — macOS strips SSID and BSSID
///     together without Location, and Android blanks rather than garbles.
///   * 00:00:00:00:00:00 — the all-zero MAC, never a real radio.
///   * 02:00:00:00:00:00 — MainActivity.kt:641 names it exactly: "the 'no
///     permission' placeholder BSSID".
///
/// The line between withheld and unreadable is BLANKED vs GARBLED. A blank is
/// something an OS does deliberately when it withholds. A value like "unknown"
/// or a truncated MAC is a row we simply cannot read; treating those as a
/// permission signal would blame Location for a parse bug, and treating them as
/// valid would render them as cloaking APs — the original defect.
///
/// Separators and case are normalized, so `AA-BB-…`, `aa:bb:…` and Cisco dotted
/// `0200.0000.0000` cannot slip past on formatting alone.
BssidIdentity classifyBssid(Map<dynamic, dynamic> row) {
  // ABSENT is not WITHHELD. A row that never carried the key is malformed; an
  // OS that withholds sets the key and blanks the value.
  if (!row.containsKey('bssid')) return BssidIdentity.unreadable;

  final Object? raw = row['bssid'];
  if (raw == null) return BssidIdentity.withheld;
  if (raw is! String) return BssidIdentity.unreadable;
  if (raw.trim().isEmpty) return BssidIdentity.withheld;

  final String bare = raw.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');
  if (bare == '000000000000' || bare == '020000000000') {
    return BssidIdentity.withheld;
  }
  // A MAC is 12 hex digits once separators are stripped. Anything else is a
  // value we cannot read, NOT a permission signal.
  return bare.length == 12 ? BssidIdentity.valid : BssidIdentity.unreadable;
}

/// Whether a BSSID VALUE is one the OS withheld. Value-level convenience over
/// [classifyBssid]; it cannot see an absent key, so prefer the row form when
/// classifying a payload.
bool isWithheldBssid(String? bssid) =>
    classifyBssid(<String, Object?>{'bssid': bssid}) == BssidIdentity.withheld;

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

  /// The network name, or null for a HIDDEN network — a BSS that is really
  /// cloaking its SSID. The UI shows "(hidden network)" for null.
  ///
  /// A null [ssid] is an RF claim about the AP, so it may only ever mean
  /// "this AP does not broadcast its name". It must NEVER stand in for "the OS
  /// withheld the name from us", which is a PERMISSION fact. The discriminator
  /// is [bssid]: a genuinely hidden BSS still reports a BSSID, whereas a BSS
  /// whose identity was withheld reports neither. Because [bssid] is
  /// non-nullable and enforced by [fromMap], a withheld row cannot be built at
  /// all — so a rendered null [ssid] can only mean cloaked
  /// ([[feedback_app_blames_the_wifi]]).
  final String? ssid;

  /// The AP MAC address (BSSID). NON-NULLABLE by design: a scan row with no
  /// BSSID is one whose identity the OS withheld (macOS revokes SSID and BSSID
  /// together when Location is lost), and such a row cannot be described
  /// honestly — it would render as a cloaking AP that does not exist. [fromMap]
  /// drops those rows instead of admitting them to the model.
  final String bssid;

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
  ///
  /// A missing or empty `bssid` drops the row. That is the load-bearing case,
  /// not a formality: macOS withholds the SSID AND the BSSID of every scanned
  /// BSS when Location is revoked, so such a row carries a null SSID for a
  /// PERMISSION reason. Admitting it would render "(hidden network)" — an
  /// affirmative claim that the AP is cloaking — over a fact about our own
  /// grant. Dropping it keeps the only honest discriminator intact: a real
  /// hidden BSS still has a BSSID ([[feedback_app_blames_the_wifi]]).
  static ScannedAp? fromMap(Map<dynamic, dynamic> map) {
    final int? rssi = (map['rssiDbm'] as num?)?.toInt();
    final int? channel = (map['channel'] as num?)?.toInt();
    final String? band = map['band'] as String?;
    final int? freq = (map['frequencyMhz'] as num?)?.toInt();
    final String? bssid = map['bssid'] as String?;
    if (rssi == null || channel == null || band == null || freq == null) {
      return null;
    }
    // ONLY a VALID identity is admitted. Testing "not withheld" here was a bug:
    // it let garbled values ("unknown", a truncated MAC) through as real APs,
    // and a garbled BSSID beside a null SSID rendered as a cloaking AP — the
    // original defect, reached through the third class rather than the second.
    // The explicit null test is what promotes `bssid` to non-null below; flow
    // analysis does not see through classifyBssid.
    if (bssid == null || classifyBssid(map) != BssidIdentity.valid) return null;
    return ScannedAp(
      ssid: map['ssid'] as String?,
      bssid: bssid,
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

/// THE ONE VERDICT a scan snapshot supports — what the screen is entitled to
/// tell the user happened.
///
/// WHY THIS EXISTS. Three separate fixes to this screen each closed a real
/// defect and opened a new false claim one axis over, because each added a
/// STATE without re-walking the state matrix. The screen decided its cards from
/// independent `if`s, so "exactly one verdict renders" was a property nobody
/// owned: adding a state silently created combinations that rendered two
/// verdicts, or none.
///
/// Deriving the verdict here makes that structural. The screen switches over
/// this enum, so it renders exactly one verdict card by construction, and a
/// fourth state cannot be added without extending this enum and failing the
/// switch to compile. The cross-product test
/// (test/screens/tools/network/ap_scan_verdict_matrix_test.dart) walks the full
/// matrix and asserts one card, never zero, never two.
enum ApScanVerdict {
  /// The radio is off. Nothing was measured.
  radioOff,

  /// The Location grant is missing or was withheld mid-scan. Nothing was
  /// measured — this is NEVER an empty RF environment.
  permissionMissing,

  /// The scan ran, the radio reported rows, and not one could be read. The RF
  /// environment is UNKNOWN, not empty.
  noneReadable,

  /// NO SCAN HAS RUN YET, and the OS scan cache is empty.
  ///
  /// The screen's first load reads the cache rather than triggering a scan, and
  /// that cache is empty on a machine which has not scanned since boot. Reading
  /// an empty cache as "nothing in range" told the user a scan ran and found an
  /// empty RF environment when nothing had been measured at all — and held that
  /// false verdict on screen for the entire duration of the first real scan.
  /// An empty cache is not a scan result ([[feedback_app_blames_the_wifi]]).
  noScanYet,

  /// The scan ran, everything the radio reported was read, and there was
  /// nothing on the air. The only state entitled to say "no networks found".
  nothingInRange,

  /// The scan ran and found APs. The list is the verdict.
  apsFound,
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
    this.unreadableCount = 0,
    this.scanPerformed = true,
  }) : assert(
          locationAuthorized || accessPoints.length == 0,
          'A snapshot cannot carry access points while locationAuthorized is '
          'false: the gate card says the scan could not run, so a list beside '
          'it contradicts it. Drop the rows or fix the flag.',
        );

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

  /// How many rows the radio reported that could not be parsed into an honest
  /// [ScannedAp] — a missing or unrecognized channel or band, a 0 dBm "no
  /// measurement" RSSI, an absent or unparseable BSSID, or an entry that was
  /// not a map at all.
  ///
  /// TODO(keith-decision): this count is structurally 0 on macOS, and possibly
  /// on Android too. Both native layers already drop these rows before building
  /// the payload (ApScanChannel.swift `mapNetwork`/`mapNetworks` — including
  /// the 6 GHz `.bandUnknown` case in `bandString` — and MainActivity.kt
  /// `mapScanResult`), so the causes
  /// named above cannot raise it from the platform being field-tested, and the
  /// causes that CAN raise it are Dart-side only. The choice is between having
  /// the native layers report what they dropped, or deleting this field and the
  /// UI it feeds and correcting the copy. See the gate #4 QA report (F-2/F-3/
  /// F-4). Not decided here; it is an architecture call.
  ///
  /// Carried so the UI can DISCLOSE the shortfall. A scan that silently drops
  /// rows presents a short list as a complete one, which under-reports the RF
  /// environment just as surely as a fabricated row over-reports it. The count
  /// never includes withheld identities: those gate the whole snapshot via
  /// [locationAuthorized] instead of being dropped.
  final int unreadableCount;

  /// Whether a scan was actually REQUESTED to produce this snapshot.
  ///
  /// False for [ApScanService.lastResults], which reads the OS scan cache
  /// without asking the radio to do anything. That cache is empty on a machine
  /// which has not scanned since boot, and an empty cache is not a measurement:
  /// without this flag the screen's first load reported "the scan ran and found
  /// no access points in range" before any scan had run, and held that claim
  /// for the whole duration of the first real scan.
  ///
  /// Defaults true because every other construction site describes a scan that
  /// did happen; only the cache read has to say otherwise.
  final bool scanPerformed;

  /// The single verdict this snapshot supports.
  ///
  /// Order is precedence, and it is load-bearing. A missing grant outranks an
  /// empty list, because without the grant the emptiness was never measured.
  /// Unread rows outrank "nothing in range" for the same reason one axis over:
  /// the radio DID report something, so the environment is unknown rather than
  /// empty. Getting this order wrong is exactly how "no access points in range"
  /// came to be printed to a user standing among APs
  /// ([[feedback_app_blames_the_wifi]]).
  ApScanVerdict get verdict {
    if (!poweredOn) return ApScanVerdict.radioOff;
    if (!locationAuthorized) return ApScanVerdict.permissionMissing;
    if (accessPoints.isNotEmpty) return ApScanVerdict.apsFound;
    if (unreadableCount > 0) return ApScanVerdict.noneReadable;
    // An empty result only means "nothing in range" if something actually
    // looked. Reading the OS cache is not looking.
    if (!scanPerformed) return ApScanVerdict.noScanYet;
    return ApScanVerdict.nothingInRange;
  }

  /// Builds a snapshot from the native channel payload.
  /// [scanPerformed] records whether the caller ASKED the radio to scan, which
  /// the payload itself cannot say: a cache read and a completed scan return
  /// the same shape, and an empty one means very different things in each case.
  factory ApScanSnapshot.fromMap(
    Map<dynamic, dynamic> map, {
    bool scanPerformed = true,
  }) {
    final List<dynamic> rawAps =
        (map['accessPoints'] as List<dynamic>?) ?? const <dynamic>[];
    final List<Map<dynamic, dynamic>> rows =
        rawAps.whereType<Map<dynamic, dynamic>>().toList();

    // A WITHHELD IDENTITY IS EVIDENCE THE GRANT IS COMPROMISED — so it gates
    // the snapshot; it does not quietly delete the row.
    //
    // Dropping these rows was the tempting fix and it is the wrong one. On
    // Android the placeholder BSSIDs genuinely occur, so dropping would silently
    // shrink the list and under-report the RF environment — trading a false
    // identity for a false COUNT, which is the same lie wearing a different hat.
    // The radio saw those APs. What we lost was permission to name them, and
    // "we lost permission" is the Location card, not a discard.
    final bool identityWithheld = rows.any((Map<dynamic, dynamic> r) =>
        classifyBssid(r) == BssidIdentity.withheld);

    final List<ScannedAp> aps = rows
        .map(ScannedAp.fromMap)
        .whereType<ScannedAp>()
        .toList();

    // Rows the radio reported that we could not parse at all (no channel, no
    // band, or CoreWLAN's 0 dBm "no measurement"). Unlike a withheld identity
    // these carry no permission signal — they are simply undescribable — so
    // they are dropped, and the count travels with the snapshot so the UI can
    // SAY so rather than presenting a short list as a complete one.
    // Entries that were not even maps never reached `rows`, so they used to
    // vanish before anything could count them — a silent discard upstream of
    // the disclosure. They are unreadable rows like any other.
    final int nonMapRows = rawAps.length - rows.length;
    final int unreadableCount = (rows.length - aps.length) + nonMapRows;

    final bool locationAuthorized =
        ((map['locationAuthorized'] as bool?) ?? false) && !identityWithheld;
    return ApScanSnapshot(
      // Rows are only meaningful when the grant that produced them is held.
      // A channel that reports rows alongside locationAuthorized:false is
      // describing a scan whose results the OS has since withheld; keeping the
      // rows would render an AP list DIRECTLY BELOW a card saying the scan
      // could not run. The flag wins, because it is the one the gate cards
      // speak from.
      accessPoints: locationAuthorized ? aps : const <ScannedAp>[],
      poweredOn: (map['poweredOn'] as bool?) ?? false,
      locationAuthorized: locationAuthorized,
      scanThrottled: (map['scanThrottled'] as bool?) ?? false,
      unreadableCount: locationAuthorized ? unreadableCount : 0,
      scanPerformed: scanPerformed,
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
  /// THE SINGLE SOURCE OF TRUTH for scan platform support. `kNativeScanPlatforms`
  /// in lib/data/tool_catalog.dart is DERIVED from this set, not copied beside
  /// it — an earlier version said "mirrors ApScanService" in a comment, and a
  /// mutation that desynced the two was caught by nothing in the suite. A rule
  /// stated in prose is a rule the next maker sincerely believes they followed
  /// (GL-013). Edit this set and the catalog follows automatically.
  ///
  /// Values are `Platform.operatingSystem` strings. Windows is deliberately
  /// absent. Its enumeration path exists ([WindowsWifiReader.scanNearbyBss]) but
  /// is written-not-executed against real hardware, and unverified code does not
  /// go live ([[feedback_gate_until_clean]]).
  static const Set<String> wiredPlatforms = <String>{'android', 'macos'};

  final Future<Object?> Function(String method, [dynamic args]) _invoke;
  final Future<Object?> Function(String method, [dynamic args])
      _invokeWifiInfo;
  final String _platform;

  /// Whether this platform supports a nearby-AP scan. Android and macOS.
  bool get isSupportedPlatform =>
      !kIsWeb && wiredPlatforms.contains(_platform);

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
  Future<ApScanSnapshot> scan() => _read('scan', scanPerformed: true);

  /// Returns the last cached scan without requesting a fresh one.
  ///
  /// This does NOT ask the radio to do anything, so the resulting snapshot
  /// carries `scanPerformed: false`. An empty answer here means the OS cache is
  /// empty — typically a machine that has not scanned since boot — and must not
  /// be reported as an empty RF environment.
  Future<ApScanSnapshot> lastResults() =>
      _read('lastResults', scanPerformed: false);

  Future<ApScanSnapshot> _read(
    String method, {
    required bool scanPerformed,
  }) async {
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
      return ApScanSnapshot.fromMap(map, scanPerformed: scanPerformed);
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
