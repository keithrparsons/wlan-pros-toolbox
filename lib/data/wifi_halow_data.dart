// Wi-Fi HaLow (IEEE 802.11ah) reference data — compile-time const, source of
// truth for the data-driven Wi-Fi HaLow screen (Tier-1, 2026-06-12).
//
// Sub-1-GHz (S1G) Wi-Fi for IoT. The single most important UX requirement on
// this page: FREQUENCY and CHANNEL WIDTH are region-dependent and MUST be
// presented that way (a device certified for the US cannot legally operate in
// Europe). That caveat is carried as a prominent warning banner on the screen.
//
// Primary source for headline figures and the MCS table: Wi-Fi Alliance,
// "Wi-Fi CERTIFIED HaLow Technology Overview" (Nov 2021), cross-checked against
// the IEEE 802.11ah Wikipedia article and Electronics-Notes. The headline single-
// stream maximum is 86.7 Mbps (MCS 9, 256-QAM, 16 MHz, SGI) -- NOT the contested
// 433.3 Mbps 4-stream Wikipedia figure, which is carried only as a low-confidence
// footnote. ASCII +/- and hyphen-minus; no em dash.

/// One "what it is" attribute (label / value pair).
class HalowFact {
  const HalowFact(this.label, this.value);
  final String label;
  final String value;
}

/// The "what it is" summary table.
const List<HalowFact> kHalowWhatItIs = <HalowFact>[
  HalowFact('Standard', 'IEEE 802.11ah'),
  HalowFact('Brand', 'Wi-Fi HaLow (Wi-Fi Alliance)'),
  HalowFact('Designation', 'S1G (Sub-1-GHz)'),
  HalowFact('Ratified', '2017 (802.11ah-2016, published May 2017)'),
  HalowFact('Purpose', 'Long-range, low-power, high-density IoT'),
  HalowFact('Native IP', 'Yes -- full TCP/IP, no translation gateway'),
  HalowFact('Security', 'WPA3; Enhanced Open (OWE)'),
];

/// The one-line "what it is" summary carried on-screen.
const String kHalowOneLiner =
    'Wi-Fi HaLow is Wi-Fi moved down into the sub-1-GHz ISM bands to trade raw '
    'speed for about 1 km range, multi-year battery life, and thousands of '
    'devices per access point, while keeping native IP and WPA3.';

/// The "not 2.4/5/6 GHz" callout: the most common misconception, surfaced with
/// a warning tone.
const String kHalowNotMainstreamBands =
    'Wi-Fi HaLow does NOT use 2.4, 5, or 6 GHz. Lower frequencies travel '
    'farther for the same power, which is the whole reason it exists.';

/// The region-lock caveat banner: the load-bearing warning on the page.
const String kHalowRegionLock =
    'Frequency and channel width are set by each region regulator, so the same '
    'silicon ships with region-specific firmware and certification. A device '
    'certified for one region cannot legally run in another. Always confirm '
    'against the local regulator before relying on a band or channel width.';

/// One region band row (frequency varies by regulator).
class HalowBand {
  const HalowBand({
    required this.region,
    required this.band,
    required this.confidence,
  });

  /// Region / regulator, e.g. `United States`.
  final String region;

  /// Band in MHz, e.g. `902-928`.
  final String band;

  /// Source confidence: `High` (in the WFA primary source) or `Medium`
  /// (secondary technical sources only; not a regulatory citation).
  final String confidence;
}

/// Bands by region. US / EU / AU-NZ are High (in the WFA source); the rest are
/// Medium (secondary sources that agree but are not the WFA doc).
const List<HalowBand> kHalowBands = <HalowBand>[
  HalowBand(region: 'United States', band: '902-928 MHz', confidence: 'High'),
  HalowBand(
    region: 'Europe (ETSI)',
    band: '863-868 MHz (narrow, duty-cycle limited)',
    confidence: 'High',
  ),
  HalowBand(
    region: 'Australia / NZ',
    band: '915-928 MHz',
    confidence: 'High',
  ),
  HalowBand(region: 'Japan', band: '916.5-927.5 MHz', confidence: 'Medium'),
  HalowBand(region: 'Korea', band: '917.5-923.5 MHz', confidence: 'Medium'),
  HalowBand(region: 'China', band: '755-787 MHz', confidence: 'Medium'),
  HalowBand(
    region: 'Singapore',
    band: '866-869 & 920-925 MHz',
    confidence: 'Medium',
  ),
];

/// Footnote under the bands table.
const String kHalowBandsNote =
    'The US 902-928 MHz band is the widest and most permissive (full 1-16 MHz '
    'channels). Europe restricts to the narrow 1/2 MHz channels. The Wi-Fi '
    'Alliance is advocating for globally harmonized access at 915-925 MHz.';

/// One channel width row.
class HalowChannel {
  const HalowChannel({
    required this.width,
    required this.use,
    required this.regions,
  });

  /// Channel width, e.g. `1 MHz`.
  final String width;

  /// Typical use.
  final String use;

  /// Region availability.
  final String regions;
}

/// Channel widths (1-16 MHz). The 1 MHz channel is the universal floor; 16 MHz
/// is effectively a US-band capability.
const List<HalowChannel> kHalowChannels = <HalowChannel>[
  HalowChannel(
    width: '1 MHz',
    use: 'Longest range, lowest rate (sensors)',
    regions: 'All regions (the universal mode)',
  ),
  HalowChannel(
    width: '2 MHz',
    use: 'Long range, low rate',
    regions: 'Most regions',
  ),
  HalowChannel(
    width: '4 MHz',
    use: 'Mid-range',
    regions: 'US, AU/NZ (not EU)',
  ),
  HalowChannel(
    width: '8 MHz',
    use: 'Mid-range, higher rate (video, robotics)',
    regions: 'US, AU/NZ (not EU)',
  ),
  HalowChannel(
    width: '16 MHz',
    use: 'Highest rate, shortest range',
    regions: 'US (widest); not in narrow-band regions like EU',
  ),
];

/// Footnote under the channel-width table.
const String kHalowChannelsNote =
    'Even the widest HaLow channel (16 MHz) is narrower than the minimum 2.4 '
    'GHz Wi-Fi channel (20 MHz). Narrow channels concentrate energy, which is '
    'how HaLow reaches farther.';

/// One single-stream MCS row from the WFA overview. Rates in Mbps; `N/A` where
/// the spec defines no rate for that MCS/width pair (printed verbatim).
class HalowMcs {
  const HalowMcs({
    required this.mcs,
    required this.modulation,
    required this.w1,
    required this.w2,
    required this.w4,
    required this.w8,
    required this.w16,
  });

  /// MCS index 0-10.
  final int mcs;

  /// Modulation, e.g. `256-QAM`.
  final String modulation;

  /// 1 MHz rate (LGI / SGI), e.g. `0.30 / 0.33`.
  final String w1;

  /// 2 MHz rate (LGI / SGI).
  final String w2;

  /// 4 MHz rate (LGI / SGI).
  final String w4;

  /// 8 MHz rate (LGI / SGI).
  final String w8;

  /// 16 MHz rate (LGI / SGI). MCS 9 carries the headline 86.7 Mbps (SGI).
  final String w16;
}

/// Single-stream MCS data-rate table (Mbps, LGI / SGI), from the WFA overview.
/// The headline single-stream maximum lives at MCS 9, 16 MHz, SGI: 86.7 Mbps.
const List<HalowMcs> kHalowMcs = <HalowMcs>[
  HalowMcs(mcs: 0, modulation: 'BPSK', w1: '0.30 / 0.33', w2: '0.65 / 0.72', w4: '1.4 / 1.5', w8: '2.9 / 3.3', w16: '5.9 / 6.5'),
  HalowMcs(mcs: 1, modulation: 'QPSK', w1: '0.60 / 0.67', w2: '1.3 / 1.4', w4: '2.7 / 3.0', w8: '5.9 / 6.5', w16: '11.7 / 13.0'),
  HalowMcs(mcs: 2, modulation: 'QPSK', w1: '0.90 / 1.00', w2: '2.0 / 2.2', w4: '4.1 / 4.5', w8: '8.8 / 9.8', w16: '17.6 / 19.5'),
  HalowMcs(mcs: 3, modulation: '16-QAM', w1: '1.2 / 1.3', w2: '2.6 / 2.9', w4: '5.4 / 6.0', w8: '17.6 / 19.5', w16: '35.1 / 39.0'),
  HalowMcs(mcs: 4, modulation: '16-QAM', w1: '1.8 / 2.0', w2: '3.9 / 4.3', w4: '8.1 / 9.0', w8: '17.6 / 19.5', w16: '35.1 / 39.0'),
  HalowMcs(mcs: 5, modulation: '64-QAM', w1: '2.4 / 2.7', w2: '5.2 / 5.8', w4: '10.8 / 12.0', w8: '22.3 / 23.6', w16: '48.6 / 52.0'),
  HalowMcs(mcs: 6, modulation: '64-QAM', w1: '2.7 / 3.0', w2: '5.9 / 6.5', w4: '12.2 / 13.5', w8: '26.3 / 29.3', w16: '52.7 / 58.5'),
  HalowMcs(mcs: 7, modulation: '64-QAM', w1: '3.0 / 3.3', w2: '6.5 / 7.2', w4: '13.5 / 15.0', w8: '29.3 / 32.5', w16: '58.5 / 65.0'),
  HalowMcs(mcs: 8, modulation: '256-QAM', w1: '3.6 / 4.0', w2: '7.8 / 8.7', w4: '16.2 / 18.0', w8: '35.0 / 39.0', w16: '70.2 / 78.0'),
  HalowMcs(mcs: 9, modulation: '256-QAM', w1: '4.0 / 4.4', w2: 'N/A', w4: '18.0 / 20.0', w8: '43.3 / 43.3', w16: '78.0 / 86.7'),
  HalowMcs(mcs: 10, modulation: 'BPSK (2x rep)', w1: '0.15 / 0.17', w2: 'N/A', w4: 'N/A', w8: 'N/A', w16: 'N/A'),
];

/// One headline / summary figure (the lime-accented numbers).
class HalowHeadline {
  const HalowHeadline({
    required this.label,
    required this.value,
    required this.note,
  });
  final String label;
  final String value;
  final String note;
}

/// The headline numbers (range, rate, capacity, power). These carry the single
/// lime accent per row (GL-003 §8.15 case-3).
const List<HalowHeadline> kHalowHeadlines = <HalowHeadline>[
  HalowHeadline(
    label: 'Range',
    value: 'about 1 km',
    note: 'vs tens of meters indoors for 2.4/5 GHz Wi-Fi; about 20 dB link-'
        'budget advantage, roughly 10x the range of 2.4 GHz Wi-Fi.',
  ),
  HalowHeadline(
    label: 'Max data rate (single stream)',
    value: '86.7 Mbps',
    note: 'MCS 9, 256-QAM, 16 MHz, short guard interval. Far edge drops to '
        '150 kbps. Future 4-stream MIMO reaches the low hundreds of Mbps.',
  ),
  HalowHeadline(
    label: 'Capacity',
    value: '8,191 devices per AP',
    note: 'A 13-bit Association ID (2^13 - 1) plus a hierarchical TIM.',
  ),
  HalowHeadline(
    label: 'Battery life',
    value: 'multi-year',
    note: 'Target Wake Time schedules wake windows; comparable to BLE and '
        'Zigbee. Exact years depend on duty cycle and battery.',
  ),
];

/// The data-rate honesty note: why 86.7 Mbps single-stream is the defensible
/// headline, not Wikipedia's contested 433.3 Mbps.
const String kHalowRateHonesty =
    'The defensible headline is 86.7 Mbps single stream, in the Wi-Fi Alliance '
    'source. Wikipedia cites 433.3 Mbps for a 4-spatial-stream maximum, but a '
    '4x scaling of the WFA figure gives about 347 Mbps, and first-generation '
    'HaLow silicon is single-stream. Read 86.7 Mbps as the number a field tech '
    'will see ceilinged.';

/// One power-efficiency feature.
const List<HalowFact> kHalowPower = <HalowFact>[
  HalowFact(
    'Target Wake Time (TWT)',
    'AP and station negotiate scheduled wake windows; the radio sleeps between',
  ),
  HalowFact(
    'Restricted Access Window (RAW)',
    'AP grants the medium to subsets of stations on a schedule; cuts contention',
  ),
  HalowFact(
    'Extended Max Idle',
    'A station may sleep more than 5 minutes without being disassociated',
  ),
  HalowFact(
    'Non-TIM mode',
    'A station need not wake to monitor every beacon',
  ),
  HalowFact(
    'Short MAC headers',
    'Packet overhead drops about 40% to 32%',
  ),
];

/// One PHY/MAC attribute.
const List<HalowFact> kHalowPhy = <HalowFact>[
  HalowFact('Modulation', 'OFDM (BPSK, QPSK, 16/64/256-QAM)'),
  HalowFact('Derivation', '802.11ac PHY down-clocked 10x (1/10 clock rate)'),
  HalowFact('FEC', 'Strong forward error correction'),
  HalowFact('Subcarriers', '26+ per channel'),
  HalowFact('Spatial streams', 'Up to 4 (4x4 MIMO); gen-1 silicon single-stream'),
  HalowFact(
    'MAC efficiency',
    'TWT, RAW, hierarchical TIM, short beacons, NDP frames, BSS coloring',
  ),
];

/// The "10x down-clock" mental model note.
const String kHalowPhyNote =
    'The clean mental model: the 802.11ac PHY clocked at one tenth. Same OFDM '
    'machinery, ten times slower clock, so symbols are 10x longer (more '
    'resilient over distance and multipath) and rates are about a tenth of 802.11ac.';

/// Use cases.
const List<String> kHalowUseCases = <String>[
  'Industrial IoT sensors and actuators',
  'Agriculture (soil, livestock, irrigation over acreage)',
  'Smart city and smart metering (utility AMI)',
  'Building and home automation (replacing Zigbee/Z-Wave meshes)',
  'Security cameras (HaLow carries video where LoRa/Zigbee cannot)',
  'Access control, door/window sensors',
  'Asset tracking across warehouses and campuses',
];

/// One row of the "vs alternatives" comparison (from the WFA comparison table).
class HalowVersus {
  const HalowVersus({
    required this.tech,
    required this.band,
    required this.rate,
    required this.range,
    required this.ipNative,
    this.isHalow = false,
  });

  final String tech;
  final String band;
  final String rate;
  final String range;
  final String ipNative;

  /// `true` for the HaLow row (given the lime accent).
  final bool isHalow;
}

/// HaLow vs other IoT radios. Figures from the Wi-Fi Alliance comparison table
/// (internally consistent, one methodology; the source is the HaLow vendor body).
const List<HalowVersus> kHalowVersus = <HalowVersus>[
  HalowVersus(tech: 'Wi-Fi HaLow', band: 'Sub-1 GHz', rate: '150 kbps - 86.7 Mbps', range: '> 1 km', ipNative: 'Yes', isHalow: true),
  HalowVersus(tech: 'Bluetooth LE', band: '2.4 GHz', rate: '125 kbps - 2 Mbps', range: '< 100 m', ipNative: 'No'),
  HalowVersus(tech: 'Zigbee', band: '2.4 / sub-1 GHz', rate: '250 kbps', range: '< 20 m', ipNative: 'No'),
  HalowVersus(tech: 'Z-Wave', band: 'Sub-1 GHz', rate: '9.6 - 100 kbps', range: '< 30 m', ipNative: 'No'),
  HalowVersus(tech: 'LoRaWAN', band: 'Sub-1 GHz', rate: '0.3 - 27 kbps', range: '< 10 km', ipNative: 'No'),
  HalowVersus(tech: 'Sigfox', band: 'Sub-1 GHz', rate: '100 / 600 bps', range: '< 40 km', ipNative: 'No'),
  HalowVersus(tech: 'NB-IoT', band: 'Licensed', rate: '20 - 127 kbps', range: '< 10 km', ipNative: 'No'),
];

/// The fair "where it sits" read (not the vendor framing).
const String kHalowVersusVerdict =
    'HaLow sits in the middle of the map: more range and device count than '
    'BLE, Zigbee, and Z-Wave, and more data rate plus native IP than LoRaWAN, '
    'Sigfox, and NB-IoT. It does not match LoRa/Sigfox/NB-IoT for multi-'
    'kilometer range, and unlike carrier NB-IoT it needs its own AP '
    'infrastructure. Its strongest case is replacing short-range mesh radios '
    'with longer reach and direct IP, and carrying video.';

/// One maturity item.
const List<HalowFact> kHalowMaturity = <HalowFact>[
  HalowFact('Certification', 'Live (Wi-Fi CERTIFIED HaLow program active)'),
  HalowFact('Leading silicon', 'Morse Micro (MM6108, MM8108 SoCs)'),
  HalowFact(
    'Shipping products',
    'HaLowLink 1 (\$99, Feb 2025); HaLowLink 2 (\$129, CES 2026)',
  ),
  HalowFact(
    'Adoption stage',
    'Early-mainstream; NOT yet mass-deployed like Zigbee/BLE',
  ),
];

/// The maturity honesty note.
const String kHalowMaturityNote =
    'HaLow is real, certified, and shipping with a clear silicon leader and '
    'sub-\$130 developer gateways, but it is at the early-adoption stage in '
    '2026. It has not displaced Zigbee or Z-Wave yet; that is a roadmap claim, '
    'not a 2026 fact.';
