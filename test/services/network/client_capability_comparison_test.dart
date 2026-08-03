// The comparison is a claims surface. These tests gate the claims.
//
// ─────────────────────────────────────────────────────────────────────────────
// EXPECTED VALUES, WRITTEN BEFORE THE TESTS
//
// The fixture device is a 2x2 Wi-Fi 7 client at 160 MHz, MCS 13, which the
// model tests already pin at a theoretical ceiling of 2882.3529411764707 Mbps,
// and a favorable estimate of 2305.8823529411766 Mbps (0.80 of the ceiling).
//
// Positions, worked out from the two published anchors (40 and 60 percent of
// the PHY rate, Vajda 2023) and the favorable estimate at 80 percent:
//
//   C1.  500 Mbps  ->  17.3%  ->  belowThePublishedRange
//   C2. 1200 Mbps  ->  41.6%  ->  withinThePublishedRange
//   C3. 1700 Mbps  ->  59.0%  ->  withinThePublishedRange
//   C4. 2000 Mbps  ->  69.4%  ->  aboveThePublishedRange
//   C5. 2400 Mbps  ->  83.3%  ->  atOrAboveTheOptimisticEstimate
//
//   Boundary checks, because a boundary is where a classifier lies:
//   C6. exactly 40% -> withinThePublishedRange   (the range is inclusive)
//   C7. exactly 60% -> withinThePublishedRange   (still inside)
//   C8. exactly 80% -> atOrAboveTheOptimisticEstimate
//
//   C9. With spatial streams unknown there is NO ceiling, so there is no
//       position, no percentage, and the copy names what is missing.
//
// THE WORDING GATE. Every string the comparison can produce is collected and
// checked mechanically, because a wording rule that depends on someone reading
// carefully is not a rule. The banned list is not a style preference: each entry
// turns a measurement of one client into a claim about a network we did not
// measure.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/client_capabilities.dart';
import 'package:wlan_pros_toolbox/services/network/client_capability_comparison.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart'
    show WiFiBand;
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart'
    show WifiPhyRateService, WifiStd;

/// The ceiling of the fixture device, pinned in client_capabilities_test.dart.
const double kFixtureCeiling = 2882.3529411764707;

/// A device whose fields are ALL known but whose combination has no defined
/// rate: Wi-Fi 6 tops out at 160 MHz, so 320 MHz against HE is undefined.
///
/// This is the only way to reach [CapabilityUnknownReason.notComputable] from
/// the public model, and it is the branch whose `detail` is the derivation pin.
ClientCapabilities _impossibleCombination() => ClientCapabilities(
      bands: Capability<Set<WiFiBand>>.known(
        <WiFiBand>{WiFiBand.band6},
        tier: CapabilityTier.publishedTable,
        pin: 'test fixture',
      ),
      standards: Capability<Set<WifiStd>>.known(
        <WifiStd>{WifiStd.he},
        tier: CapabilityTier.publishedTable,
        pin: 'test fixture',
      ),
      maxChannelWidthMhz: Capability<int>.known(
        320,
        tier: CapabilityTier.publishedTable,
        pin: 'test fixture',
      ),
      spatialStreams: Capability<int>.known(
        2,
        tier: CapabilityTier.publishedTable,
        pin: 'test fixture',
      ),
      maxMcsIndex: Capability<int>.known(
        11,
        tier: CapabilityTier.publishedTable,
        pin: 'test fixture',
      ),
      osReportedMaxPhyRateMbps: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
      ),
    );

ClientCapabilities _device({Capability<int>? spatialStreams}) =>
    ClientCapabilities(
      bands: Capability<Set<WiFiBand>>.known(
        <WiFiBand>{WiFiBand.band24, WiFiBand.band5, WiFiBand.band6},
        tier: CapabilityTier.livePlatformQuery,
        pin: 'test fixture',
      ),
      standards: Capability<Set<WifiStd>>.known(
        <WifiStd>{WifiStd.ht, WifiStd.vht, WifiStd.he, WifiStd.eht},
        tier: CapabilityTier.livePlatformQuery,
        pin: 'test fixture',
      ),
      maxChannelWidthMhz: Capability<int>.known(
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
      maxMcsIndex: Capability<int>.known(
        13,
        tier: CapabilityTier.livePlatformQuery,
        pin: 'test fixture',
      ),
      osReportedMaxPhyRateMbps: const Capability<int>.unknown(
        CapabilityUnknownReason.platformDoesNotExpose,
      ),
    );

ThroughputComparison _at(double mbps, {Capability<int>? spatialStreams}) =>
    ThroughputComparison.of(
      measuredMbps: mbps,
      capabilities: _device(spatialStreams: spatialStreams),
    );

/// Every string the comparison can produce, across every position and the
/// no-ceiling case. Sampling one case would let a bad string hide in another.
List<String> _everyStringTheFeatureCanShow() => <String>[
      ..._at(500).allCopy,
      ..._at(1200).allCopy,
      ..._at(1700).allCopy,
      ..._at(2000).allCopy,
      ..._at(2400).allCopy,
      ..._at(3000).allCopy,
      ..._at(
        500,
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      ).allCopy,
      kClientCapabilitiesAttribution,
      ...kNormalReasonsForAGap,
    ];

void main() {
  group('position', () {
    test('C1: well below the published range', () {
      expect(_at(500).position, ThroughputPosition.belowThePublishedRange);
    });

    test('C2 and C3: inside the published range', () {
      expect(_at(1200).position, ThroughputPosition.withinThePublishedRange);
      expect(_at(1700).position, ThroughputPosition.withinThePublishedRange);
    });

    test('C4: above the published range, below our optimistic estimate', () {
      expect(_at(2000).position, ThroughputPosition.aboveThePublishedRange);
    });

    test('C5: at or above the optimistic estimate', () {
      expect(
        _at(2400).position,
        ThroughputPosition.atOrAboveTheOptimisticEstimate,
      );
    });

    test('C6, C7, C8: the boundaries land where they are documented', () {
      expect(
        _at(kFixtureCeiling * 0.40).position,
        ThroughputPosition.withinThePublishedRange,
      );
      expect(
        _at(kFixtureCeiling * 0.60).position,
        ThroughputPosition.withinThePublishedRange,
      );
      expect(
        _at(kFixtureCeiling * 0.80).position,
        ThroughputPosition.atOrAboveTheOptimisticEstimate,
      );
      expect(
        _at(kFixtureCeiling * 0.3999).position,
        ThroughputPosition.belowThePublishedRange,
      );
    });

    test('the percentage is the measurement over the ceiling, not rounded away',
        () {
      final ThroughputComparison c = _at(1441.1764705882354);
      expect(c.percentOfCeiling, closeTo(50.0, 0.0001));
    });
  });

  group('no ceiling means no comparison', () {
    test('C9: an unknown ceiling produces no position and no percentage', () {
      final ThroughputComparison c = _at(
        500,
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      expect(c.isComparable, isFalse);
      expect(c.position, isNull);
      expect(c.percentOfCeiling, isNull);
    });

    test('the copy names the missing value rather than going quiet', () {
      final ThroughputComparison c = _at(
        500,
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      expect(c.detail.contains('spatial streams'), isTrue);
      expect(c.headline.contains('500'), isTrue,
          reason: 'the measurement is still worth showing on its own');
    });

    // L-4, and the defect found next to it. The no-ceiling sentence used to
    // interpolate the unknown's `detail` directly. For a NOT-COMPUTABLE ceiling
    // that detail IS the derivation pin, so the user would have been shown
    // "this device does not tell us WifiPhyRateService.phyRateMbps over the
    // highest known standard…". Every reason now gets a finished sentence.
    // The reason a device has no ceiling is NOT the reason its fields are
    // unknown: the ceiling is derived, so an all-unknown device always reports
    // `derivedInputUnknown` no matter what its fields say. Reaching the other
    // branches needs devices actually built to land on them, which is why this
    // table constructs them rather than looping over the enum. A loop over
    // `CapabilityUnknownReason.values` looks broader and exercises one branch.
    final Map<String, ClientCapabilities> noCeilingDevices =
        <String, ClientCapabilities>{
      // Every input unknown -> derivedInputUnknown, detail = the input's name.
      'a platform that exposes nothing': ClientCapabilities.allUnknown(
        CapabilityUnknownReason.platformDoesNotExpose,
      ),
      'a model absent from the table': ClientCapabilities.allUnknown(
        CapabilityUnknownReason.deviceNotInTable,
      ),
      // One input missing, the rest known -> derivedInputUnknown.
      'a device that reports everything but its spatial streams': _device(
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      ),
      // Every input KNOWN, but the combination has no defined rate, so
      // compute() returns null -> notComputable, whose detail IS the
      // derivation pin. This is the branch that leaked a symbol name.
      'a device whose reported combination has no defined rate':
          _impossibleCombination(),
    };

    test('no reason leaks an internal identifier into the copy', () {
      noCeilingDevices.forEach((String label, ClientCapabilities device) {
        final ThroughputComparison c =
            ThroughputComparison.of(measuredMbps: 500, capabilities: device);
        expect(c.isComparable, isFalse, reason: '$label should have no ceiling');
        for (final String symbol in <String>[
          'WifiPhyRateService',
          'phyRateMbps',
          'Capability',
          'giKey',
        ]) {
          expect(
            c.detail.contains(symbol),
            isFalse,
            reason: '"$symbol" reached the screen for $label: ${c.detail}',
          );
        }
      });
    });

    test('every no-ceiling reason produces finished sentences', () {
      noCeilingDevices.forEach((String label, ClientCapabilities device) {
        final ThroughputComparison c =
            ThroughputComparison.of(measuredMbps: 500, capabilities: device);
        // The reason clause sits between two fixed sentences. If it does not
        // terminate itself, the paragraph runs straight on into the next one.
        expect(
          c.detail,
          contains('. The measurement stands on its own.'),
          reason: 'the reason clause for $label does not end in a full stop, '
              'so it runs into the sentence after it: ${c.detail}',
        );
        expect(c.detail.trim(), endsWith('.'), reason: c.detail);
        expect(c.detail.contains('..'), isFalse,
            reason: 'doubled full stop for $label: ${c.detail}');
        expect(c.detail.contains(r'$'), isFalse,
            reason: 'an uninterpolated placeholder for $label: ${c.detail}');
      });
    });

    test('the notComputable branch really is reached, so the two tests above '
        'are not vacuous', () {
      final Capability<double> ceiling =
          _impossibleCombination().theoreticalMaxPhyRateMbps;
      expect(
        (ceiling as UnknownCapability<double>).reason,
        CapabilityUnknownReason.notComputable,
        reason: 'if this stops being notComputable, the pin-leak branch is no '
            'longer covered by anything',
      );
      expect(ceiling.detail, contains('WifiPhyRateService'),
          reason: 'the detail must still BE the pin, or there is nothing to '
              'leak and the guard above proves nothing');
    });

    test('an unknown ceiling never states a percentage for the measurement',
        () {
      final ThroughputComparison c = _at(
        500,
        spatialStreams: const Capability<int>.unknown(
          CapabilityUnknownReason.platformDoesNotExpose,
        ),
      );
      // Scoped to the two strings that speak about THIS measurement. The
      // standing caveat legitimately quotes the published 40 to 60 percent
      // range, which is a general statement and not a claim about this reading.
      final RegExp aFigureInPercent = RegExp(r'\d+(\.\d+)? percent');
      expect(aFigureInPercent.hasMatch(c.headline), isFalse, reason: c.headline);
      expect(aFigureInPercent.hasMatch(c.detail), isFalse, reason: c.detail);
    });
  });

  group('a gap never appears without its reasons', () {
    test('every position below the ceiling carries the full reason list', () {
      for (final double mbps in <double>[500, 1200, 1700, 2000, 2400]) {
        final ThroughputComparison c = _at(mbps);
        expect(c.normalReasons, kNormalReasonsForAGap,
            reason: 'at $mbps Mbps the gap was shown with no explanation');
      }
    });

    test('a measurement at or above the ceiling has no gap to explain', () {
      expect(_at(3000).normalReasons, isEmpty);
    });

    test('the reasons blame physics and sharing, never the user or the network',
        () {
      expect(kNormalReasonsForAGap.length, 6);
      for (final String reason in kNormalReasonsForAGap) {
        expect(reason.trim(), isNotEmpty);
        expect(reason.endsWith('.'), isTrue);
      }
    });
  });

  group('the wording gate', () {
    test('no string turns a measurement into a verdict', () {
      // Each entry converts "we measured one number" into "something is wrong",
      // which is a claim about a network this app never looked at.
      const List<String> banned = <String>[
        'underperform',
        'poor ',
        'bad ',
        'weak',
        'slow wi-fi',
        'your wi-fi is',
        'your network is',
        'is broken',
        'is failing',
        'should be getting',
        'only getting',
        'you are only',
        'not getting what',
        'fix your',
        'boost the',
        'problem with your',
        'something is wrong',
        'make sure you are on wi-fi',
      ];
      for (final String s in _everyStringTheFeatureCanShow()) {
        final String lower = s.toLowerCase();
        for (final String bad in banned) {
          expect(lower.contains(bad), isFalse,
              reason: 'banned phrase "$bad" appears in: $s');
        }
      }
    });

    test('the lowest position is the one most likely to read as an accusation, '
        'so it says outright that it is not one', () {
      final ThroughputComparison c = _at(500);
      final String d = c.detail.toLowerCase();
      expect(d.contains('not an answer about your network'), isTrue,
          reason: 'the one case a user reads as blame must refuse the blame '
              'in words');
      expect(c.normalReasons, isNotEmpty);
    });

    test('the caveat states that the theoretical figure is not a target', () {
      final String caveat = _at(1200).caveat.toLowerCase();
      expect(caveat.contains('no device sustains it'), isTrue);
      expect(caveat.contains('40 to 60 percent'), isTrue,
          reason: 'the published range is the anchor, and it is not ours');
      expect(caveat.contains('normal case'), isTrue);
    });

    test('Wi-Fi is spelled Wi-Fi everywhere, never WiFi or Wifi', () {
      for (final String s in _everyStringTheFeatureCanShow()) {
        expect(RegExp(r'\bWiFi\b').hasMatch(s), isFalse, reason: s);
        expect(RegExp(r'\bWifi\b').hasMatch(s), isFalse, reason: s);
        expect(RegExp(r'\bwifi\b').hasMatch(s), isFalse, reason: s);
      }
    });

    test('no em dash in any user-facing string', () {
      for (final String s in _everyStringTheFeatureCanShow()) {
        expect(s.contains('—'), isFalse,
            reason: 'em dash in user-facing copy: $s');
      }
    });

    test('US spelling', () {
      const List<String> britishisms = <String>[
        'favourable',
        'behaviour',
        'optimise',
        'normalise',
        'analyse',
        'centre',
        'colour',
        'recognise',
      ];
      for (final String s in _everyStringTheFeatureCanShow()) {
        for (final String b in britishisms) {
          expect(s.toLowerCase().contains(b), isFalse,
              reason: '"$b" in: $s');
        }
      }
    });

    test('no string claims the app measured the network', () {
      for (final String s in _everyStringTheFeatureCanShow()) {
        final String lower = s.toLowerCase();
        expect(lower.contains('we measured your network'), isFalse);
        expect(lower.contains('we tested your network'), isFalse);
      }
    });
  });

  group('attribution the spec requires', () {
    test('HW052 and François Vergès are both named, with LCMI explained', () {
      expect(kClientCapabilitiesAttribution.contains('HW052'), isTrue);
      expect(
        kClientCapabilitiesAttribution.contains('Vergès'),
        isTrue,
        reason: 'the spec requires the credit by name',
      );
      expect(kClientCapabilitiesAttribution.contains('LCMI'), isTrue);
      expect(
        kClientCapabilitiesAttribution.contains('least capable most important'),
        isTrue,
        reason: 'the acronym on its own teaches nobody anything',
      );
      expect(kClientCapabilitiesAttribution.contains('13 May 2025'), isTrue);
    });
  });

  group('the published anchors are stated, not buried', () {
    test('the two anchors are the ones the outside source published', () {
      expect(kPublishedRealThroughputLow, 0.40);
      expect(kPublishedRealThroughputHigh, 0.60);
    });

    test('our own efficiency factors sit ABOVE the published range, which is '
        'why they are not used as the yardstick', () {
      // If this ever stops being true, the honesty note in the caveat becomes
      // wrong and has to be rewritten rather than quietly left in place.
      //
      // H-2. This READS the shipped factors rather than restating them as a
      // literal. A literal here asserts that 0.70 > 0.60, which is arithmetic,
      // not a fact about the code, and it stayed green when the factors were
      // mutated below Vajda's upper bound.
      expect(
        WifiPhyRateService.eff,
        isNotEmpty,
        reason: 'an empty table would make the reduce below vacuous',
      );
      final double lowestOurs =
          WifiPhyRateService.eff.values.reduce(math.min);
      expect(
        lowestOurs,
        greaterThan(kPublishedRealThroughputHigh),
        reason: 'the shipped caveat tells the user our own estimate sits above '
            'the published range. If that stops being true the sentence is '
            'false in user-facing copy.',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // M-3. `atOrAboveTheOptimisticEstimate` names "the favorable estimate this
  // app can produce". The classifier used to fall back to the CEILING when that
  // estimate was unknown, which made the favorable fraction exactly 1.0 and let
  // the copy name an estimate that did not exist. It is now emitted only when
  // the estimate is real.
  //
  // The branch is unreachable today because every standard has an eff factor,
  // so the first test PINS that reachability fact: if a standard is ever added
  // without one, it fails and says the dead branch just came alive.
  // ───────────────────────────────────────────────────────────────────────────
  group('M-3: a position never names a value the app does not have', () {
    test('the branch is currently unreachable, and this is what makes it so',
        () {
      final List<WifiStd> withoutEff = WifiStd.values
          .where((WifiStd s) => WifiPhyRateService.eff[s] == null)
          .toList();
      expect(
        withoutEff,
        isEmpty,
        reason: 'every standard has an efficiency factor, so a known ceiling '
            'always yields a known favorable estimate. If that stops being '
            'true, the no-estimate path in ThroughputComparison.of is now '
            'REACHABLE and its copy needs re-reading.',
      );
    });

    test('wherever the optimistic position IS emitted, the estimate behind it '
        'is real', () {
      final ClientCapabilities device = _device();
      bool sawTheOptimisticPosition = false;
      // Sweep the whole range rather than sampling the one value that happens
      // to land there.
      for (int i = 1; i <= 400; i++) {
        final ThroughputComparison c = ThroughputComparison.of(
          measuredMbps: kFixtureCeiling * i / 200,
          capabilities: device,
        );
        if (c.position != ThroughputPosition.atOrAboveTheOptimisticEstimate) {
          continue;
        }
        sawTheOptimisticPosition = true;
        expect(
          device.favorableThroughputEstimateMbps.isKnown,
          isTrue,
          reason: 'the copy for this position names an estimate the app '
              'produced. It must exist.',
        );
      }
      expect(
        sawTheOptimisticPosition,
        isTrue,
        reason: 'a sweep that never reaches the position under test proves '
            'nothing about it',
      );
    });
  });
}
