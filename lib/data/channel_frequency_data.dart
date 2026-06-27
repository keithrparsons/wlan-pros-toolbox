// Wi-Fi Channel <-> Frequency conversion engine + verified channel-plan data.
//
// SOURCE OF TRUTH: Deliverables/2026-06-27-channel-frequency-plan/channel-plan.md
// (primary-source-verified by Pax against IEEE 802.11-2020/2024 channelization +
// FCC 6 GHz / 5.9 GHz Reports & Orders). Every value here is either universal
// physics (channel<->frequency arithmetic) or a verified channel set. NO channel
// data is pulled from any secondary source. In particular the 6 GHz start
// frequency is 5950 (so channel 1 = 5955, channel 2 = 5935 special), NOT the
// wrong 5940+5n some bad sources use.
//
// THE SINGLE RULE: center_freq_MHz = channel_starting_freq + 5 x channel_number,
// with two hard-coded special cases (2.4 GHz ch14 = 2484; 6 GHz ch2 = 5935).
//
// PHYSICS vs REGULATORY: channel<->frequency is universal physics, identical
// everywhere. Channel AVAILABILITY (US 1-11 vs world 1-13, DFS, UNII-4, 6 GHz
// country adoption, ch2/ch14) is regulatory. This engine computes the physics;
// availability is surfaced as a caveat string, never as a reason to change a
// computed frequency.
//
// Glyph note: ASCII hyphen-minus and +/- throughout; no em dash (GL-004).

import 'package:flutter/foundation.dart';

/// The three Wi-Fi bands the converter spans. The band is REQUIRED for
/// channel->frequency because channel NUMBERS collide across 5 and 6 GHz
/// (channel 36 exists in both); frequency->channel returns the band because
/// the frequency RANGES are disjoint.
enum WifiBand {
  band24,
  band5,
  band6,
}

extension WifiBandInfo on WifiBand {
  /// Display label, e.g. `2.4 GHz`.
  String get label {
    switch (this) {
      case WifiBand.band24:
        return '2.4 GHz';
      case WifiBand.band5:
        return '5 GHz';
      case WifiBand.band6:
        return '6 GHz';
    }
  }

  /// The channel_starting_freq for the linear formula (MHz). Special-case
  /// channels (2.4 ch14, 6 ch2) bypass this.
  int get startFreqMHz {
    switch (this) {
      case WifiBand.band24:
        return 2407;
      case WifiBand.band5:
        return 5000;
      case WifiBand.band6:
        return 5950;
    }
  }

  /// Channel widths (MHz) valid for this band, narrow -> wide.
  List<int> get widthsMHz {
    switch (this) {
      case WifiBand.band24:
        return const <int>[20, 40];
      case WifiBand.band5:
        return const <int>[20, 40, 80, 160];
      case WifiBand.band6:
        return const <int>[20, 40, 80, 160, 320];
    }
  }
}

// ─── Valid 20 MHz primary channels (the selectable channels) ────────────────

/// 2.4 GHz: 1..14 (14 is the 2484 special case).
const List<int> k24Channels = <int>[
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
];

/// 5 GHz valid 20 MHz primaries (channel-plan.md sec 3.1). This is the EXACT
/// allowed set; anything else (e.g. 37, 49, 51, 145, 181) is rejected.
const List<int> k5Channels = <int>[
  36, 40, 44, 48, // UNII-1
  52, 56, 60, 64, // UNII-2A (DFS)
  100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, // UNII-2C (DFS)
  149, 153, 157, 161, 165, // UNII-3
  169, 173, 177, // UNII-4
];

/// 6 GHz valid 20 MHz primaries: the arithmetic sequence 1, 5, 9, ... 233
/// (step 4), PLUS the special channel 2 (5935). Computed, not hard-coded.
final List<int> k6Channels = <int>[
  2, // special, sits just below channel 1
  for (int n = 1; n <= 233; n += 4) n,
];

/// 6 GHz Preferred Scanning Channels (channel-plan.md sec 4.3) — 15 channels,
/// 80 MHz apart, starting at 5.
const Set<int> k6Psc = <int>{
  5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229,
};

/// 5 GHz DFS channels (channel-plan.md sec 3.1) — radar-detection required;
/// availability is regulatory.
const Set<int> k5Dfs = <int>{
  52, 56, 60, 64, // UNII-2A
  100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, // UNII-2C
};

/// 5 GHz UNII-4 channels (US-led, FCC 20-164) — not available in many regions.
const Set<int> k5Unii4 = <int>{169, 173, 177};

// ─── Bonding groups: component 20 MHz channels per wide channel ─────────────
// Each inner list is the contiguous component 20 MHz channels of one wide
// channel. 5 GHz groups are listed verbatim from channel-plan.md sec 5.2 (the
// DFS gaps mean they do NOT tile naively). 6 GHz groups are computed from the
// regular center-channel sequences in sec 5.3. 2.4 GHz 40 MHz pairs are the
// HT40 bonds {p, p+4}.

/// 2.4 GHz 40 MHz bonds: {p, p+4} for p in 1..9. An interior primary (e.g. 6)
/// belongs to two of these (HT40- with the lower, HT40+ with the higher) — both
/// are real, so both are returned.
final List<List<int>> k24Bond40 = <List<int>>[
  for (int p = 1; p <= 9; p++) <int>[p, p + 4],
];

const List<List<int>> k5Bond40 = <List<int>>[
  <int>[36, 40], <int>[44, 48], <int>[52, 56], <int>[60, 64],
  <int>[100, 104], <int>[108, 112], <int>[116, 120], <int>[124, 128],
  <int>[132, 136], <int>[140, 144], <int>[149, 153], <int>[157, 161],
  <int>[165, 169], <int>[173, 177],
];

const List<List<int>> k5Bond80 = <List<int>>[
  <int>[36, 40, 44, 48], <int>[52, 56, 60, 64],
  <int>[100, 104, 108, 112], <int>[116, 120, 124, 128],
  <int>[132, 136, 140, 144], <int>[149, 153, 157, 161],
  <int>[165, 169, 173, 177],
];

const List<List<int>> k5Bond160 = <List<int>>[
  <int>[36, 40, 44, 48, 52, 56, 60, 64],
  <int>[100, 104, 108, 112, 116, 120, 124, 128],
  <int>[149, 153, 157, 161, 165, 169, 173, 177],
];

/// Build 6 GHz bonding groups from the center-channel sequences (sec 5.3).
/// A width-W group has N = W/20 components, contiguous on the 4-step 20 MHz
/// grid, centered on the given center channel.
List<List<int>> _build6Bond(Iterable<int> centers, int n) {
  return <List<int>>[
    for (final int c in centers)
      <int>[for (int i = 0; i < n; i++) c - 2 * (n - 1) + 4 * i],
  ];
}

/// 6 GHz 40 MHz: centers 3, 11, ... 227 (step 8).
final List<List<int>> k6Bond40 =
    _build6Bond(<int>[for (int c = 3; c <= 227; c += 8) c], 2);

/// 6 GHz 80 MHz: centers 7, 23, ... 215 (step 16).
final List<List<int>> k6Bond80 =
    _build6Bond(<int>[for (int c = 7; c <= 215; c += 16) c], 4);

/// 6 GHz 160 MHz: centers 15, 47, ... 207 (step 32).
final List<List<int>> k6Bond160 =
    _build6Bond(<int>[for (int c = 15; c <= 207; c += 32) c], 8);

/// 6 GHz 320 MHz: centers 31, 63, 95, 127, 159, 191. These OVERLAP by design
/// in 802.11be (an odd number of 160 MHz blocks), so a primary can land in two
/// of them. Both placements are returned; the engine does NOT assert the
/// unverified 320 MHz-1 / 320 MHz-2 scheme labels.
final List<List<int>> k6Bond320 =
    _build6Bond(<int>[31, 63, 95, 127, 159, 191], 16);

/// Returns the bonding groups for [band] at [widthMHz], or `const []` for a
/// width with no bonding table (e.g. 20 MHz, or an out-of-band width).
List<List<int>> bondingGroups(WifiBand band, int widthMHz) {
  switch (band) {
    case WifiBand.band24:
      return widthMHz == 40 ? k24Bond40 : const <List<int>>[];
    case WifiBand.band5:
      switch (widthMHz) {
        case 40:
          return k5Bond40;
        case 80:
          return k5Bond80;
        case 160:
          return k5Bond160;
        default:
          return const <List<int>>[];
      }
    case WifiBand.band6:
      switch (widthMHz) {
        case 40:
          return k6Bond40;
        case 80:
          return k6Bond80;
        case 160:
          return k6Bond160;
        case 320:
          return k6Bond320;
        default:
          return const <List<int>>[];
      }
  }
}

// ─── Pure conversion functions ──────────────────────────────────────────────

/// Returns `true` when [channel] is a selectable 20 MHz primary in [band].
/// Bonded center designators (5 GHz 38/42/50, 6 GHz 3/7/15/31) and off-plan
/// numbers are NOT valid primaries and return `false`.
bool isValid20MhzPrimary(WifiBand band, int channel) {
  switch (band) {
    case WifiBand.band24:
      return k24Channels.contains(channel);
    case WifiBand.band5:
      return k5Channels.contains(channel);
    case WifiBand.band6:
      return k6Channels.contains(channel);
  }
}

/// The valid 20 MHz primaries for [band], in ascending order.
List<int> channelsFor(WifiBand band) {
  switch (band) {
    case WifiBand.band24:
      return k24Channels;
    case WifiBand.band5:
      return k5Channels;
    case WifiBand.band6:
      return k6Channels;
  }
}

/// CHANNEL -> FREQUENCY (center frequency, MHz).
///
/// Applies the linear rule `start + 5 x channel` with the two hard-coded
/// special cases. Defined for any channel number on the band's channelization
/// (20 MHz primaries AND bonded center designators), per channel-plan.md sec 1.
/// Returns `null` for a channel number that is not on the channelization.
///
/// [band] is REQUIRED: channel numbers collide across 5 and 6 GHz, so the band
/// disambiguates (channel-plan.md sec 6.3).
int? channelToFrequency(WifiBand band, int channel) {
  // Special cases first — the formula must never touch these.
  if (band == WifiBand.band24 && channel == 14) return 2484;
  if (band == WifiBand.band6 && channel == 2) return 5935;

  if (!_isOnChannelization(band, channel)) return null;
  return band.startFreqMHz + 5 * channel;
}

/// `true` when [channel] is either a valid 20 MHz primary OR a valid bonded
/// center designator for [band] — i.e. the formula is defined for it.
bool _isOnChannelization(WifiBand band, int channel) {
  if (isValid20MhzPrimary(band, channel)) return true;
  // A bonded center designator is the mean of some bonding group's components.
  for (final int width in band.widthsMHz) {
    if (width == 20) continue;
    for (final List<int> group in bondingGroups(band, width)) {
      if (_centerChannelOf(group) == channel) return true;
    }
  }
  return false;
}

/// FREQUENCY -> (band, channel). Snaps [mhz] to the 5 MHz grid with a +/-1 MHz
/// tolerance (channel-plan.md sec 1, sec 6.5) and returns the matching band +
/// 20 MHz primary channel, or `null` when nothing valid is within tolerance.
///
/// Frequency ranges are disjoint across bands, so the result is unambiguous and
/// the band is returned (never needed as input).
({WifiBand band, int channel})? frequencyToChannel(double mhz) {
  const double tolerance = 1.0;
  ({WifiBand band, int channel})? best;
  double bestDelta = double.infinity;

  for (final WifiBand band in WifiBand.values) {
    for (final int channel in channelsFor(band)) {
      final int? center = channelToFrequency(band, channel);
      if (center == null) continue;
      final double delta = (mhz - center).abs();
      if (delta <= tolerance && delta < bestDelta) {
        best = (band: band, channel: channel);
        bestDelta = delta;
      }
    }
  }
  return best;
}

/// One wide-channel placement: a primary 20 MHz channel resolved into the
/// contiguous group it belongs to at a chosen width, with the verified center
/// channel/frequency and band edges.
@immutable
class BondedChannel {
  const BondedChannel({
    required this.band,
    required this.widthMHz,
    required this.components,
    required this.centerChannel,
    required this.centerFreqMHz,
    required this.lowEdgeMHz,
    required this.highEdgeMHz,
  });

  final WifiBand band;
  final int widthMHz;

  /// The contiguous component 20 MHz channels, ascending.
  final List<int> components;

  /// The center-channel designator (mean of [components]). For a wide channel
  /// this is NOT a selectable 20 MHz primary — it is a center designator only.
  final int centerChannel;

  final int centerFreqMHz;
  final int lowEdgeMHz;
  final int highEdgeMHz;
}

int _centerChannelOf(List<int> components) {
  int sum = 0;
  for (final int c in components) {
    sum += c;
  }
  return sum ~/ components.length;
}

/// All wide-channel placements of [primaryChannel] at [widthMHz] in [band].
///
/// Usually returns exactly one placement. Returns TWO for an interior 2.4 GHz
/// 40 MHz primary (HT40- and HT40+) and for a 6 GHz 320 MHz primary that falls
/// in two overlapping 320 MHz channels (802.11be, by design). Returns an empty
/// list when [primaryChannel] is not a valid 20 MHz primary, or cannot form a
/// channel of [widthMHz].
List<BondedChannel> bondedChannels({
  required WifiBand band,
  required int primaryChannel,
  required int widthMHz,
}) {
  if (!isValid20MhzPrimary(band, primaryChannel)) return const <BondedChannel>[];

  // 20 MHz: the channel is its own only component.
  if (widthMHz == 20) {
    final int? center = channelToFrequency(band, primaryChannel);
    if (center == null) return const <BondedChannel>[];
    return <BondedChannel>[
      BondedChannel(
        band: band,
        widthMHz: 20,
        components: <int>[primaryChannel],
        centerChannel: primaryChannel,
        centerFreqMHz: center,
        lowEdgeMHz: center - 10,
        highEdgeMHz: center + 10,
      ),
    ];
  }

  final List<BondedChannel> results = <BondedChannel>[];
  for (final List<int> group in bondingGroups(band, widthMHz)) {
    if (!group.contains(primaryChannel)) continue;
    final int centerChannel = _centerChannelOf(group);
    // Center frequency = mean of the component center frequencies (first-
    // principles; equals start + 5 x centerChannel for these groups).
    int sum = 0;
    for (final int c in group) {
      sum += band.startFreqMHz + 5 * c;
    }
    final int centerFreq = sum ~/ group.length;
    results.add(
      BondedChannel(
        band: band,
        widthMHz: widthMHz,
        components: List<int>.unmodifiable(group),
        centerChannel: centerChannel,
        centerFreqMHz: centerFreq,
        lowEdgeMHz: centerFreq - widthMHz ~/ 2,
        highEdgeMHz: centerFreq + widthMHz ~/ 2,
      ),
    );
  }
  results.sort((BondedChannel a, BondedChannel b) =>
      a.centerFreqMHz.compareTo(b.centerFreqMHz));
  return results;
}

/// Convenience single-result accessor (the lowest-center placement), for the
/// common case and the verification vectors. Returns `null` when there is none.
BondedChannel? bondedChannel({
  required WifiBand band,
  required int primaryChannel,
  required int widthMHz,
}) {
  final List<BondedChannel> all = bondedChannels(
    band: band,
    primaryChannel: primaryChannel,
    widthMHz: widthMHz,
  );
  return all.isEmpty ? null : all.first;
}

// ─── Regulatory + classification metadata (caveat layer, NOT physics) ───────

/// The UNII sub-band a 5 or 6 GHz 20 MHz primary sits in, or `null` (2.4 GHz
/// has no UNII sub-bands). channel-plan.md sec 3.1 / 4.1, confidence High.
String? uniiSubBand(WifiBand band, int channel) {
  if (band == WifiBand.band5) {
    if (channel >= 36 && channel <= 48) return 'UNII-1';
    if (channel >= 52 && channel <= 64) return 'UNII-2A';
    if (channel >= 100 && channel <= 144) return 'UNII-2C';
    if (channel >= 149 && channel <= 165) return 'UNII-3';
    if (channel >= 169 && channel <= 177) return 'UNII-4';
    return null;
  }
  if (band == WifiBand.band6) {
    final int? freq = channelToFrequency(band, channel);
    if (freq == null) return null;
    if (freq < 6425) return 'UNII-5';
    if (freq < 6525) return 'UNII-6';
    if (freq < 6875) return 'UNII-7';
    return 'UNII-8';
  }
  return null;
}

/// Short regulatory/classification flags for a 20 MHz primary (DFS, PSC,
/// UNII-4, or the two special-case channels). Empty when none apply.
List<String> channelFlags(WifiBand band, int channel) {
  final List<String> flags = <String>[];
  if (band == WifiBand.band24 && channel == 14) {
    flags.add('Special (2484 MHz)');
    flags.add('Japan, DSSS/802.11b only');
  }
  if (band == WifiBand.band5) {
    if (k5Dfs.contains(channel)) flags.add('DFS');
    if (k5Unii4.contains(channel)) flags.add('UNII-4');
  }
  if (band == WifiBand.band6) {
    if (channel == 2) flags.add('Special (5935 MHz, reserved/guard)');
    if (k6Psc.contains(channel)) flags.add('PSC');
  }
  return flags;
}

/// A regulatory caveat string when availability is region-dependent for this
/// primary, or `null` when it is broadly available. Never changes the computed
/// frequency — it is a note only.
String? regulatoryCaveat(WifiBand band, int channel) {
  if (band == WifiBand.band24) {
    if (channel == 14) {
      return 'Channel 14 is Japan-only and DSSS/802.11b only (no OFDM).';
    }
    if (channel >= 12) {
      return 'Channels 12-13 are not usable in the US (FCC allows 1-11).';
    }
    return null;
  }
  if (band == WifiBand.band5) {
    if (k5Unii4.contains(channel)) {
      return 'UNII-4 (169/173/177) is US-led and not available in many regions.';
    }
    if (k5Dfs.contains(channel)) {
      return 'DFS channel: radar detection required; availability varies by country.';
    }
    return null;
  }
  // 6 GHz: adoption varies by country everywhere.
  if (channel == 2) {
    return 'Channel 2 is a reserved/guard channel, available only where a '
        'regulator permits. 6 GHz adoption also varies by country.';
  }
  return '6 GHz availability varies by regulatory domain (e.g. US opens '
      '5925-7125 MHz; the EU opened only 5945-6425 MHz; some regions not at all).';
}

/// The universal note shown on the tool: channel<->frequency is physics;
/// availability is regulatory.
const String kChannelFrequencyNote =
    'Channel and frequency are universal physics, identical worldwide. Channel '
    'AVAILABILITY (US 1-11 vs world 1-13, DFS, UNII-4, 6 GHz adoption, channels '
    '2 and 14) is regulatory and varies by country. This tool shows the physics.';

/// MikroTik framing shown under a computed center frequency. Both RouterOS
/// wireless stacks (legacy `/interface wireless` and the v7 `/interface/wifi`)
/// configure the operating channel by an explicit center frequency in MHz, not
/// by an 802.11 channel number, so this value is what the operator enters
/// directly. (Pax research, mikrotik-frequency-notes.md, 2026-06-27. In the
/// Wi-Fi role the device is an Access Point, never a Router.)
const String kChannelFrequencyMikroTikNote =
    'On MikroTik, this is the center frequency you enter directly. RouterOS sets '
    'the channel by frequency in MHz, not by channel number.';

/// MikroTik framing for the off-grid frequency->channel reject: there is no
/// standard 802.11 channel at this frequency, but MikroTik can still run the
/// center frequency directly. This does NOT snap to or fabricate a channel —
/// the honest reject stands; this is context only.
const String kChannelFrequencyMikroTikOffGridNote =
    'No standard 802.11 channel sits here, but MikroTik can still run this center '
    'frequency: RouterOS accepts non-standard and narrow 5/10 MHz channels set '
    'directly in MHz.';
