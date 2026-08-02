// Client Capabilities — model tests.
//
// ─────────────────────────────────────────────────────────────────────────────
// EXPECTED VALUES, WRITTEN BEFORE THE TESTS
//
// Every number below was worked out from the constant tables in
// wifi_phy_rate_service.dart BEFORE any assertion was written, so a test cannot
// be quietly reshaped around whatever the code happened to produce.
//
// The formula is (Nsd x bitsPerSymbol x streams) / symbolTimeUs.
//
//  E1. Fastest guard interval per standard, taken as the SHORTEST symbol time
//      in WifiPhyRateService.sym intersected with giKeys:
//        ht   {0.4: 3.6, 0.8: 4.0}                    -> '0.4'
//        vht  {0.4: 3.6, 0.8: 4.0}                    -> '0.4'
//        he   {0.8: 13.6, 1.6: 14.4, 3.2: 16.0}       -> '0.8'
//        eht  {0.8: 13.6, 1.6: 14.4, 3.2: 16.0}       -> '0.8'
//
//  E2. EHT, 160 MHz, 2 streams, MCS 13, GI 0.8:
//        Nsd 1960, bps 10.0, streams 2, symbol 13.6
//        (1960 x 10.0 x 2) / 13.6 = 39200 / 13.6 = 2882.3529411764707
//      This is the "2882 Mbps" figure the spec uses as its example of a number
//      that must NOT be the headline. Matching it is a cross-check that the
//      derivation is wired to the same math the spec was written against.
//
//  E3. Favorable throughput estimate for E2: EHT efficiency is 0.80.
//        2882.3529411764707 x 0.80 = 2305.8823529411766
//
//  E4. EHT, 320 MHz, 8 streams, MCS 13, GI 0.8:
//        Nsd 3920, bps 10.0, streams 8, symbol 13.6
//        (3920 x 10.0 x 8) / 13.6 = 313600 / 13.6 = 23058.823529411766
//
//  E5. HE at 320 MHz has NO entry in the Nsd table (HE stops at 160), so the
//      combination has no defined answer and must resolve to notComputable, not
//      to a narrower width the device never claimed.
//
//  E6. With spatial streams unknown and everything else known at EHT/160/MCS 13,
//      the FABRICATION SET is every rate a substituted stream count 1..8 would
//      produce, each 1441.1764705882354 x n:
//        1 ->  1441.1764705882354
//        2 ->  2882.3529411764707
//        3 ->  4323.529411764706
//        4 ->  5764.705882352941
//        5 ->  7205.882352941177
//        6 ->  8647.058823529413
//        7 -> 10088.235294117647
//        8 -> 11529.411764705883
//      The derived ceiling must equal NONE of these. It must be unknown.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/client_capabilities.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart'
    show WiFiBand;
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart'
    show WifiPhyRateService, WifiStd;

/// A capability set with everything known, used as the base for "knock one
/// field out and prove nothing gets invented" tests.
ClientCapabilities _fullyKnown({
  Capability<int>? spatialStreams,
  Capability<int>? maxMcsIndex,
  Capability<int>? maxChannelWidthMhz,
  Capability<Set<WifiStd>>? standards,
}) =>
    ClientCapabilities(
      bands: Capability<Set<WiFiBand>>.known(
        <WiFiBand>{WiFiBand.band24, WiFiBand.band5, WiFiBand.band6},
        tier: CapabilityTier.livePlatformQuery,
        pin: 'test fixture',
      ),
      standards: standards ??
          Capability<Set<WifiStd>>.known(
            <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he, WifiStd.eht},
            tier: CapabilityTier.livePlatformQuery,
            pin: 'test fixture',
          ),
      maxChannelWidthMhz: maxChannelWidthMhz ??
          Capability<int>.known(
            160,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'test fixture',
          ),
      spatialStreams: spatialStreams ??
          Capability<int>.known(
            2,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'test fixture',
          ),
      maxMcsIndex: maxMcsIndex ??
          Capability<int>.known(
            13,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'test fixture',
          ),
      osReportedMaxPhyRateMbps: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
      ),
    );

void main() {
  group('a known capability cannot exist without a source', () {
    test('an empty pin throws, so a value can never ship unsourced', () {
      expect(
        () => Capability<int>.known(
          2,
          tier: CapabilityTier.livePlatformQuery,
          pin: '',
        ),
        throwsArgumentError,
      );
    });

    test('a whitespace-only pin throws too', () {
      expect(
        () => Capability<int>.known(
          2,
          tier: CapabilityTier.publishedTable,
          pin: '   \n ',
        ),
        throwsArgumentError,
      );
    });

    test('the check runs outside asserts, so a release build is guarded', () {
      // A test that only passed in debug would be a test that cannot fail where
      // it matters. Calling the constructor inside a plain try proves the throw
      // is control flow, not an assertion.
      Object? caught;
      try {
        Capability<String>.known(
          'x',
          tier: CapabilityTier.livePlatformQuery,
          pin: '',
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<ArgumentError>());
    });

    test('a pin is stored trimmed but intact', () {
      final Capability<int> c = Capability<int>.known(
        2,
        tier: CapabilityTier.livePlatformQuery,
        pin: '  CoreWLAN supportedWLANChannels()  ',
      );
      expect((c as KnownCapability<int>).pin,
          'CoreWLAN supportedWLANChannels()');
    });
  });

  group('unknown is a first-class answer, never a blank', () {
    test('every reason carries a non-empty label the screen can print', () {
      for (final CapabilityUnknownReason r in CapabilityUnknownReason.values) {
        expect(r.label.trim(), isNotEmpty, reason: '${r.name} has no label');
        expect(r.label.endsWith('.'), isFalse,
            reason: '${r.name} label ends with a period; the screen '
                'punctuates');
      }
    });

    test('an unknown yields null and no tier, for every reason', () {
      for (final CapabilityUnknownReason r in CapabilityUnknownReason.values) {
        final Capability<int> c = Capability<int>.unknown(r);
        expect(c.isKnown, isFalse);
        expect(c.valueOrNull, isNull);
        expect(c.tierOrNull, isNull);
        expect(c.boundOrNull, isNull);
      }
    });

    test('allUnknown leaves every field unknown and the set entirely unknown',
        () {
      final ClientCapabilities caps = ClientCapabilities.allUnknown(
        CapabilityUnknownReason.noReaderForPlatform,
      );
      expect(caps.isEntirelyUnknown, isTrue);
      expect(caps.weakestKnownTier, isNull);
      for (final MapEntry<String, Capability<Object>> e
          in caps.allFields.entries) {
        expect(e.value.isKnown, isFalse, reason: '${e.key} claimed a value');
        expect(e.value.valueOrNull, isNull, reason: '${e.key} held a value');
      }
      expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, isNull);
      expect(caps.favorableThroughputEstimateMbps.valueOrNull, isNull);
      expect(caps.highestStandard.valueOrNull, isNull);
    });
  });

  group('a derived value cannot outrank its inputs', () {
    test('a tier-2 input drags a tier-1 input down to tier 2', () {
      final Capability<int> derived = Capability.derive<int>(
        inputs: <String, Capability<Object>>{
          'live': Capability<int>.known(
            1,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'live',
          ),
          'table': Capability<int>.known(
            2,
            tier: CapabilityTier.publishedTable,
            pin: 'table',
          ),
        },
        pin: 'sum',
        compute: () => 3,
      );
      expect(derived.valueOrNull, 3);
      expect(derived.tierOrNull, CapabilityTier.publishedTable);
    });

    test('an atLeast input makes the result an atLeast', () {
      final Capability<int> derived = Capability.derive<int>(
        inputs: <String, Capability<Object>>{
          'exact': Capability<int>.known(
            1,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'exact',
          ),
          'floor': Capability<int>.known(
            2,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'floor',
            bound: CapabilityBound.atLeast,
          ),
        },
        pin: 'sum',
        compute: () => 3,
      );
      expect(derived.boundOrNull, CapabilityBound.atLeast);
    });

    test('one unknown input names itself and blocks the computation', () {
      bool computed = false;
      final Capability<int> derived = Capability.derive<int>(
        inputs: <String, Capability<Object>>{
          'known thing': Capability<int>.known(
            1,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'p',
          ),
          'spatial streams': const Capability<int>.unknown(
            CapabilityUnknownReason.platformDoesNotExpose,
          ),
        },
        pin: 'sum',
        compute: () {
          computed = true;
          return 99;
        },
      );
      expect(computed, isFalse,
          reason: 'compute ran despite a missing input, which is how a '
              'fabricated value gets in');
      expect(derived.valueOrNull, isNull);
      expect(
        (derived as UnknownCapability<int>).reason,
        CapabilityUnknownReason.derivedInputUnknown,
      );
      expect(derived.detail, 'spatial streams');
    });

    test('no inputs at all is unknown, not a free value', () {
      final Capability<int> derived = Capability.derive<int>(
        inputs: const <String, Capability<Object>>{},
        pin: 'nothing',
        compute: () => 7,
      );
      expect(derived.valueOrNull, isNull);
    });

    test('all inputs known but no defined answer is notComputable', () {
      final Capability<int> derived = Capability.derive<int>(
        inputs: <String, Capability<Object>>{
          'a': Capability<int>.known(
            1,
            tier: CapabilityTier.livePlatformQuery,
            pin: 'p',
          ),
        },
        pin: 'undefined combination',
        compute: () => null,
      );
      expect(
        (derived as UnknownCapability<int>).reason,
        CapabilityUnknownReason.notComputable,
      );
    });
  });

  group('the fastest guard interval is derived from the tables, not typed in',
      () {
    test('E1: the shortest symbol time wins for every standard', () {
      expect(ClientCapabilities.fastestGuardIntervalKeyFor(WifiStd.ht), '0.4');
      expect(ClientCapabilities.fastestGuardIntervalKeyFor(WifiStd.vht), '0.4');
      expect(ClientCapabilities.fastestGuardIntervalKeyFor(WifiStd.he), '0.8');
      expect(ClientCapabilities.fastestGuardIntervalKeyFor(WifiStd.eht), '0.8');
    });

    test('it recomputes the answer rather than storing it', () {
      // Derived independently here from the same tables. If someone hardcodes
      // the keys above and the tables later change, this disagrees.
      for (final WifiStd std in WifiStd.values) {
        final Map<String, double> symbols = WifiPhyRateService.sym[std]!;
        final List<String> offered = WifiPhyRateService.giKeys[std]!;
        final String expected = offered.reduce(
          (String a, String b) => symbols[a]! <= symbols[b]! ? a : b,
        );
        expect(ClientCapabilities.fastestGuardIntervalKeyFor(std), expected);
      }
    });
  });

  group('the theoretical ceiling', () {
    test('E2: EHT 160 MHz, 2 streams, MCS 13 is 2882.3529411764707 Mbps', () {
      final ClientCapabilities caps = _fullyKnown();
      expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, 2882.3529411764707);
    });

    test('E3: the favorable estimate applies the 0.80 EHT factor', () {
      final ClientCapabilities caps = _fullyKnown();
      expect(
        caps.favorableThroughputEstimateMbps.valueOrNull,
        2305.8823529411766,
      );
    });

    test('E4: EHT 320 MHz, 8 streams, MCS 13 is 23058.823529411766 Mbps', () {
      final ClientCapabilities caps = _fullyKnown(
        maxChannelWidthMhz: Capability<int>.known(
          320,
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
        spatialStreams: Capability<int>.known(
          8,
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
      );
      expect(caps.theoreticalMaxPhyRateMbps.valueOrNull, 23058.823529411766);
    });

    test('E5: HE at 320 MHz is notComputable, never silently narrowed', () {
      final ClientCapabilities caps = _fullyKnown(
        standards: Capability<Set<WifiStd>>.known(
          <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he},
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
        maxChannelWidthMhz: Capability<int>.known(
          320,
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
        maxMcsIndex: Capability<int>.known(
          11,
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
      );
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;
      expect(rate.valueOrNull, isNull);
      expect(
        (rate as UnknownCapability<double>).reason,
        CapabilityUnknownReason.notComputable,
      );
      // The 160 MHz answer for the same device would be 2401.94...; the point
      // is that no answer at all is produced, not that a different one is.
      expect(
        WifiPhyRateService.phyRateMbps(
          std: WifiStd.he,
          bandwidthMHz: 160,
          mcs: 11,
          streams: 2,
          giKey: '0.8',
        ),
        isNotNull,
        reason: 'the narrowed combination IS computable, which is exactly why '
            'the code must not quietly fall back to it',
      );
    });

    test('the ceiling inherits the weakest tier of its inputs', () {
      final ClientCapabilities caps = _fullyKnown(
        maxMcsIndex: Capability<int>.known(
          13,
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
      );
      expect(
        caps.theoreticalMaxPhyRateMbps.tierOrNull,
        CapabilityTier.publishedTable,
      );
    });

    test('a floor input makes the ceiling a floor', () {
      final ClientCapabilities caps = _fullyKnown(
        maxChannelWidthMhz: Capability<int>.known(
          160,
          tier: CapabilityTier.livePlatformQuery,
          pin: 'CoreWLAN, at the vocabulary ceiling',
          bound: CapabilityBound.atLeast,
        ),
      );
      expect(
        caps.theoreticalMaxPhyRateMbps.boundOrNull,
        CapabilityBound.atLeast,
      );
    });
  });

  group('a missing input is never filled with a plausible number', () {
    test(
        'E6: with spatial streams unknown, the ceiling matches NO substituted '
        'stream count from 1 to 8', () {
      final ClientCapabilities caps = _fullyKnown(
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;

      // The strong form: forbid ANY value, not just the likely guess of 2.
      expect(rate.isKnown, isFalse);
      expect(rate.valueOrNull, isNull);
      for (int streams = 1; streams <= 8; streams++) {
        final double? fabricated = WifiPhyRateService.phyRateMbps(
          std: WifiStd.eht,
          bandwidthMHz: 160,
          mcs: 13,
          streams: streams,
          giKey: '0.8',
        );
        expect(fabricated, isNotNull);
        expect(
          rate.valueOrNull,
          isNot(fabricated),
          reason: 'the ceiling equals the rate for $streams streams, which the '
              'device never reported',
        );
      }
      expect(
        (rate as UnknownCapability<double>).detail,
        'spatial streams',
        reason: 'the screen must be able to say WHICH value is missing',
      );
    });

    test('a missing MCS index blocks the ceiling and names itself', () {
      final ClientCapabilities caps = _fullyKnown(
        maxMcsIndex: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;
      expect(rate.valueOrNull, isNull);
      expect((rate as UnknownCapability<double>).detail, 'maximum MCS index');
    });

    test('a missing width blocks the ceiling and names itself', () {
      final ClientCapabilities caps = _fullyKnown(
        maxChannelWidthMhz: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      final Capability<double> rate = caps.theoreticalMaxPhyRateMbps;
      expect(rate.valueOrNull, isNull);
      expect(
        (rate as UnknownCapability<double>).detail,
        'maximum channel width',
      );
    });

    test('an unknown ceiling means an unknown favorable estimate too', () {
      final ClientCapabilities caps = _fullyKnown(
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      expect(caps.favorableThroughputEstimateMbps.valueOrNull, isNull);
    });

    test('knowing three of five fields renders three known rows, not zero', () {
      final ClientCapabilities caps = _fullyKnown(
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        maxMcsIndex: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      expect(caps.isEntirelyUnknown, isFalse);
      final int known = caps.allFields.values
          .where((Capability<Object> c) => c.isKnown)
          .length;
      expect(known, 3, reason: 'bands, generations and width are known');
    });
  });

  group('highest standard', () {
    test('picks the newest member of the set', () {
      final ClientCapabilities caps = _fullyKnown(
        standards: Capability<Set<WifiStd>>.known(
          <WifiStd>{WifiStd.ht, WifiStd.he},
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
      );
      expect(caps.highestStandard.valueOrNull, WifiStd.he);
    });

    test('an empty set is notComputable, not a default of HT', () {
      final ClientCapabilities caps = _fullyKnown(
        standards: Capability<Set<WifiStd>>.known(
          const <WifiStd>{},
          tier: CapabilityTier.livePlatformQuery,
          pin: 'test fixture',
        ),
      );
      expect(caps.highestStandard.valueOrNull, isNull);
      expect(
        (caps.highestStandard as UnknownCapability<WifiStd>).reason,
        CapabilityUnknownReason.notComputable,
      );
    });
  });

  group('merging two partial answers', () {
    test('a tier-2 value filling a tier-1 gap still says tier 2', () {
      final ClientCapabilities live = ClientCapabilities(
        bands: Capability<Set<WiFiBand>>.known(
          <WiFiBand>{WiFiBand.band5},
          tier: CapabilityTier.livePlatformQuery,
          pin: 'CoreWLAN',
        ),
        standards: const Capability<Set<WifiStd>>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        maxChannelWidthMhz: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        maxMcsIndex: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        osReportedMaxPhyRateMbps: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      final ClientCapabilities table = ClientCapabilities(
        bands: Capability<Set<WiFiBand>>.known(
          <WiFiBand>{WiFiBand.band24, WiFiBand.band5, WiFiBand.band6},
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        standards: Capability<Set<WifiStd>>.known(
          <WifiStd>{WifiStd.he},
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        maxChannelWidthMhz: Capability<int>.known(
          160,
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        spatialStreams: Capability<int>.known(
          2,
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        maxMcsIndex: Capability<int>.known(
          11,
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        osReportedMaxPhyRateMbps: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );

      final ClientCapabilities merged = live.fillGapsFrom(table);

      // The live band read WINS and keeps its own tier and its own value.
      expect(merged.bands.tierOrNull, CapabilityTier.livePlatformQuery);
      expect(merged.bands.valueOrNull, <WiFiBand>{WiFiBand.band5});
      // The gaps are filled, each still stamped tier 2.
      expect(merged.spatialStreams.valueOrNull, 2);
      expect(merged.spatialStreams.tierOrNull, CapabilityTier.publishedTable);
      expect(merged.maxMcsIndex.tierOrNull, CapabilityTier.publishedTable);
      // The whole set reports itself at its weakest tier, never its strongest.
      expect(merged.weakestKnownTier, CapabilityTier.publishedTable);
    });

    test('merging cannot upgrade a tier-2 value to tier 1', () {
      final ClientCapabilities table = ClientCapabilities(
        bands: const Capability<Set<WiFiBand>>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
        ),
        standards: const Capability<Set<WifiStd>>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
        ),
        maxChannelWidthMhz: const Capability<int>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
        ),
        spatialStreams: Capability<int>.known(
          2,
          tier: CapabilityTier.publishedTable,
          pin: 'Apple Platform Deployment',
        ),
        maxMcsIndex: const Capability<int>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
        ),
        osReportedMaxPhyRateMbps: const Capability<int>.unknown(
          CapabilityUnknownReason.deviceNotInTable,
        ),
      );
      final ClientCapabilities live = ClientCapabilities(
        bands: const Capability<Set<WiFiBand>>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        standards: const Capability<Set<WifiStd>>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        maxChannelWidthMhz: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        maxMcsIndex: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
        osReportedMaxPhyRateMbps: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      // Merge in the other direction: a tier-1 reader that knew nothing.
      final ClientCapabilities merged = live.fillGapsFrom(table);
      expect(merged.spatialStreams.tierOrNull, CapabilityTier.publishedTable);
    });

    test('tier ordering is stated, not assumed', () {
      expect(
        CapabilityTier.publishedTable
            .isWeakerThan(CapabilityTier.livePlatformQuery),
        isTrue,
      );
      expect(
        CapabilityTier.livePlatformQuery
            .isWeakerThan(CapabilityTier.publishedTable),
        isFalse,
      );
    });

    test('there is no tier that means unknown', () {
      // If a member is ever added here that stands for absence, the tier system
      // stops being a provenance claim and starts being a nullable field again.
      expect(CapabilityTier.values.length, 2);
      for (final CapabilityTier t in CapabilityTier.values) {
        expect(t.label.toLowerCase().contains('unknown'), isFalse);
      }
    });
  });
}
