// Client Capabilities — resolver tests.
//
// ─────────────────────────────────────────────────────────────────────────────
// EXPECTED VALUES, WRITTEN BEFORE THE TESTS
//
// R1. macOS, a Wi-Fi 6E MacBook reporting 2.4/5/6 GHz channels, a widest
//     supported width of 80 MHz, a vocabulary ceiling of 160 MHz, and an active
//     PHY mode of 802.11ax:
//       bands              KNOWN {2.4, 5, 6}, tier 1, AT LEAST
//                          (H-1: supportedWLANChannels() is scoped to the
//                          ACTIVE COUNTRY CODE, so it is a regulatory read and
//                          a band it omits has not been ruled out)
//       generations        KNOWN {ht, vht, he}, tier 1, AT LEAST
//                          (the mode in use is a floor on what is supported)
//       max channel width  KNOWN 80, tier 1, AT LEAST
//                          (H-1: same country-code scope. A region that permits
//                          nothing wider caps this independently of the radio,
//                          so it is a floor at EVERY width, not only at the
//                          vocabulary ceiling.)
//       spatial streams    UNKNOWN platformDoesNotExpose
//       max MCS index      UNKNOWN platformDoesNotExpose
//       theoretical rate   UNKNOWN derivedInputUnknown, naming spatial streams
//
// R2. The same Mac reporting 160 MHz, which IS the vocabulary ceiling:
//       max channel width  KNOWN 160, tier 1, AT LEAST, and the note naming
//                          the 160 MHz vocabulary limit is present ON TOP OF
//                          the standing regional note
//
// R3. macOS with Location denied and an empty channel list:
//       bands              UNKNOWN permissionNotGranted, not queryFailed
//
// R4. Android 33 reporting 5 GHz true, 6 GHz false, 11n/11ac/11ax true,
//     11be false, max supported Tx 2402:
//       bands              KNOWN {5 GHz}, AT LEAST
//                          (there is no 2.4 GHz query, so the list is a floor
//                          and must NOT be read as "no 2.4 GHz")
//       generations        KNOWN {ht, vht, he}, EXACT (all four answered)
//       OS-reported rate   KNOWN 2402, tier 1
//
// R5. Android 29, where isWifiStandardSupported does not exist:
//       generations        UNKNOWN platformDoesNotExpose
//       and NOT an empty set, which would read as "supports nothing"
//
// R6. iOS table lookup for a model that is present, with a source:
//       every listed field KNOWN at tier 2, each pin containing the row source
//
// R7. iOS table lookup for a model that is absent:
//       every field        UNKNOWN deviceNotInTable
//       and no field from any other row leaks in
//
// R8. iOS table row present but with an EMPTY source string:
//       every field        UNKNOWN deviceNotInTable
//       a row without a pin does not ship, per the spec's table rules
//
// R9. A platform with no reader (Linux) resolves to noReaderForPlatform on
//     every field, which is tier 3 and a legitimate answer, not an error.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/client_capabilities.dart';
import 'package:wlan_pros_toolbox/services/network/client_capability_resolver.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart'
    show WiFiBand;
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart'
    show WifiStd;

Map<String, Object?> _macPayload({
  List<String> bands = const <String>['2.4 GHz', '5 GHz', '6 GHz'],
  int? maxWidth = 80,
  int ceiling = 160,
  String? phyMode = '802.11ax',
  bool interfacePresent = true,
  bool locationAuthorized = true,
}) =>
    <String, Object?>{
      'interfacePresent': interfacePresent,
      'locationAuthorized': locationAuthorized,
      'supportedBands': bands,
      'maxChannelWidthMhz': maxWidth,
      'widthVocabularyCeilingMhz': ceiling,
      'activePhyMode': phyMode,
      'supportedChannelCount': bands.length * 10,
    };

Map<String, Object?> _androidPayload({
  int apiLevel = 33,
  bool? band5 = true,
  bool? band6 = false,
  bool? n = true,
  bool? ac = true,
  bool? ax = true,
  bool? be = false,
  int? maxTx = 2402,
}) =>
    <String, Object?>{
      'apiLevel': apiLevel,
      'band5Supported': band5,
      'band6Supported': band6,
      'standard11n': n,
      'standard11ac': ac,
      'standard11ax': ax,
      'standard11be': be,
      'maxSupportedTxLinkSpeedMbps': maxTx,
    };

/// A minimal two-row table, so a miss cannot be confused with an empty file.
///
/// H-3. This fixture is SHAPED LIKE THE SHIPPED ASSET, and that is load-bearing
/// rather than tidy. It previously keyed both rows on an `identifier` field
/// (`"iPhone16,1"`) that the shipped asset carries on ZERO rows, so the whole
/// tier-2 suite proved a lookup path production can never take, while the path
/// production DOES take went untested. A fixture that does not resemble the
/// asset hides the defect it was written to catch.
///
/// The lookup key is a MARKETING NAME, because that is what Apple's table is
/// keyed by. `_assetRowKeysAreASupersetOfTheFixture` below fails if the asset
/// and this fixture ever drift apart again.
const String _tableJson = '''
{
  "_meta": { "last_updated": "2026-08-02" },
  "devices": [
    {
      "names": ["iPhone 15 Pro", "iPhone 15 Pro Max"],
      "familyNames": [],
      "bands": ["2.4 GHz", "5 GHz", "6 GHz"],
      "standards": ["802.11n", "802.11ac", "802.11ax"],
      "maxChannelWidthMhz": 160,
      "spatialStreams": 2,
      "maxMcsIndex": 11,
      "source": "Apple Platform Deployment, Wi-Fi specifications"
    },
    {
      "names": ["unsourced device"],
      "familyNames": [],
      "bands": ["2.4 GHz", "5 GHz"],
      "standards": ["802.11ax"],
      "maxChannelWidthMhz": 80,
      "spatialStreams": 2,
      "maxMcsIndex": 11,
      "source": ""
    }
  ]
}
''';

void main() {
  group('macOS tier 1', () {
    test('R1: reports what CoreWLAN knows and admits what it does not', () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload());

      expect(caps.bands.valueOrNull,
          <WiFiBand>{WiFiBand.band24, WiFiBand.band5, WiFiBand.band6});
      expect(caps.bands.tierOrNull, CapabilityTier.livePlatformQuery);
      expect(
        caps.bands.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'H-1: the channel list is scoped to the active country code',
      );

      expect(caps.standards.valueOrNull,
          <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he});
      expect(
        caps.standards.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'activePHYMode is the mode in use, so the set is a floor',
      );

      expect(caps.maxChannelWidthMhz.valueOrNull, 80);
      expect(
        caps.maxChannelWidthMhz.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'H-1: 80 MHz is the widest channel this REGION permits, which '
            'is not the widest channel the radio supports',
      );

      expect(caps.spatialStreams.valueOrNull, isNull);
      expect(
        (caps.spatialStreams as UnknownCapability<int>).reason,
        CapabilityUnknownReason.platformDoesNotExpose,
      );
      expect(caps.maxMcsIndex.valueOrNull, isNull);

      // The consequence: macOS shows no ceiling, and says which value is
      // missing rather than inventing one.
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;
      expect(rate.valueOrNull, isNull);
      expect(
        (rate as UnknownCapability<double>).reason,
        CapabilityUnknownReason.derivedInputUnknown,
      );
      expect(rate.detail, 'spatial streams');
    });

    test('every known field carries a non-empty pin naming CoreWLAN', () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload());
      for (final MapEntry<String, Capability<Object>> e
          in caps.allFields.entries) {
        final Capability<Object> c = e.value;
        if (c is! KnownCapability<Object>) continue;
        expect(c.pin.trim(), isNotEmpty, reason: '${e.key} has a blank pin');
        expect(c.pin.contains('CoreWLAN'), isTrue,
            reason: '${e.key} does not name where it came from');
      }
    });

    test('R2: a width AT the vocabulary ceiling is a floor, not an exact value',
        () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload(maxWidth: 160));
      expect(caps.maxChannelWidthMhz.valueOrNull, 160);
      expect(caps.maxChannelWidthMhz.boundOrNull, CapabilityBound.atLeast);
      expect(
        caps.notes.any((String n) => n.contains('160 MHz')),
        isTrue,
        reason: 'the screen needs the reason next to the number',
      );
    });

    // Was 'a width below the ceiling stays exact'. That assertion ENSHRINED
    // H-1: it proved the width was exact whenever the vocabulary ceiling was
    // not reached, which is exactly the false claim. What the original test was
    // really guarding is that the two reasons are DISTINCT and reported
    // separately, so that is what it now checks.
    test('below the vocabulary ceiling, only the regional reason is given, and '
        'the bound is still a floor', () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload(maxWidth: 40));
      expect(caps.maxChannelWidthMhz.boundOrNull, CapabilityBound.atLeast);
      expect(
        caps.notes.any((String n) => n.contains('region')),
        isTrue,
        reason: 'the regional limit applies at every width',
      );
      expect(
        caps.notes.any((String n) => n.contains('vocabulary')),
        isFalse,
        reason: '40 MHz is nowhere near the 160 MHz vocabulary ceiling, so '
            'claiming that limit here would be a second wrong reason',
      );
    });

    test('R3: no channels with Location denied is a permission answer', () {
      final ClientCapabilities caps = MacOsCapabilityReader.parse(
        _macPayload(bands: const <String>[], maxWidth: null,
            locationAuthorized: false),
      );
      expect(
        (caps.bands as UnknownCapability<Set<WiFiBand>>).reason,
        CapabilityUnknownReason.permissionNotGranted,
      );
      expect(
        (caps.maxChannelWidthMhz as UnknownCapability<int>).reason,
        CapabilityUnknownReason.permissionNotGranted,
      );
    });

    test('no channels WITH Location granted is a query failure, not a denial',
        () {
      final ClientCapabilities caps = MacOsCapabilityReader.parse(
        _macPayload(bands: const <String>[], maxWidth: null),
      );
      expect(
        (caps.bands as UnknownCapability<Set<WiFiBand>>).reason,
        CapabilityUnknownReason.queryFailed,
      );
    });

    // H-1. `supportedWLANChannels()` is documented by Apple as "An array of
    // channels supported by the interface FOR THE ACTIVE COUNTRY CODE". It is a
    // regulatory permission read, not a hardware capability read. A 6 GHz-capable
    // MacBook in a region with no 6 GHz allocation reports 2.4/5 only, so
    // publishing that set as EXACT is a false negative about the user's radio.
    // Everything CoreWLAN derives from that channel list is therefore a floor.
    test('H-1: macOS bands are a floor, because the OS answered a regulatory '
        'question and not a hardware one', () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload());
      expect(
        caps.bands.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'supportedWLANChannels() is scoped to the active country code, '
            'so a band missing here may still be supported by the radio',
      );
    });

    test('H-1: macOS width is a floor even well below the vocabulary ceiling',
        () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload(maxWidth: 40));
      expect(caps.maxChannelWidthMhz.valueOrNull, 40);
      expect(
        caps.maxChannelWidthMhz.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'the widest PERMITTED channel in this region is not the widest '
            'channel the radio supports',
      );
    });

    test('H-1: the regional narrowing is stated on screen, not just in a bound',
        () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload());
      expect(
        caps.notes.any((String n) => n.contains('region')),
        isTrue,
        reason: 'a bound with no sentence next to it renders as a bare value',
      );
    });

    test('H-1: the pin names the country-code scope, so the provenance line '
        'cannot overstate the read', () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload());
      for (final Capability<Object> c
          in <Capability<Object>>[caps.bands, caps.maxChannelWidthMhz]) {
        expect((c as KnownCapability<Object>).pin.contains('country code'),
            isTrue,
            reason: 'the pin claims a hardware read it did not perform');
      }
    });

    test('no Wi-Fi interface is all-unknown, never all-zero', () {
      final ClientCapabilities caps = MacOsCapabilityReader.parse(
        _macPayload(interfacePresent: false),
      );
      expect(caps.isEntirelyUnknown, isTrue);
      for (final Capability<Object> c in caps.allFields.values) {
        expect(c.valueOrNull, isNull);
      }
    });

    test('a pre-HT active mode yields unknown generations, not an empty set',
        () {
      final ClientCapabilities caps =
          MacOsCapabilityReader.parse(_macPayload(phyMode: '802.11g'));
      expect(caps.standards.isKnown, isFalse);
      expect(caps.standards.valueOrNull, isNull);
    });

    test('a null payload is a query failure with a reason', () {
      final ClientCapabilities caps = MacOsCapabilityReader.parse(null);
      expect(caps.isEntirelyUnknown, isTrue);
    });

    test('the reader goes through the channel and maps what comes back',
        () async {
      final List<String> called = <String>[];
      final MacOsCapabilityReader reader = MacOsCapabilityReader(
        invoke: (String method) async {
          called.add(method);
          return _macPayload();
        },
      );
      final ClientCapabilities caps = await reader.read();
      expect(called, <String>['getWifiCapabilities']);
      expect(caps.bands.isKnown, isTrue);
      expect(reader.tier, CapabilityTier.livePlatformQuery);
    });
  });

  group('Android tier 1', () {
    test('R4: an affirmed band list is a floor, because 2.4 GHz cannot be asked',
        () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload());
      expect(caps.bands.valueOrNull, <WiFiBand>{WiFiBand.band5});
      expect(
        caps.bands.boundOrNull,
        CapabilityBound.atLeast,
        reason: 'reading this as exact would render "no 2.4 GHz", which is a '
            'false negative manufactured out of a missing API',
      );
      expect(
        caps.notes.any((String n) => n.contains('2.4 GHz')),
        isTrue,
        reason: 'the missing query has to be visible on the screen',
      );
    });

    test('generations are exact when all four were answered', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload());
      expect(caps.standards.valueOrNull,
          <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he});
      expect(caps.standards.boundOrNull, CapabilityBound.exact);
    });

    test('generations are a floor when one could not be asked', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload(be: null));
      expect(caps.standards.boundOrNull, CapabilityBound.atLeast);
    });

    test('R4: the OS-reported maximum rate is carried through at tier 1', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload());
      expect(caps.osReportedMaxPhyRateMbps.valueOrNull, 2402);
      expect(
        caps.osReportedMaxPhyRateMbps.tierOrNull,
        CapabilityTier.livePlatformQuery,
      );
    });

    test('a negative sentinel rate is unknown, never a number', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload(maxTx: -1));
      expect(caps.osReportedMaxPhyRateMbps.valueOrNull, isNull);
    });

    test('R5: an old Android answers unknown generations, not an empty set',
        () {
      final ClientCapabilities caps = AndroidCapabilityReader.parse(
        _androidPayload(
            apiLevel: 29, n: null, ac: null, ax: null, be: null,
            band5: true, band6: null),
      );
      expect(caps.standards.isKnown, isFalse);
      expect(
        (caps.standards as UnknownCapability<Set<WifiStd>>).reason,
        CapabilityUnknownReason.platformDoesNotExpose,
      );
      expect(
        caps.standards.valueOrNull,
        isNull,
        reason: 'an empty set would read as "this phone supports nothing"',
      );
    });

    test('null is not false: an unanswerable band query is not "no band"', () {
      final ClientCapabilities caps = AndroidCapabilityReader.parse(
        _androidPayload(band5: null, band6: null),
      );
      expect(caps.bands.isKnown, isFalse);
      expect(caps.bands.valueOrNull, isNull);
    });

    test('a false band answer IS a real answer and stays out of the set', () {
      final ClientCapabilities caps = AndroidCapabilityReader.parse(
        _androidPayload(band5: true, band6: false),
      );
      expect(caps.bands.valueOrNull!.contains(WiFiBand.band6), isFalse);
    });

    test('Android exposes no width, streams or MCS, and says so', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload());
      for (final Capability<int> c in <Capability<int>>[
        caps.maxChannelWidthMhz,
        caps.spatialStreams,
        caps.maxMcsIndex,
      ]) {
        expect(
          (c as UnknownCapability<int>).reason,
          CapabilityUnknownReason.platformDoesNotExpose,
        );
        expect(c.detail, isNotNull);
      }
    });

    test('every known Android field carries a pin naming the API', () {
      final ClientCapabilities caps =
          AndroidCapabilityReader.parse(_androidPayload());
      for (final MapEntry<String, Capability<Object>> e
          in caps.allFields.entries) {
        final Capability<Object> c = e.value;
        if (c is! KnownCapability<Object>) continue;
        expect(c.pin.contains('Android'), isTrue,
            reason: '${e.key} does not name its API');
      }
    });
  });

  group('iOS tier 2, the published table', () {
    test('R6: a listed model resolves every field at tier 2 with a pin', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(_tableJson, 'iPhone 15 Pro');
      expect(caps.deviceName, 'iPhone 15 Pro');
      expect(caps.tableVersion, '2026-08-02');
      expect(caps.maxChannelWidthMhz.valueOrNull, 160);
      expect(caps.spatialStreams.valueOrNull, 2);
      expect(caps.maxMcsIndex.valueOrNull, 11);
      expect(caps.standards.valueOrNull,
          <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he});
      for (final MapEntry<String, Capability<Object>> e
          in caps.allFields.entries) {
        final Capability<Object> c = e.value;
        if (c is! KnownCapability<Object>) continue;
        expect(c.tier, CapabilityTier.publishedTable, reason: e.key);
        expect(c.pin.contains('Apple Platform Deployment'), isTrue,
            reason: '${e.key} does not carry the row source');
        expect(c.pin.contains('iPhone 15 Pro'), isTrue,
            reason: '${e.key} does not name the row');
      }
    });

    test('a tier-2 ceiling is computable and is stamped tier 2', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(_tableJson, 'iPhone 15 Pro');
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;
      expect(rate.isKnown, isTrue);
      expect(rate.tierOrNull, CapabilityTier.publishedTable);
    });

    test('R7: an unlisted model is unknown everywhere and leaks nothing', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(_tableJson, 'iPhone 99 Ultra');
      expect(caps.isEntirelyUnknown, isTrue);
      for (final MapEntry<String, Capability<Object>> e
          in caps.allFields.entries) {
        expect(e.value.valueOrNull, isNull,
            reason: '${e.key} took a value from another row');
        expect(
          (e.value as UnknownCapability<Object>).reason,
          CapabilityUnknownReason.deviceNotInTable,
        );
      }
      expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, isNull);
    });

    test('R8: a row with an empty source does not ship', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(_tableJson, 'unsourced device');
      expect(
        caps.isEntirelyUnknown,
        isTrue,
        reason: 'the row lists a width, streams and an MCS index, and every '
            'one of them must be discarded because the row has no source',
      );
      expect(caps.spatialStreams.valueOrNull, isNull);
      expect(caps.maxChannelWidthMhz.valueOrNull, isNull);
    });

    test('a device that reported no identifier is not in the table', () async {
      final PublishedTableCapabilityReader reader =
          PublishedTableCapabilityReader(
        deviceModelName: null,
        loadJson: () async => _tableJson,
      );
      final ClientCapabilities caps = await reader.read();
      expect(caps.isEntirelyUnknown, isTrue);
    });

    test('malformed JSON is a query failure, not a crash and not a default',
        () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse('{ not json', 'iPhone 15 Pro');
      expect(caps.isEntirelyUnknown, isTrue);
    });

    test('a missing field in a present row is unknown for that field only', () {
      final Map<String, Object?> table =
          jsonDecode(_tableJson) as Map<String, Object?>;
      final List<Object?> devices = table['devices']! as List<Object?>;
      final Map<String, Object?> row =
          (devices.first! as Map<String, Object?>);
      row.remove('maxMcsIndex');
      final ClientCapabilities caps = PublishedTableCapabilityReader.parse(
        jsonEncode(table),
        'iPhone 15 Pro',
      );
      expect(caps.maxMcsIndex.valueOrNull, isNull);
      expect(caps.spatialStreams.valueOrNull, 2,
          reason: 'unknown is per field, not per device');
      expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, isNull);
    });
  });

  group('the service picks readers and merges without upgrading anything', () {
    test('R9: a platform with no reader is honestly unavailable', () async {
      final ClientCapabilityService service = ClientCapabilityService(
        platformOverride: TargetPlatform.linux,
        isWebOverride: false,
      );
      final ClientCapabilities caps = await service.resolve();
      expect(caps.isEntirelyUnknown, isTrue);
      for (final Capability<Object> c in caps.allFields.values) {
        expect(
          (c as UnknownCapability<Object>).reason,
          CapabilityUnknownReason.noReaderForPlatform,
        );
      }
    });

    test('web has no reader', () async {
      final ClientCapabilityService service = ClientCapabilityService(
        platformOverride: TargetPlatform.macOS,
        isWebOverride: true,
      );
      final ClientCapabilities caps = await service.resolve();
      expect(caps.isEntirelyUnknown, isTrue);
    });

    test('macOS picks the CoreWLAN reader, iOS picks the table', () {
      expect(
        ClientCapabilityService(
          platformOverride: TargetPlatform.macOS,
          isWebOverride: false,
        ).readersFor().single,
        isA<MacOsCapabilityReader>(),
      );
      expect(
        ClientCapabilityService(
          platformOverride: TargetPlatform.iOS,
          isWebOverride: false,
        ).readersFor(deviceModelName: 'iPhone 15 Pro').single,
        isA<PublishedTableCapabilityReader>(),
      );
      expect(
        ClientCapabilityService(
          platformOverride: TargetPlatform.android,
          isWebOverride: false,
        ).readersFor().single,
        isA<AndroidCapabilityReader>(),
      );
    });

    test('two readers merge field by field, each keeping its own tier',
        () async {
      final ClientCapabilityService service = ClientCapabilityService(
        isWebOverride: false,
        readersOverride: <CapabilityReader>[
          _FakeReader(
            CapabilityTier.livePlatformQuery,
            MacOsCapabilityReader.parse(_macPayload()),
          ),
          _FakeReader(
            CapabilityTier.publishedTable,
            PublishedTableCapabilityReader.parse(_tableJson, 'iPhone 15 Pro'),
          ),
        ],
      );
      final ClientCapabilities caps =
          await service.resolve(deviceIdentifier: 'iPhone16,1');

      // The live width wins over the table's 160.
      expect(caps.maxChannelWidthMhz.valueOrNull, 80);
      expect(
        caps.maxChannelWidthMhz.tierOrNull,
        CapabilityTier.livePlatformQuery,
      );
      // The gap macOS cannot fill comes from the table, still labelled tier 2.
      expect(caps.spatialStreams.valueOrNull, 2);
      expect(caps.spatialStreams.tierOrNull, CapabilityTier.publishedTable);
      // And the whole set reports itself at the weaker of the two.
      expect(caps.weakestKnownTier, CapabilityTier.publishedTable);
      // The derived ceiling is now computable, and it is tier 2, not tier 1.
      expect(caps.theoreticalMaxPhyRateMbps.isKnown, isTrue);
      expect(
        caps.theoreticalMaxPhyRateMbps.tierOrNull,
        CapabilityTier.publishedTable,
      );
    });

    test('the identity passed in never overwrites what a reader resolved',
        () async {
      final ClientCapabilityService service = ClientCapabilityService(
        isWebOverride: false,
        readersOverride: <CapabilityReader>[
          _FakeReader(
            CapabilityTier.publishedTable,
            PublishedTableCapabilityReader.parse(_tableJson, 'iPhone 15 Pro'),
          ),
        ],
      );
      final ClientCapabilities caps = await service.resolve(
        deviceIdentifier: 'iPhone16,1',
        deviceName: 'something else',
      );
      expect(caps.deviceName, 'iPhone 15 Pro');
    });
  });

  group('label mapping', () {
    test('standard labels map both ways round without inventing a standard',
        () {
      expect(wifiStdFromLabel('802.11ax'), WifiStd.he);
      expect(wifiStdFromLabel('11be'), WifiStd.eht);
      expect(wifiStdFromLabel('802.11g'), isNull);
      expect(wifiStdFromLabel(null), isNull);
      expect(wifiStdFromLabel('nonsense'), isNull);
    });

    test('standardsUpToAndIncluding is inclusive and ordered', () {
      expect(standardsUpToAndIncluding(WifiStd.ht), <WifiStd>{WifiStd.ht});
      expect(standardsUpToAndIncluding(WifiStd.eht), WifiStd.values.toSet());
    });

    test('band labels map without inventing a band', () {
      expect(wifiBandFromLabel('6 GHz'), WiFiBand.band6);
      expect(wifiBandFromLabel('5'), WiFiBand.band5);
      expect(wifiBandFromLabel('60 GHz'), isNull);
      expect(wifiBandFromLabel(null), isNull);
    });
  });
}

class _FakeReader implements CapabilityReader {
  _FakeReader(this.tier, this._result);

  final ClientCapabilities _result;

  @override
  final CapabilityTier tier;

  @override
  String get name => 'fake';

  @override
  Future<ClientCapabilities> read() async => _result;
}
