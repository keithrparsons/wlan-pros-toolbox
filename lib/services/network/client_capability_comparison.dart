// Client Capabilities — reading a measured throughput against what the device
// could theoretically produce.
//
// Step 6 of the Client Capabilities build (spec:
// Deliverables/2026-07-31-client-capabilities-spec/SPEC.md). This file holds the
// CLAIMS, not the pixels: the relationship, the wording, and the reasons. A
// screen renders what this produces and adds nothing of its own.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS IS THE MOST DANGEROUS FILE IN THE FEATURE
//
// The payoff is "your device could do X, you measured Y", and that sentence
// ships as an accusation unless it is written not to. The app cannot see the
// network. It measured one number on one device at one moment. Turning that
// into "your Wi-Fi is underperforming" is inventing a finding out of an absence,
// and it is the specific failure this app, under a Wi-Fi authority's name,
// cannot make.
//
// THREE RULES, EACH ENFORCED BY A TEST RATHER THAN BY GOOD INTENTIONS:
//
//  1. STATE A RELATIONSHIP, NEVER A VERDICT. Every string here says where the
//     measurement sits relative to a published range. None of them says whether
//     that is good, bad, or someone's fault.
//  2. A GAP NEVER APPEARS WITHOUT ITS REASONS. Falling short of a theoretical
//     ceiling is what a healthy link does. [normalReasons] is non-empty whenever
//     there is a gap, and the screen prints it next to the number.
//  3. NO CEILING MEANS NO COMPARISON. When the device's capabilities are not
//     known, there is no percentage, no position and no relationship. The copy
//     says which value is missing.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE TWO PUBLISHED ANCHORS, AND WHY WE USE SOMEONE ELSE'S
//
// Jim Vajda (CWNE #183), "Data Rates Are Dead", framebyframewifi.net,
// 4 September 2023: actual throughput is roughly 40 to 60 percent of the PHY
// rate. That is an outside number, which is the point. Our own
// [WifiPhyRateService.eff] factors run 0.70 to 0.80, ABOVE the top of his range,
// so our own optimistic estimate is the wrong thing to measure a user against
// and is used here only as the upper marker.
//
// The same article is why the theoretical ceiling is not the headline. Three
// stations at the same MCS can show wildly different rates for reasons that have
// nothing to do with link quality, so a big number at the top of a screen
// participates in the confusion rather than clearing it.

import 'client_capabilities.dart';

/// Where a measured throughput sits relative to the published ranges.
///
/// These are POSITIONS, not grades. Nothing here means "good" or "bad", and the
/// labels are written so they cannot be read that way.
enum ThroughputPosition {
  /// Below the 40 to 60 percent of PHY rate commonly published for real
  /// throughput.
  belowThePublishedRange,

  /// Inside the published 40 to 60 percent range.
  withinThePublishedRange,

  /// Above the published range, below our own optimistic estimate.
  aboveThePublishedRange,

  /// At or above our own optimistic estimate, which is already a favorable
  /// number.
  atOrAboveTheOptimisticEstimate,
}

/// The published lower bound for real throughput as a fraction of the PHY rate.
///
/// Jim Vajda, "Data Rates Are Dead", framebyframewifi.net, 4 September 2023.
const double kPublishedRealThroughputLow = 0.40;

/// The published upper bound. Same source.
const double kPublishedRealThroughputHigh = 0.60;

/// The reasons a perfectly healthy client falls short of its theoretical
/// ceiling.
///
/// This list is not decoration. It is the difference between a number and an
/// accusation, and it is printed next to the number every time there is a gap.
/// Order is stable so the screen and any golden agree.
const List<String> kNormalReasonsForAGap = <String>[
  'Protocol overhead. Some of every transmission is spent on headers, '
      'acknowledgements and spacing, and none of it carries your data.',
  'Airtime is shared. Every other device on the channel, including ones that '
      'are not yours, takes a turn.',
  'Rate adaptation. A client steps down to a slower, sturdier modulation the '
      'moment that is the faster way to get the data through.',
  'MIMO conditions. The number of spatial streams a link actually sustains '
      'depends on the radio environment, not only on the hardware.',
  'Band steering. A device can be moved to a band that is less busy but '
      'slower.',
  'Power save. A battery-powered client sleeps between frames on purpose.',
];

/// A measured throughput read against a device ceiling.
///
/// Immutable. Build it with [ThroughputComparison.of], which is a pure function
/// of its inputs.
class ThroughputComparison {
  const ThroughputComparison._({
    required this.measuredMbps,
    required this.ceiling,
    required this.position,
    required this.percentOfCeiling,
    required this.headline,
    required this.detail,
    required this.normalReasons,
    required this.caveat,
  });

  /// Compares [measuredMbps] against the ceiling in [capabilities].
  ///
  /// Returns a comparison with a null [position] whenever the ceiling is
  /// unknown. There is no fallback ceiling and no assumed device.
  static ThroughputComparison of({
    required double measuredMbps,
    required ClientCapabilities capabilities,
  }) {
    final Capability<double> ceiling = capabilities.theoreticalMaxPhyRateMbps;
    final double? ceilingMbps = ceiling.valueOrNull;

    if (ceilingMbps == null || ceilingMbps <= 0) {
      final String missing = ceiling is UnknownCapability<double>
          ? (ceiling.detail ?? ceiling.reason.label)
          : 'the device ceiling';
      return ThroughputComparison._(
        measuredMbps: measuredMbps,
        ceiling: ceiling,
        position: null,
        percentOfCeiling: null,
        headline: 'You measured ${_mbps(measuredMbps)}.',
        detail: 'There is nothing to compare it against yet, because this '
            'device does not tell us $missing. The measurement stands on its '
            'own.',
        normalReasons: const <String>[],
        caveat: _kCaveat,
      );
    }

    final double fraction = measuredMbps / ceilingMbps;
    final double favorableFraction =
        (capabilities.favorableThroughputEstimateMbps.valueOrNull ??
                ceilingMbps) /
            ceilingMbps;

    final ThroughputPosition position;
    if (fraction < kPublishedRealThroughputLow) {
      position = ThroughputPosition.belowThePublishedRange;
    } else if (fraction <= kPublishedRealThroughputHigh) {
      position = ThroughputPosition.withinThePublishedRange;
    } else if (fraction < favorableFraction) {
      position = ThroughputPosition.aboveThePublishedRange;
    } else {
      position = ThroughputPosition.atOrAboveTheOptimisticEstimate;
    }

    final bool thereIsAGap = fraction < 1.0;

    return ThroughputComparison._(
      measuredMbps: measuredMbps,
      ceiling: ceiling,
      position: position,
      percentOfCeiling: fraction * 100,
      headline: 'You measured ${_mbps(measuredMbps)}. This device tops out at '
          '${_mbps(ceilingMbps)} in theory.',
      detail: _detailFor(position, fraction),
      normalReasons:
          thereIsAGap ? kNormalReasonsForAGap : const <String>[],
      caveat: _kCaveat,
    );
  }

  /// The measured figure, in Mbps.
  final double measuredMbps;

  /// The theoretical ceiling, with its own provenance. May be unknown.
  final Capability<double> ceiling;

  /// Where the measurement sits, or null when there is no ceiling to sit
  /// against.
  final ThroughputPosition? position;

  /// The measurement as a percentage of the ceiling, or null when there is no
  /// ceiling.
  final double? percentOfCeiling;

  /// One line stating the two numbers. Never a judgement.
  final String headline;

  /// One paragraph stating where the measurement sits, and what that does and
  /// does not mean.
  final String detail;

  /// The ordinary reasons a healthy client falls short. Empty only when there
  /// is no gap to explain.
  final List<String> normalReasons;

  /// The standing honesty note about the ceiling itself.
  final String caveat;

  /// True when the app has enough to make any comparison at all.
  bool get isComparable => position != null;

  /// Every user-facing string this comparison produces, so a wording check can
  /// see all of them in one place rather than sampling.
  List<String> get allCopy => <String>[
        headline,
        detail,
        caveat,
        ...normalReasons,
      ];

  static const String _kCaveat =
      'The theoretical figure assumes the widest channel, every spatial '
      'stream, the highest modulation and a quiet radio environment, all at '
      'once. No device sustains it. Published measurements put real throughput '
      'at roughly 40 to 60 percent of the theoretical rate, and our own '
      'estimate of achievable throughput sits above even that, so falling '
      'short of either is the normal case and not a finding about your '
      'network.';

  static String _detailFor(ThroughputPosition position, double fraction) {
    final String pct = '${(fraction * 100).round()} percent';
    switch (position) {
      case ThroughputPosition.belowThePublishedRange:
        return 'That is $pct of the theoretical figure, which is below the 40 '
            'to 60 percent that published measurements associate with a '
            'working link. This app measured one number on one device, so '
            'that is a question to look into, not an answer about your '
            'network. The reasons below are all ordinary, and any of them can '
            'produce this on its own.';
      case ThroughputPosition.withinThePublishedRange:
        return 'That is $pct of the theoretical figure, which sits inside the '
            '40 to 60 percent that published measurements associate with a '
            'working link.';
      case ThroughputPosition.aboveThePublishedRange:
        return 'That is $pct of the theoretical figure, which is above the 40 '
            'to 60 percent that published measurements associate with a '
            'working link.';
      case ThroughputPosition.atOrAboveTheOptimisticEstimate:
        return 'That is $pct of the theoretical figure, at or above even the '
            'favorable estimate this app can produce for achievable '
            'throughput.';
    }
  }

  static String _mbps(double v) {
    if (v >= 100) return '${v.round()} Mbps';
    if (v >= 10) return '${v.toStringAsFixed(1)} Mbps';
    return '${v.toStringAsFixed(2)} Mbps';
  }
}

/// Attribution the spec requires wherever this feature explains itself.
///
/// Heavy Wireless HW052, "How Capable Is My Wi-Fi Client?", 13 May 2025, Keith
/// Parsons hosting François Vergès. That episode is where the framing comes
/// from, including LCMI, the least capable most important device, which is the
/// question a designer is actually asking when they ask what a client can do.
///
/// Held as a constant rather than typed into a screen so there is exactly one
/// copy of it and a test can check it is present.
const String kClientCapabilitiesAttribution =
    'The thinking behind this tool comes from Heavy Wireless episode HW052, '
    '"How Capable Is My Wi-Fi Client?", from 13 May 2025, with '
    'François Vergès. That conversation is also where LCMI comes from, the '
    'least capable most important device, which is the client a design has to '
    'serve even though it is not the fastest one on the network.';
