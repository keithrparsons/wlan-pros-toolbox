// 6 GHz power, PSD and SNR math for the Wi-Fi Lab 6 GHz Power and PSD tool.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/17-six-ghz-psd.md, with
// every limit taken from Deliverables/2026-09-25-wifi-lab-wave3-research/
// brief.md §1, which read the primary texts:
//   - US: 47 CFR §15.407(a)(4)-(a)(9), eCFR 2026-09-01 edition.
//   - EU: ETSI EN 303 687 V1.1.1 (2023-06), Tables 2 and 3.
// Pure Dart, no Flutter imports, so every number the screen shows is pinned
// by test/services/wifi_lab/six_ghz_psd_math_test.dart.
//
// The lesson in one line. A class is limited per MHz (PSD) and in total
// (max EIRP). While the PSD limit binds, EIRP = PSD + 10 log10(BW) grows 3 dB
// per doubling of width, which exactly offsets the 3 dB higher noise floor,
// so SNR holds. Once a cap binds, EIRP stops growing and SNR falls 3 dB per
// doubling.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'fspl_math.dart';

/// Regulatory region.
enum PsdRegion {
  us('US', 'US (FCC)'),
  eu('EU', 'EU (ETSI)');

  const PsdRegion(this.short, this.label);
  final String short;
  final String label;
}

/// A 6 GHz sub-band with its edges in MHz (47 CFR band edges; the EU band is
/// ETSI EN 303 687's 5945-6425 MHz).
enum SixGhzSubBand {
  unii5('U-NII-5', 5925, 6425),
  unii6('U-NII-6', 6425, 6525),
  unii7('U-NII-7', 6525, 6875),
  unii8('U-NII-8', 6875, 7125),
  eu('5945-6425 MHz', 5945, 6425);

  const SixGhzSubBand(this.label, this.lowMHz, this.highMHz);
  final String label;
  final double lowMHz;
  final double highMHz;
}

/// Which AP authorized power a relative client limit follows.
enum PsdAuthorizedBy { standardPower, gvp }

/// One regulatory device class and its limits.
enum PowerClass {
  // US, 47 CFR §15.407.
  usSpAp(
    region: PsdRegion.us,
    label: 'Standard Power AP',
    shortLabel: 'SP AP',
    rule: '15.407(a)(4)',
    psdDbmPerMHz: 23,
    maxEirpDbm: 36,
    subBands: <SixGhzSubBand>[SixGhzSubBand.unii5, SixGhzSubBand.unii7],
    ownGrant: PsdAuthorizedBy.standardPower,
  ),
  usFixedClient(
    region: PsdRegion.us,
    label: 'Fixed client device',
    shortLabel: 'Fixed client',
    rule: '15.407(a)(4)',
    psdDbmPerMHz: 23,
    maxEirpDbm: 36,
    subBands: <SixGhzSubBand>[SixGhzSubBand.unii5, SixGhzSubBand.unii7],
  ),
  usSpClient(
    region: PsdRegion.us,
    label: 'Standard Power client',
    shortLabel: 'SP client',
    rule: '15.407(a)(8)(i)',
    psdDbmPerMHz: 17,
    maxEirpDbm: 30,
    subBands: <SixGhzSubBand>[SixGhzSubBand.unii5, SixGhzSubBand.unii7],
    followsAp: PsdAuthorizedBy.standardPower,
  ),
  usLpiAp(
    region: PsdRegion.us,
    label: 'Low Power Indoor AP',
    shortLabel: 'LPI AP',
    rule: '15.407(a)(5)',
    psdDbmPerMHz: 5,
    maxEirpDbm: 30,
    subBands: _usAll,
  ),
  usSubordinate(
    region: PsdRegion.us,
    label: 'Subordinate device',
    shortLabel: 'Subordinate',
    rule: '15.407(a)(6)',
    psdDbmPerMHz: 5,
    maxEirpDbm: 30,
    subBands: _usAll,
  ),
  usLpiClient(
    region: PsdRegion.us,
    label: 'Low Power Indoor client',
    shortLabel: 'LPI client',
    rule: '15.407(a)(8)(ii)',
    psdDbmPerMHz: -1,
    maxEirpDbm: 24,
    subBands: _usAll,
  ),
  usGvpAp(
    region: PsdRegion.us,
    label: 'Geofenced Variable Power AP',
    shortLabel: 'GVP AP',
    rule: '15.407(a)(7)',
    psdDbmPerMHz: 11,
    maxEirpDbm: 24,
    subBands: <SixGhzSubBand>[SixGhzSubBand.unii5, SixGhzSubBand.unii7],
    ownGrant: PsdAuthorizedBy.gvp,
  ),
  usGvpClient(
    region: PsdRegion.us,
    label: 'Geofenced Variable Power client',
    shortLabel: 'GVP client',
    rule: '15.407(a)(8)(iii)',
    psdDbmPerMHz: 5,
    maxEirpDbm: 18,
    subBands: <SixGhzSubBand>[SixGhzSubBand.unii5, SixGhzSubBand.unii7],
    followsAp: PsdAuthorizedBy.gvp,
  ),
  usVlp(
    region: PsdRegion.us,
    label: 'Very Low Power device',
    shortLabel: 'VLP',
    rule: '15.407(a)(9)',
    psdDbmPerMHz: -5,
    maxEirpDbm: 14,
    subBands: _usAll,
  ),
  // EU, ETSI EN 303 687 V1.1.1, Tables 2 (mean EIRP) and 3 (PSD). The LPI
  // AP/bridge and LPI client share one limit: there is no client offset.
  euLpi(
    region: PsdRegion.eu,
    label: 'Low Power Indoor (AP or client)',
    shortLabel: 'EU LPI',
    rule: 'EN 303 687 Tables 2, 3',
    psdDbmPerMHz: 10,
    maxEirpDbm: 23,
    subBands: <SixGhzSubBand>[SixGhzSubBand.eu],
  ),
  euVlp(
    region: PsdRegion.eu,
    label: 'Very Low Power',
    shortLabel: 'EU VLP',
    rule: 'EN 303 687 Tables 2, 3',
    psdDbmPerMHz: 1,
    maxEirpDbm: 14,
    subBands: <SixGhzSubBand>[SixGhzSubBand.eu],
  );

  const PowerClass({
    required this.region,
    required this.label,
    required this.shortLabel,
    required this.rule,
    required this.psdDbmPerMHz,
    required this.maxEirpDbm,
    required this.subBands,
    this.followsAp,
    this.ownGrant,
  });

  final PsdRegion region;
  final String label;
  final String shortLabel;

  /// Where the limit is written.
  final String rule;

  /// PSD limit, dBm EIRP in any 1 MHz.
  final double psdDbmPerMHz;

  /// Maximum total EIRP, dBm.
  final double maxEirpDbm;

  /// Sub-bands the class may use.
  final List<SixGhzSubBand> subBands;

  /// Set for SP and GVP clients: EIRP may not exceed the associated AP's
  /// authorized power minus 6 dB (§15.407(a)(8)(i) and (iii)).
  final PsdAuthorizedBy? followsAp;

  /// Set for SP and GVP APs: the AP cannot radiate more than it was
  /// authorized (by the AFC or the geofencing system).
  final PsdAuthorizedBy? ownGrant;

  static List<PowerClass> forRegion(PsdRegion r) => <PowerClass>[
    for (final PowerClass c in values)
      if (c.region == r) c,
  ];
}

const List<SixGhzSubBand> _usAll = <SixGhzSubBand>[
  SixGhzSubBand.unii5,
  SixGhzSubBand.unii6,
  SixGhzSubBand.unii7,
  SixGhzSubBand.unii8,
];

/// What set a class's EIRP at a width.
enum PsdLimit {
  /// PSD x bandwidth: the per-MHz rule binds.
  psd,

  /// The class's maximum EIRP binds.
  cap,

  /// 6 dB below the associated AP's authorized power binds (SP, GVP client).
  apRelative,

  /// The AP's own authorized power binds (SP, GVP AP).
  authorized;

  /// PSD-limited or not; every other limit is a cap on total power.
  bool get isPsd => this == PsdLimit.psd;
}

/// EIRP of a class at a width and what limited it.
typedef PsdEirp = ({double eirpDbm, PsdLimit limit});

abstract final class SixGhzPsdMath {
  /// Channel widths the tool steps through, MHz.
  static const List<int> widthsMHz = <int>[20, 40, 80, 160, 320];

  /// Thermal noise density, dBm/Hz (kT at 290 K).
  static const double thermalNoiseDbmPerHz = -174;

  /// Default receiver noise figure, dB (spec 17).
  static const double defaultNoiseFigureDb = 7;

  /// Default AP authorized EIRPs: the class maximums.
  static const double defaultSpAuthorizedDbm = 36;
  static const double defaultGvpAuthorizedDbm = 24;

  /// The client offset from its AP's authorized power, dB.
  static const double clientOffsetDb = 6;

  /// Path loss is evaluated at one fixed frequency for every width, so only
  /// the width changes between columns. 6105 MHz is the center of 20 MHz
  /// channel 31 and of 320 MHz channel 31, inside U-NII-5 and inside the EU
  /// band, so it is legal for every class in both regions.
  static const double referenceFreqMHz = 6105;

  /// 10 log10(BW in MHz): the dB the PSD limit gains from a wider channel.
  static double bandwidthDb(int widthMHz) =>
      FsplMath.log10(widthMHz * 1.0) * 10;

  /// PSD limit times width, before any cap.
  static double psdEirpDbm(PowerClass c, int widthMHz) =>
      c.psdDbmPerMHz + bandwidthDb(widthMHz);

  /// EIRP = min(PSD + 10 log10(BW), max EIRP), and for SP and GVP clients also
  /// min(..., AP authorized - 6). An SP or GVP AP is also held to its own
  /// authorized power. Ties go to the cap: a class that exactly reaches its
  /// cap is no longer gaining from width.
  static PsdEirp eirp(
    PowerClass c,
    int widthMHz, {
    double spAuthorizedDbm = defaultSpAuthorizedDbm,
    double gvpAuthorizedDbm = defaultGvpAuthorizedDbm,
  }) {
    double auth(PsdAuthorizedBy a) =>
        a == PsdAuthorizedBy.standardPower ? spAuthorizedDbm : gvpAuthorizedDbm;
    double best = psdEirpDbm(c, widthMHz);
    PsdLimit limit = PsdLimit.psd;
    void apply(double v, PsdLimit why, {required bool winsTie}) {
      if (v < best || (winsTie && v == best)) {
        best = v;
        limit = why;
      }
    }

    // The class's own cap wins a tie with the PSD product. The AP-derived
    // limits only win when strictly lower, so an SP client under an AP at the
    // full 36 dBm reads as capped at its own 30, not as following its AP.
    apply(c.maxEirpDbm, PsdLimit.cap, winsTie: true);
    final PsdAuthorizedBy? own = c.ownGrant;
    if (own != null) apply(auth(own), PsdLimit.authorized, winsTie: false);
    final PsdAuthorizedBy? ap = c.followsAp;
    if (ap != null) {
      apply(auth(ap) - clientOffsetDb, PsdLimit.apRelative, winsTie: false);
    }
    return (eirpDbm: best, limit: limit);
  }

  /// The PSD actually radiated, dBm/MHz: EIRP spread evenly over the width.
  /// Equal to the PSD limit while PSD-limited; below it once a cap binds.
  static double radiatedPsdDbmPerMHz(double eirpDbm, int widthMHz) =>
      eirpDbm - bandwidthDb(widthMHz);

  /// Receiver noise floor, dBm: -174 dBm/Hz + 10 log10(BW Hz) + NF.
  static double noiseFloorDbm(int widthMHz, double noiseFigureDb) =>
      thermalNoiseDbmPerHz +
      10 * FsplMath.log10(widthMHz * 1e6) +
      noiseFigureDb;

  /// Received power, dBm: EIRP minus free-space loss at [referenceFreqMHz]
  /// minus extra loss. The receive antenna is 0 dBi.
  static double receivedDbm(
    double eirpDbm,
    double distanceM,
    double extraLossDb,
  ) => FsplMath.receivedPowerDbm(
    txPowerDbm: eirpDbm,
    txGainDbi: 0,
    rxGainDbi: 0,
    pathLossDb: FsplMath.fsplDb(distanceM, referenceFreqMHz),
    otherLossesDb: extraLossDb,
  );

  /// SNR, dB: received power minus the noise floor.
  static double snrDb({
    required double eirpDbm,
    required int widthMHz,
    required double distanceM,
    required double extraLossDb,
    required double noiseFigureDb,
  }) =>
      receivedDbm(eirpDbm, distanceM, extraLossDb) -
      noiseFloorDbm(widthMHz, noiseFigureDb);

  // ── Channels ────────────────────────────────────────────────────────────

  /// Center frequency of a 6 GHz channel number, MHz: 5950 + 5 x ch.
  static double centerMHz(int channel) => 5950 + 5.0 * channel;

  /// Every channel placement at a width, by channel number: the 802.11
  /// 6 GHz channelization (20 MHz 1..233 step 4; 40 MHz centers 3..227 step
  /// 8; 80 MHz 7..215 step 16; 160 MHz 15..207 step 32; 320 MHz 31..191 step
  /// 32, where neighbours overlap).
  static List<int> placements(int widthMHz) {
    final (int first, int last, int step) = switch (widthMHz) {
      20 => (1, 233, 4),
      40 => (3, 227, 8),
      80 => (7, 215, 16),
      160 => (15, 207, 32),
      320 => (31, 191, 32),
      _ => throw ArgumentError.value(widthMHz, 'widthMHz'),
    };
    return <int>[for (int c = first; c <= last; c += step) c];
  }

  /// True when the whole channel sits inside one sub-band of [c].
  static bool channelAllowed(PowerClass c, int channel, int widthMHz) {
    final double lo = centerMHz(channel) - widthMHz / 2;
    final double hi = centerMHz(channel) + widthMHz / 2;
    // US LPI and VLP may use all four contiguous sub-bands as one block.
    final List<(double, double)> spans = _merged(c.subBands);
    return spans.any(((double, double) s) => lo >= s.$1 && hi <= s.$2);
  }

  static List<(double, double)> _merged(List<SixGhzSubBand> bands) {
    final List<SixGhzSubBand> sorted = <SixGhzSubBand>[
      ...bands,
    ]..sort((SixGhzSubBand a, SixGhzSubBand b) => a.lowMHz.compareTo(b.lowMHz));
    final List<(double, double)> out = <(double, double)>[];
    for (final SixGhzSubBand b in sorted) {
      if (out.isNotEmpty && out.last.$2 >= b.lowMHz) {
        out[out.length - 1] = (out.last.$1, math.max(out.last.$2, b.highMHz));
      } else {
        out.add((b.lowMHz, b.highMHz));
      }
    }
    return out;
  }

  /// Non-overlapping channels of [widthMHz] the class may use, counted by
  /// taking allowed placements in frequency order and skipping any that
  /// overlap the last one taken.
  static int channelCount(PowerClass c, int widthMHz) {
    int n = 0;
    double lastHigh = double.negativeInfinity;
    for (final int ch in placements(widthMHz)) {
      if (!channelAllowed(c, ch, widthMHz)) continue;
      final double lo = centerMHz(ch) - widthMHz / 2;
      if (lo < lastHigh) continue;
      n++;
      lastHigh = centerMHz(ch) + widthMHz / 2;
    }
    return n;
  }

  /// Sub-band list in words, for readouts.
  static String subBandText(PowerClass c) {
    if (c.region == PsdRegion.eu) return '5945-6425 MHz';
    if (c.subBands.length == 4) return 'U-NII-5 to U-NII-8';
    return c.subBands.map((SixGhzSubBand b) => b.label).join(' and ');
  }
}
