// Client Capabilities — the three-tier resolver.
//
// Step 2 of the Client Capabilities build (spec:
// Deliverables/2026-07-31-client-capabilities-spec/SPEC.md). The model lives in
// `client_capabilities.dart`; this file decides WHO answers, in what order, and
// how two partial answers combine.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE THREE TIERS
//
//   1. Live platform query   the OS tells us            macOS, Android, Windows
//   2. Published table       per device model            iOS
//   3. Unknown               nothing available           anything unrecognised
//
// Tier 1 is preferred everywhere it exists. Tier 3 is not an error: it is the
// answer for a device nobody has published anything about, and it renders as
// "unknown" per field, never as a plausible default.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW A LOWER TIER IS PREVENTED FROM MASQUERADING AS A HIGHER ONE
//
// Readers do not merge. Each reader returns a complete [ClientCapabilities] in
// which every field it could not answer is an [UnknownCapability], and the
// service combines them with [ClientCapabilities.fillGapsFrom], which copies a
// field WITH ITS OWN tier and pin and never overwrites a field that is already
// known. So a tier-2 value that fills a tier-1 gap still says tier 2 on the
// screen, and a tier-1 value is never displaced by a table.
//
// Every parse in this file is a pure static function over a decoded payload, so
// the mapping is unit-testable with no channel, no plugin and no device. The
// only impure part is the one line that invokes the channel.

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException, rootBundle;

import 'client_capabilities.dart';
import 'wifi_details.dart' show WiFiBand;
import 'wifi_phy_rate_service.dart' show WifiStd;

/// One source of capability answers.
///
/// A reader ALWAYS returns a full capability set. Fields it cannot answer come
/// back unknown with a reason, so a caller can never mistake "this reader does
/// not do that field" for "this device does not have that capability".
abstract interface class CapabilityReader {
  /// Short identifier for logs and pins, e.g. `macOS CoreWLAN`.
  String get name;

  /// The tier this reader answers at.
  CapabilityTier get tier;

  /// Reads what it can. Never throws: a failure is an unknown with a reason.
  Future<ClientCapabilities> read();
}

/// Maps a Wi-Fi standard name to the enum the rate tables use.
///
/// Returns null for anything pre-HT (802.11a/b/g) or unrecognised. Pre-HT modes
/// have no entry in the rate tables, so there is nothing to compute from them.
WifiStd? wifiStdFromLabel(String? label) {
  switch (label?.trim().toLowerCase()) {
    case '802.11n':
    case '11n':
    case 'ht':
      return WifiStd.ht;
    case '802.11ac':
    case '11ac':
    case 'vht':
      return WifiStd.vht;
    case '802.11ax':
    case '11ax':
    case 'he':
      return WifiStd.he;
    case '802.11be':
    case '11be':
    case 'eht':
      return WifiStd.eht;
    default:
      return null;
  }
}

/// Every standard up to and including [top].
///
/// Used where a platform reports the mode currently NEGOTIATED rather than the
/// modes supported. A device running 802.11ax certainly supports 802.11n and
/// 802.11ac, so the negotiated mode is a floor on capability, and the caller
/// marks the result [CapabilityBound.atLeast] to say so.
Set<WifiStd> standardsUpToAndIncluding(WifiStd top) => WifiStd.values
    .where((WifiStd s) => s.index <= top.index)
    .toSet();

/// Maps a band label to [WiFiBand]. Returns null for anything unrecognised.
WiFiBand? wifiBandFromLabel(String? label) {
  final String? l = label?.trim();
  for (final WiFiBand b in WiFiBand.values) {
    if (b.label == l) return b;
  }
  switch (l) {
    case '2.4':
    case '2.4GHz':
      return WiFiBand.band24;
    case '5':
    case '5GHz':
      return WiFiBand.band5;
    case '6':
    case '6GHz':
      return WiFiBand.band6;
    default:
      return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier 1 — macOS, via CoreWLAN
// ─────────────────────────────────────────────────────────────────────────────

/// Reads capabilities from CoreWLAN through the existing
/// `com.wlanpros.toolbox/wifi_info` channel.
///
/// WHAT macOS CAN AND CANNOT ANSWER, and why the unknowns here are permanent
/// rather than unfinished work:
///
///  * BANDS and MAXIMUM CHANNEL WIDTH come from
///    `CWInterface.supportedWLANChannels()`, which Apple documents as "An array
///    of channels supported by the interface FOR THE ACTIVE COUNTRY CODE".
///    That last clause is the whole story. It is a REGULATORY read, not a
///    hardware read: a 6 GHz-capable MacBook sitting in a region with no 6 GHz
///    allocation enumerates no 6 GHz channels, and a region that permits only
///    narrow channels caps the widest width the same way. Publishing either as
///    exact would be a false negative about the user's own radio, manufactured
///    out of a question we did not ask. Both are therefore
///    [CapabilityBound.atLeast], permanently, and both say so on screen.
///    This is the same class of defect the Android reader guards below: a
///    platform answer narrowed by something the value cannot express.
///  * WI-FI GENERATIONS have no capability API. `activePHYMode()` reports the
///    mode currently negotiated, which is a FLOOR on what the radio can do, so
///    it is reported as [CapabilityBound.atLeast] and never as the exact set.
///  * SPATIAL STREAMS and MAXIMUM MCS INDEX have no public API at all. They are
///    [CapabilityUnknownReason.platformDoesNotExpose], permanently, and the
///    honest consequence is that macOS shows no theoretical ceiling.
///
/// One more limit worth naming: `CWChannelWidth` has no 320 MHz case, so a
/// Wi-Fi 7 Mac cannot report more than 160 MHz through this API. When the read
/// lands exactly on that ceiling the width is marked [CapabilityBound.atLeast],
/// because we cannot tell a genuine 160 MHz radio from a 320 MHz radio
/// described by a vocabulary that stops at 160.
class MacOsCapabilityReader implements CapabilityReader {
  /// Creates the reader. [invoke] defaults to the real method channel.
  MacOsCapabilityReader({Future<Object?> Function(String method)? invoke})
      : _invoke = invoke ?? _defaultInvoke;

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/wifi_info');

  static Future<Object?> _defaultInvoke(String method) =>
      _channel.invokeMethod<Object?>(method);

  final Future<Object?> Function(String method) _invoke;

  @override
  String get name => 'macOS CoreWLAN';

  @override
  CapabilityTier get tier => CapabilityTier.livePlatformQuery;

  @override
  Future<ClientCapabilities> read() async {
    try {
      final Object? payload = await _invoke('getWifiCapabilities');
      return parse(payload is Map ? payload : null);
    } on PlatformException catch (e) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: e.message ?? 'CoreWLAN channel error',
      );
    } on MissingPluginException {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.noReaderForPlatform,
        detail: 'No CoreWLAN handler is registered in this build',
      );
    }
  }

  /// Pure mapping from the Swift payload to the model. Testable with no device.
  ///
  /// Payload contract (`WifiInfoChannel.getWifiCapabilities`):
  ///   interfacePresent           bool
  ///   locationAuthorized         bool
  ///   supportedBands             List of '2.4 GHz' / '5 GHz' / '6 GHz'
  ///   maxChannelWidthMhz         int, or null when no channel reported one
  ///   widthVocabularyCeilingMhz  int, the largest width CWChannelWidth can
  ///                              express on the building SDK
  ///   activePhyMode              String, e.g. '802.11ax', or null
  static ClientCapabilities parse(Map<dynamic, dynamic>? payload) {
    if (payload == null) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: 'CoreWLAN returned no payload',
      );
    }
    final bool interfacePresent = payload['interfacePresent'] == true;
    final bool locationAuthorized = payload['locationAuthorized'] == true;
    if (!interfacePresent) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: 'This Mac reports no Wi-Fi interface',
      );
    }

    // Bands.
    final Object? rawBands = payload['supportedBands'];
    final Set<WiFiBand> bands = <WiFiBand>{};
    if (rawBands is List) {
      for (final Object? entry in rawBands) {
        final WiFiBand? b = wifiBandFromLabel(entry?.toString());
        if (b != null) bands.add(b);
      }
    }
    final Capability<Set<WiFiBand>> bandsCapability = bands.isEmpty
        ? Capability<Set<WiFiBand>>.unknown(
            locationAuthorized
                ? CapabilityUnknownReason.queryFailed
                : CapabilityUnknownReason.permissionNotGranted,
            detail: locationAuthorized
                ? 'CoreWLAN listed no supported channels'
                : 'Location Services must be on for macOS to list Wi-Fi '
                    'channels',
          )
        : Capability<Set<WiFiBand>>.known(
            bands,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'macOS CoreWLAN CWInterface.supportedWLANChannels(), '
                'channelBand of every supported channel. Apple scopes that '
                'list to the active country code, so it is a floor on the '
                'radio, not an exact reading of it',
            // A band absent from a region's channel list has not been ruled
            // out. See the H-1 note in the class comment.
            bound: CapabilityBound.atLeast,
          );

    // Maximum channel width, with the vocabulary-ceiling caveat.
    final int? width = _asInt(payload['maxChannelWidthMhz']);
    final int? ceiling = _asInt(payload['widthVocabularyCeilingMhz']);
    final Capability<int> widthCapability = width == null
        ? Capability<int>.unknown(
            locationAuthorized
                ? CapabilityUnknownReason.queryFailed
                : CapabilityUnknownReason.permissionNotGranted,
            detail: 'CoreWLAN reported no channel width',
          )
        : Capability<int>.known(
            width,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'macOS CoreWLAN CWInterface.supportedWLANChannels(), widest '
                'channelWidth of any supported channel. Apple scopes that list '
                'to the active country code, so it is a floor on the radio, '
                'not an exact reading of it',
            // ALWAYS a floor, for two independent reasons that push the same
            // way: the region may permit nothing wider (H-1), and
            // CWChannelWidth may not be able to SAY anything wider even if it
            // did. Neither is a property of the radio.
            bound: CapabilityBound.atLeast,
          );

    // Wi-Fi generations, from the negotiated mode, as a floor.
    final WifiStd? active = wifiStdFromLabel(payload['activePhyMode'] as String?);
    final Capability<Set<WifiStd>> standardsCapability = active == null
        ? const Capability<Set<WifiStd>>.unknown(
            CapabilityUnknownReason.platformDoesNotExpose,
            detail: 'macOS reports the mode in use, and right now that is not '
                'one the rate tables cover',
          )
        : Capability<Set<WifiStd>>.known(
            standardsUpToAndIncluding(active),
            tier: CapabilityTier.livePlatformQuery,
            pin: 'macOS CoreWLAN CWInterface.activePHYMode(), which reports '
                'the mode in use on this link, not the modes the radio '
                'supports',
            bound: CapabilityBound.atLeast,
          );

    return ClientCapabilities(
      bands: bandsCapability,
      standards: standardsCapability,
      maxChannelWidthMhz: widthCapability,
      spatialStreams: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'macOS publishes no spatial-stream count to apps',
      ),
      maxMcsIndex: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'macOS publishes no MCS index to apps',
      ),
      osReportedMaxPhyRateMbps: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'macOS reports the current transmit rate, not a maximum',
      ),
      notes: <String>[
        // H-1. Stated whenever either value derived from the channel list is
        // shown, because a floor with no sentence next to it renders as a bare
        // value and reads as exact.
        if (bands.isNotEmpty || width != null)
          'macOS lists the channels permitted by the region this Mac is set '
              'to, so a band or a width missing here may still be supported by '
              'the radio.',
        if (active != null)
          'macOS reports the Wi-Fi generation in use, not the generations the '
              'radio supports, so the list here is a floor.',
        if (width != null && ceiling != null && width >= ceiling)
          'The macOS channel-width vocabulary stops at $ceiling MHz, so a '
              'wider radio would still report $ceiling MHz here.',
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier 1 — Android, via WifiManager
// ─────────────────────────────────────────────────────────────────────────────

/// Reads capabilities from `WifiManager` through the existing
/// `com.wlanpros.toolbox/wifi_info` channel.
///
/// Android answers a different subset from macOS, and the difference matters:
///
///  * WI-FI GENERATIONS are a REAL capability query,
///    `WifiManager.isWifiStandardSupported()`, so the set is exact when the API
///    level supports the call.
///  * BANDS are partial. `is5GHzBandSupported()` and `is6GHzBandSupported()`
///    exist; there is NO 2.4 GHz equivalent. Reporting the set as exact would
///    render "5 GHz, 6 GHz" and read as "no 2.4 GHz", which is a false negative
///    manufactured out of a missing API. The set is therefore a floor.
///  * MAXIMUM SUPPORTED TX LINK SPEED is the platform's own ceiling figure,
///    which is a better anchor than anything we can reconstruct.
///  * MAXIMUM CHANNEL WIDTH, SPATIAL STREAMS and MAXIMUM MCS INDEX have no
///    public API.
class AndroidCapabilityReader implements CapabilityReader {
  /// Creates the reader. [invoke] defaults to the real method channel.
  AndroidCapabilityReader({Future<Object?> Function(String method)? invoke})
      : _invoke = invoke ?? _defaultInvoke;

  static const MethodChannel _channel =
      MethodChannel('com.wlanpros.toolbox/wifi_info');

  static Future<Object?> _defaultInvoke(String method) =>
      _channel.invokeMethod<Object?>(method);

  final Future<Object?> Function(String method) _invoke;

  @override
  String get name => 'Android WifiManager';

  @override
  CapabilityTier get tier => CapabilityTier.livePlatformQuery;

  @override
  Future<ClientCapabilities> read() async {
    try {
      final Object? payload = await _invoke('getWifiCapabilities');
      return parse(payload is Map ? payload : null);
    } on PlatformException catch (e) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: e.message ?? 'WifiManager channel error',
      );
    } on MissingPluginException {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.noReaderForPlatform,
        detail: 'No WifiManager handler is registered in this build',
      );
    }
  }

  /// Pure mapping from the Kotlin payload to the model.
  ///
  /// Payload contract (`MainActivity.getWifiCapabilities`). Every support flag
  /// is a NULLABLE bool: null means "this API level cannot answer", which is
  /// not the same as false and must never collapse into it.
  ///   apiLevel                    int
  ///   band5Supported              bool or null
  ///   band6Supported              bool or null
  ///   standard11n / 11ac / 11ax / 11be   bool or null
  ///   maxSupportedTxLinkSpeedMbps int or null
  static ClientCapabilities parse(Map<dynamic, dynamic>? payload) {
    if (payload == null) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: 'WifiManager returned no payload',
      );
    }
    final int? apiLevel = _asInt(payload['apiLevel']);

    // Bands. Only bands the OS AFFIRMS go in the set, and the set is always a
    // floor because Android has no 2.4 GHz query at all.
    final bool? band5 = _asBool(payload['band5Supported']);
    final bool? band6 = _asBool(payload['band6Supported']);
    final Set<WiFiBand> bands = <WiFiBand>{
      if (band5 == true) WiFiBand.band5,
      if (band6 == true) WiFiBand.band6,
    };
    final Capability<Set<WiFiBand>> bandsCapability =
        (band5 == null && band6 == null)
            ? const Capability<Set<WiFiBand>>.unknown(
                CapabilityUnknownReason.platformDoesNotExpose,
                detail: 'This Android version has no band-support query',
              )
            : Capability<Set<WiFiBand>>.known(
                bands,
                tier: CapabilityTier.livePlatformQuery,
                pin: 'Android WifiManager.is5GHzBandSupported() and '
                    'is6GHzBandSupported(). There is no 2.4 GHz equivalent, so '
                    'this list is a floor',
                bound: CapabilityBound.atLeast,
              );

    // Wi-Fi generations. A real capability query, so exact when every one of
    // the four answered, and a floor when some could not be asked.
    final Map<WifiStd, bool?> answers = <WifiStd, bool?>{
      WifiStd.ht: _asBool(payload['standard11n']),
      WifiStd.vht: _asBool(payload['standard11ac']),
      WifiStd.he: _asBool(payload['standard11ax']),
      WifiStd.eht: _asBool(payload['standard11be']),
    };
    final Set<WifiStd> supported = answers.entries
        .where((MapEntry<WifiStd, bool?> e) => e.value == true)
        .map((MapEntry<WifiStd, bool?> e) => e.key)
        .toSet();
    final bool anyAnswered =
        answers.values.any((bool? v) => v != null);
    final bool allAnswered =
        answers.values.every((bool? v) => v != null);
    final Capability<Set<WifiStd>> standardsCapability = !anyAnswered
        ? const Capability<Set<WifiStd>>.unknown(
            CapabilityUnknownReason.platformDoesNotExpose,
            detail: 'isWifiStandardSupported() needs Android 11 or later',
          )
        : Capability<Set<WifiStd>>.known(
            supported,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'Android WifiManager.isWifiStandardSupported(), asked once '
                'per generation',
            bound:
                allAnswered ? CapabilityBound.exact : CapabilityBound.atLeast,
          );

    final int? maxTx = _asInt(payload['maxSupportedTxLinkSpeedMbps']);
    final Capability<int> osRate = (maxTx == null || maxTx <= 0)
        ? const Capability<int>.unknown(
            CapabilityUnknownReason.queryFailed,
            detail: 'Android returned no maximum supported transmit rate. It '
                'is only reported while connected to Wi-Fi',
          )
        : Capability<int>.known(
            maxTx,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'Android WifiInfo.getMaxSupportedTxLinkSpeedMbps()',
          );

    return ClientCapabilities(
      bands: bandsCapability,
      standards: standardsCapability,
      maxChannelWidthMhz: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'Android publishes no maximum channel width to apps',
      ),
      spatialStreams: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'Android publishes no spatial-stream count to apps',
      ),
      maxMcsIndex: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'Android publishes no MCS index to apps',
      ),
      osReportedMaxPhyRateMbps: osRate,
      notes: <String>[
        if (band5 != null || band6 != null)
          'Android can be asked about 5 GHz and 6 GHz support but not about '
              '2.4 GHz, so 2.4 GHz is neither confirmed nor ruled out here.',
        if (apiLevel != null && apiLevel < 30)
          'This device runs Android API level $apiLevel. The per-generation '
              'support query needs API level 30.',
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier 2 — iOS, from Apple's published per-model table
// ─────────────────────────────────────────────────────────────────────────────

/// Looks the device up in the seeded Apple capability table.
///
/// iOS exposes no Wi-Fi capability API to third-party apps at all, which is why
/// it is the one platform that needs a table. Apple publishes the numbers in the
/// Platform Deployment guide, with literal columns for maximum channel bandwidth
/// and maximum MCS index. The consumer tech-spec pages are NOT the source: they
/// stop at "Wi-Fi 7 with 2x2 MIMO".
///
/// A model that is not in the table resolves to
/// [CapabilityUnknownReason.deviceNotInTable] on every field. It never falls
/// back to a similar model, and it never falls back to a typical value.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// THE LOOKUP KEY IS A MARKETING NAME, AND IT IS NOT THE ONE iOS HANDS YOU
///
/// Apple's table is keyed by marketing name ("iPhone 16 Pro"), so that is what
/// [deviceModelName] must be. iOS supplies `utsname.machine` ("iPhone17,1"),
/// `model` ("iPhone") and the user's chosen device name; it exposes NO API for
/// the marketing name. Passing a machine identifier here therefore misses every
/// row in the shipped table, which is an honest miss rather than a wrong answer,
/// but it is still a miss.
///
/// Closing that gap needs a SOURCED identifier-to-name mapping shipped as its
/// own pinned asset. That is a spec-level decision, not something this reader
/// should paper over: an unsourced mapping layer between two sourced facts is
/// precisely the seam a wrong row would enter through.
class PublishedTableCapabilityReader implements CapabilityReader {
  /// Creates the reader for [deviceModelName] (e.g. `iPhone 16 Pro`), reading
  /// [loadJson] for the table.
  PublishedTableCapabilityReader({
    required this.deviceModelName,
    required Future<String> Function() loadJson,
  })  :
        // The field is private, so an initializing formal would name the
        // parameter `_loadJson` at every call site. The lint's fix is worse
        // than the lint.
        // ignore: prefer_initializing_formals
        _loadJson = loadJson;

  /// The MARKETING model name to look up, e.g. `iPhone 16 Pro` — not the
  /// machine identifier. Null when the device could not be identified at all.
  ///
  /// See the class comment: a machine identifier passed here is a guaranteed
  /// miss, because no row in the shipped table is keyed by one.
  final String? deviceModelName;

  final Future<String> Function() _loadJson;

  @override
  String get name => 'Apple published specifications';

  @override
  CapabilityTier get tier => CapabilityTier.publishedTable;

  @override
  Future<ClientCapabilities> read() async {
    if (deviceModelName == null || deviceModelName!.trim().isEmpty) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.deviceNotInTable,
        detail: 'This device did not report a model name',
      );
    }
    final String raw;
    try {
      raw = await _loadJson();
    } on Object {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: 'The capability table could not be loaded',
        deviceName: deviceModelName,
      );
    }
    return parse(raw, deviceModelName!);
  }

  /// Pure lookup. Testable with a literal JSON string.
  ///
  /// Every row must carry a `source` string; a row without one is DROPPED
  /// rather than trusted, because an unsourced capability row is the exact
  /// thing the table exists to avoid.
  static ClientCapabilities parse(String rawJson, String deviceModelName) {
    final Map<String, Object?> root;
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return ClientCapabilities.allUnknown(
          CapabilityUnknownReason.queryFailed,
          detail: 'The capability table is not a JSON object',
          deviceName: deviceModelName,
        );
      }
      root = decoded.cast<String, Object?>();
    } on FormatException {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.queryFailed,
        detail: 'The capability table is not valid JSON',
        deviceName: deviceModelName,
      );
    }

    final Object? meta = root['_meta'];
    final String? tableVersion =
        meta is Map ? meta['last_updated']?.toString() : null;

    // Apple's table is keyed by MARKETING NAME ("iPhone 16 Pro"), so that is
    // what we match on. Keying by the machine identifier ("iPhone17,1") would
    // need a second mapping source that Apple does not publish in one place,
    // and an unsourced mapping layer between two sourced facts is exactly the
    // seam a wrong row would enter through.
    final Object? rows = root['devices'];
    Map<String, Object?>? row;
    bool matchedThroughOurExpansion = false;
    String? matchedName;
    final String target = _normalizeModelName(deviceModelName);
    if (rows is List) {
      // Verbatim Apple names first, so an exact source match always wins over
      // an expansion of ours.
      for (final Object? entry in rows) {
        if (entry is! Map) continue;
        final Map<String, Object?> candidate = entry.cast<String, Object?>();
        final String? hit = _matchingName(candidate['names'], target);
        if (hit != null) {
          row = candidate;
          matchedName = hit;
          break;
        }
      }
      if (row == null) {
        for (final Object? entry in rows) {
          if (entry is! Map) continue;
          final Map<String, Object?> candidate = entry.cast<String, Object?>();
          final String? hit =
              _matchingName(candidate['familyNames'], target);
          if (hit != null) {
            row = candidate;
            matchedName = hit;
            matchedThroughOurExpansion = true;
            break;
          }
        }
      }
    }
    if (row == null) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.deviceNotInTable,
        detail: '$deviceModelName is not in the table',
        deviceName: deviceModelName,
        tableVersion: tableVersion,
      );
    }

    final String source = row['source']?.toString().trim() ?? '';
    // The VERBATIM entry that matched, not `row['name']`. The shipped asset
    // carries no `name` key on any row, so reading one returned null for every
    // real device while the test fixture supplied it and hid that. Same defect
    // class as the `identifier` key in H-3, found by making the fixture
    // resemble the asset.
    final String? name = matchedName;
    if (source.isEmpty) {
      // A row with no source does not ship. Dropping it is the honest outcome:
      // the device is then simply not in the table.
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.deviceNotInTable,
        detail: '$deviceModelName has a row with no source, so it is not '
            'trusted',
        deviceName: name ?? deviceModelName,
        tableVersion: tableVersion,
      );
    }
    // The pin says HOW the row was matched, not just where the numbers came
    // from. A match through our own expansion of a phrase like "All iPhone 14
    // models" is a weaker link than a verbatim Apple name, and the reader of
    // the screen is entitled to know which one they are looking at.
    final String pin = matchedThroughOurExpansion
        ? '$source (row matched for $deviceModelName through our expansion of '
            "Apple's model-family wording, not a verbatim Apple name)"
        : '$source (row: $deviceModelName)';

    Capability<int> intField(String key) {
      final int? v = _asInt(row![key]);
      if (v == null) {
        return const Capability<int>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
          detail: 'The published table does not list this for this model',
        );
      }
      return Capability<int>.known(
        v,
        tier: CapabilityTier.publishedTable,
        pin: pin,
      );
    }

    final Object? rawBands = row['bands'];
    final Set<WiFiBand> bands = <WiFiBand>{};
    if (rawBands is List) {
      for (final Object? b in rawBands) {
        final WiFiBand? parsed = wifiBandFromLabel(b?.toString());
        if (parsed != null) bands.add(parsed);
      }
    }

    final Object? rawStds = row['standards'];
    final Set<WifiStd> stds = <WifiStd>{};
    if (rawStds is List) {
      for (final Object? s in rawStds) {
        final WifiStd? parsed = wifiStdFromLabel(s?.toString());
        if (parsed != null) stds.add(parsed);
      }
    }

    return ClientCapabilities(
      bands: bands.isEmpty
          ? const Capability<Set<WiFiBand>>.unknown(
              CapabilityUnknownReason.deviceNotInTable,
              detail: 'The published table lists no bands for this model',
            )
          : Capability<Set<WiFiBand>>.known(
              bands,
              tier: CapabilityTier.publishedTable,
              pin: pin,
            ),
      standards: stds.isEmpty
          ? const Capability<Set<WifiStd>>.unknown(
              CapabilityUnknownReason.deviceNotInTable,
              detail: 'The published table lists no generations for this model',
            )
          : Capability<Set<WifiStd>>.known(
              stds,
              tier: CapabilityTier.publishedTable,
              pin: pin,
            ),
      maxChannelWidthMhz: intField('maxChannelWidthMhz'),
      spatialStreams: intField('spatialStreams'),
      maxMcsIndex: intField('maxMcsIndex'),
      osReportedMaxPhyRateMbps: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
        detail: 'iOS reports no maximum rate to apps',
      ),
      deviceName: name,
      tableVersion: tableVersion,
      notes: <String>[
        if (tableVersion != null)
          'These figures come from a table we ship, last checked '
              '$tableVersion. They describe the model, not the radio in front '
              'of you.',
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The service
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the capabilities of the device the app is running on.
///
/// Picks the readers for the current platform, runs them in tier order, and
/// combines them so each field keeps the provenance of whichever reader
/// answered it. A platform with no reader resolves to
/// [CapabilityUnknownReason.noReaderForPlatform] on every field, which is tier
/// 3 and a legitimate answer.
class ClientCapabilityService {
  /// Creates the service.
  ///
  /// [readersOverride] replaces the per-platform reader list wholesale, which
  /// is how tests exercise the merge without any platform at all.
  ClientCapabilityService({
    TargetPlatform? platformOverride,
    List<CapabilityReader>? readersOverride,
    bool? isWebOverride,
  })  : _platform = platformOverride ?? defaultTargetPlatform,
        // Same reason as above: the field is private and an initializing
        // formal would force `_readersOverride:` on every caller.
        // ignore: prefer_initializing_formals
        _readersOverride = readersOverride,
        _isWeb = isWebOverride ?? kIsWeb;

  final TargetPlatform _platform;
  final List<CapabilityReader>? _readersOverride;
  final bool _isWeb;

  /// The readers that apply, strongest tier first.
  ///
  /// [deviceModelName] is the MARKETING name, because that is what the published
  /// table is keyed by. Passing a machine identifier here misses every row.
  List<CapabilityReader> readersFor({String? deviceModelName}) {
    if (_readersOverride != null) return _readersOverride;
    if (_isWeb) return const <CapabilityReader>[];
    switch (_platform) {
      case TargetPlatform.macOS:
        return <CapabilityReader>[MacOsCapabilityReader()];
      case TargetPlatform.android:
        return <CapabilityReader>[AndroidCapabilityReader()];
      case TargetPlatform.iOS:
        return <CapabilityReader>[
          PublishedTableCapabilityReader(
            deviceModelName: deviceModelName,
            loadJson: loadAppleCapabilityTable,
          ),
        ];
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const <CapabilityReader>[];
    }
  }

  /// Path of the shipped Apple capability table.
  static const String appleCapabilityTableAsset =
      'assets/data/client_capabilities_apple.json';

  /// Loads the shipped Apple capability table from the bundle.
  static Future<String> loadAppleCapabilityTable() =>
      rootBundle.loadString(appleCapabilityTableAsset);

  /// Reads every applicable reader and merges the results.
  ///
  /// [deviceIdentifier] and [deviceName] come from the device-info layer; they
  /// are passed in rather than read here so this service stays free of plugins.
  ///
  /// The published table is looked up by [deviceName], the MARKETING name, not
  /// by [deviceIdentifier]. Handing the machine identifier to the table reader
  /// was H-3: it misses every row, on every device. iOS does not supply a
  /// marketing name, so tier 2 stays inert on iOS until a sourced
  /// identifier-to-name mapping ships.
  Future<ClientCapabilities> resolve({
    String? deviceIdentifier,
    String? deviceName,
  }) async {
    final List<CapabilityReader> readers =
        readersFor(deviceModelName: deviceName);
    if (readers.isEmpty) {
      return ClientCapabilities.allUnknown(
        CapabilityUnknownReason.noReaderForPlatform,
        detail: 'The Toolbox has no capability reader for this platform yet',
        deviceIdentifier: deviceIdentifier,
        deviceName: deviceName,
      );
    }
    ClientCapabilities? merged;
    for (final CapabilityReader reader in readers) {
      final ClientCapabilities result = await reader.read();
      merged = merged == null ? result : merged.fillGapsFrom(result);
    }
    final ClientCapabilities out = merged!;
    // Attach identity without touching any resolved field.
    return ClientCapabilities(
      bands: out.bands,
      standards: out.standards,
      maxChannelWidthMhz: out.maxChannelWidthMhz,
      spatialStreams: out.spatialStreams,
      maxMcsIndex: out.maxMcsIndex,
      osReportedMaxPhyRateMbps: out.osReportedMaxPhyRateMbps,
      deviceIdentifier: out.deviceIdentifier ?? deviceIdentifier,
      deviceName: out.deviceName ?? deviceName,
      tableVersion: out.tableVersion,
      notes: out.notes,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tolerant scalar parsing. A value we cannot read is null, never a default.
// ─────────────────────────────────────────────────────────────────────────────

/// Lower-cases and collapses whitespace so "iPhone  16 Pro" and "iphone 16 pro"
/// match the same row. Nothing else is stripped: parentheses and generation
/// words are load-bearing in Apple's names.
String _normalizeModelName(String? name) =>
    (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The VERBATIM entry in [list] matching [normalizedTarget], or null.
///
/// Returns the entry rather than a bool so the caller can report the name the
/// table actually carries, instead of echoing back whatever the caller typed.
String? _matchingName(Object? list, String normalizedTarget) {
  if (list is! List || normalizedTarget.isEmpty) return null;
  for (final Object? entry in list) {
    final String? text = entry?.toString();
    if (_normalizeModelName(text) == normalizedTarget) return text;
  }
  return null;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.round() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

bool? _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) {
    if (v == 1) return true;
    if (v == 0) return false;
    return null;
  }
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return null;
}
