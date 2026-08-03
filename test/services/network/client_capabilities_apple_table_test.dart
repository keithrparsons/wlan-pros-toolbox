// The shipped Apple capability table, checked against its own rules and
// against Apple's own arithmetic.
//
// ─────────────────────────────────────────────────────────────────────────────
// EXPECTED VALUES, WRITTEN BEFORE THE TESTS
//
// Transcribed from the Apple Platform Deployment guide, "Wi-Fi and Ethernet
// specifications for Apple devices", retrieved 2026-08-02. Verbatim cells:
//
//   A1. iPhone 17 / iPhone 16 table, be@6 GHz row:
//         2400 Mbps · 160 MHz · MCS 11 (EHT) · 2/MIMO
//   A2. iPhone 15 table, ax@6 GHz row:
//         2400 Mbps · 160 MHz · MCS 11 (HE) · 2/MIMO
//   A3. iPhone 17e / 16e / 14 / 13 / 12 / 11 / SE table, ax@5 GHz row:
//         1200 Mbps · 80 MHz · MCS 11 (HE) · 2/MIMO
//
// THE CROSS-CHECK. Apple publishes its OWN maximum PHY data rate in the same
// table, so our reconstruction can be checked against an outside authority
// rather than against ourselves. Worked out from the rate tables before writing
// the assertion:
//
//   A1/A2 at 160 MHz, MCS 11 (bits/symbol 8.3333), 2 streams, 0.8 us GI:
//     (1960 x 8.3333 x 2) / 13.6 = 2401.9509803921568   Apple says 2400
//     difference 0.081%
//   A3 at 80 MHz, MCS 11, 2 streams, 0.8 us GI:
//     (980 x 8.3333 x 2) / 13.6 = 1200.9754901960784    Apple says 1200
//     difference 0.081%
//
// A tolerance of 0.5% therefore passes both and is nowhere near loose enough to
// hide a real error: one MCS step is roughly 20%, halving the width or dropping
// a spatial stream is 50%.
//
//   A4. iPhone 15 and iPhone 15 Plus must NOT resolve. Apple lists them in two
//       tables with contradictory figures (160 MHz / 2400 Mbps against
//       80 MHz / 1200 Mbps), and resolving that contradiction is not ours to do.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/client_capabilities.dart';
import 'package:wlan_pros_toolbox/services/network/client_capability_resolver.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart'
    show WiFiBand;
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart'
    show WifiStd;

/// Apple's published rate, and ours, must agree to within this fraction.
const double kMaxRelativeDifference = 0.005;

void main() {
  final String raw =
      File('assets/data/client_capabilities_apple.json').readAsStringSync();
  final Map<String, Object?> table =
      jsonDecode(raw) as Map<String, Object?>;
  final List<Object?> devices = table['devices']! as List<Object?>;

  group('the table obeys its own rules', () {
    test('every row carries a non-empty source', () {
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        final String source = (row['source'] ?? '').toString().trim();
        expect(source, isNotEmpty,
            reason: 'row ${row['names']} has no source, so it cannot ship');
        expect(source.contains('Apple Platform Deployment'), isTrue);
        expect(source.contains('retrieved'), isTrue,
            reason: 'a capability row without a retrieval date is a fact with '
                'an invisible expiry');
      }
    });

    test('the table is dated', () {
      final Map<String, Object?> meta = table['_meta']! as Map<String, Object?>;
      expect(meta['retrieved'], isNotNull);
      expect(meta['last_updated'], isNotNull);
      expect(meta['source'].toString().contains('support.apple.com'), isTrue);
    });

    test('no model name appears in two rows', () {
      final Map<String, String> seen = <String, String>{};
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        for (final String key in <String>['names', 'familyNames']) {
          for (final Object? n in (row[key] ?? <Object?>[]) as List<Object?>) {
            final String name = n.toString().toLowerCase();
            expect(seen.containsKey(name), isFalse,
                reason: '$name is in two rows, so the lookup order decides '
                    'which figures a device gets');
            seen[name] = key;
          }
        }
      }
    });

    test('a row with familyNames explains why they exist', () {
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        final List<Object?> family =
            (row['familyNames'] ?? <Object?>[]) as List<Object?>;
        if (family.isEmpty) continue;
        expect((row['expansionNote'] ?? '').toString().trim(), isNotEmpty,
            reason: 'an expansion of ours needs to say it is ours');
      }
    });

    // L-1. This test iterates SIX fields and used to be named "five", and
    // `client_capabilities.dart` called `allFields` "the five READ fields"
    // while returning six. A wrong count in a name is how a seventh field gets
    // silently dropped later.
    test('every row carries all six capability fields', () {
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        for (final String field in <String>[
          'bands',
          'standards',
          'maxChannelWidthMhz',
          'spatialStreams',
          'maxMcsIndex',
          'applePublishedMaxPhyRateMbps',
        ]) {
          expect(row[field], isNotNull, reason: '${row['names']} lacks $field');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // H-3. The shipped asset is the only thing production ever reads. These tests
  // exist because the resolver's own fixture once carried an `identifier` key
  // and a `name` key that the asset carries on ZERO rows, so the suite proved
  // two lookup paths production can never take, and the path production DOES
  // take went untested. A fixture that does not resemble the asset hides the
  // defect it was written to catch.
  // ───────────────────────────────────────────────────────────────────────────
  group('H-3: the lookup key is what the platform can actually supply', () {
    test('no row is keyed by a machine identifier, so nothing may be looked up '
        'by one', () {
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        expect(
          row.containsKey('identifier'),
          isFalse,
          reason: 'a row gained an `identifier` key. The resolver fixture and '
              'the machine-identifier miss test below are now both stale, and '
              'the resolver lookup needs re-pointing at it deliberately.',
        );
        expect(
          row.containsKey('name'),
          isFalse,
          reason: 'a row gained a `name` key. `parse` reports the VERBATIM '
              'matched entry as the device name; a `name` key would be a '
              'second, competing answer.',
        );
      }
    });

    test('a machine identifier misses every row in the SHIPPED table, and '
        'misses honestly', () {
      // This is what iOS can actually supply: utsname.machine. Apple exposes no
      // API for the marketing name the table is keyed by.
      for (final String machineId in <String>[
        'iPhone17,1',
        'iPhone16,1',
        'iPhone14,2',
      ]) {
        final ClientCapabilities caps =
            PublishedTableCapabilityReader.parse(raw, machineId);
        expect(
          caps.isEntirelyUnknown,
          isTrue,
          reason: '$machineId resolved against a table keyed by marketing '
              'name, which means something is matching that should not',
        );
        for (final Capability<Object> c in caps.allFields.values) {
          expect(
            (c as UnknownCapability<Object>).reason,
            CapabilityUnknownReason.deviceNotInTable,
            reason: 'the miss must name itself, not read as a blank',
          );
        }
      }
    });

    test('the marketing name the table IS keyed by resolves, so the miss above '
        'is about the key and not about the table', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 16 Pro');
      expect(caps.spatialStreams.valueOrNull, 2);
      expect(caps.maxChannelWidthMhz.valueOrNull, 160);
      expect(caps.theoreticalMaxPhyRateMbps.isKnown, isTrue);
    });

    test('the device name reported back is the VERBATIM table entry', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iphone   16   pro');
      expect(
        caps.deviceName,
        'iPhone 16 Pro',
        reason: 'the table\'s own spelling, not the caller\'s',
      );
    });
  });

  group('our reconstruction agrees with Apple, cell for cell', () {
    test('A1: the Wi-Fi 7 iPhones resolve to 160 MHz, MCS 11, 2 streams', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 16 Pro');
      expect(caps.maxChannelWidthMhz.valueOrNull, 160);
      expect(caps.maxMcsIndex.valueOrNull, 11);
      expect(caps.spatialStreams.valueOrNull, 2);
      expect(caps.highestStandard.valueOrNull, WifiStd.eht);
      expect(caps.bands.valueOrNull,
          <WiFiBand>{WiFiBand.band24, WiFiBand.band5, WiFiBand.band6});
      expect(caps.weakestKnownTier, CapabilityTier.publishedTable);
    });

    test('A2: the iPhone 15 Pro pair resolves to Wi-Fi 6E at 160 MHz', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 15 Pro Max');
      expect(caps.highestStandard.valueOrNull, WifiStd.he);
      expect(caps.maxChannelWidthMhz.valueOrNull, 160);
      expect(caps.bands.valueOrNull!.contains(WiFiBand.band6), isTrue);
    });

    test('A3: the 80 MHz family resolves to 80 MHz and no 6 GHz', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 13 Pro');
      expect(caps.maxChannelWidthMhz.valueOrNull, 80);
      expect(caps.bands.valueOrNull!.contains(WiFiBand.band6), isFalse);
      expect(caps.highestStandard.valueOrNull, WifiStd.he);
    });

    test(
        'our derived ceiling matches Apple\'s published rate on every row, '
        'within 0.5%', () {
      for (final Object? entry in devices) {
        final Map<String, Object?> row = entry! as Map<String, Object?>;
        final String probe =
            ((row['names']! as List<Object?>).first).toString();
        final double applePublished =
            (row['applePublishedMaxPhyRateMbps']! as num).toDouble();
        final ClientCapabilities caps =
            PublishedTableCapabilityReader.parse(raw, probe);
        final double? ours = caps.theoreticalMaxPhyRateMbps.valueOrNull;
        expect(ours, isNotNull, reason: '$probe produced no ceiling at all');
        final double diff = (ours! - applePublished).abs() / applePublished;
        expect(
          diff,
          lessThan(kMaxRelativeDifference),
          reason: '$probe: we compute $ours Mbps, Apple publishes '
              '$applePublished Mbps, a difference of '
              '${(diff * 100).toStringAsFixed(3)}%. Either our transcription '
              'of a cell is wrong or the rate tables are',
        );
      }
    });

    test('a family-name match is still tier 2 and says it was an expansion',
        () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 12 mini');
      expect(caps.maxChannelWidthMhz.valueOrNull, 80);
      final KnownCapability<int> width =
          caps.maxChannelWidthMhz as KnownCapability<int>;
      expect(width.tier, CapabilityTier.publishedTable);
      expect(width.pin.contains('expansion'), isTrue,
          reason: 'a match through our own expansion has to be visible in the '
              'pin');
    });

    test('a verbatim Apple name does NOT claim to be an expansion', () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 16 Pro');
      final KnownCapability<int> width =
          caps.maxChannelWidthMhz as KnownCapability<int>;
      expect(width.pin.contains('expansion'), isFalse);
    });

    test('matching tolerates case and stray whitespace only', () {
      expect(
        PublishedTableCapabilityReader.parse(raw, '  iphone  16 pro ')
            .maxChannelWidthMhz
            .valueOrNull,
        160,
      );
      expect(
        PublishedTableCapabilityReader.parse(raw, 'iPhone16Pro')
            .maxChannelWidthMhz
            .valueOrNull,
        isNull,
        reason: 'a fuzzy match would hand one model another model\'s numbers',
      );
    });
  });

  group('the contradiction in Apple\'s own page is not resolved by us', () {
    test('A4: iPhone 15 and iPhone 15 Plus do not resolve at all', () {
      for (final String model in <String>['iPhone 15', 'iPhone 15 Plus']) {
        final ClientCapabilities caps =
            PublishedTableCapabilityReader.parse(raw, model);
        expect(
          caps.isEntirelyUnknown,
          isTrue,
          reason: '$model resolved to figures, but Apple publishes two '
              'contradictory sets for it and we have no authority to pick one',
        );
        expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, isNull);
      }
    });

    test('the conflict is recorded in the file, not just in a commit message',
        () {
      final Map<String, Object?> meta = table['_meta']! as Map<String, Object?>;
      final List<Object?> conflicts =
          meta['known_conflicts_in_the_source']! as List<Object?>;
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.toString().contains('iPhone 15'), isTrue);
    });

    test('an unlisted Apple device is an honest unknown, not a near neighbour',
        () {
      final ClientCapabilities caps =
          PublishedTableCapabilityReader.parse(raw, 'iPhone 8');
      expect(caps.isEntirelyUnknown, isTrue);
      expect(
        (caps.maxMcsIndex as UnknownCapability<int>).reason,
        CapabilityUnknownReason.deviceNotInTable,
      );
    });
  });
}
