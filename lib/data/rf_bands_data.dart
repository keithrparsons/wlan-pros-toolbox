// RF Bands reference data — compile-time const, source of truth for the
// data-driven RF Bands screen (Tier-1, 2026-06-12).
//
// A FREQUENCY reference (not a channel plan, not a security/attack chart): where
// the common wireless technologies live in the spectrum, organized low -> high
// frequency, so a Wi-Fi pro can see the NEIGHBORS of the bands they design in.
//
// The rows are grouped into five spectrum neighborhoods, low -> high. Wi-Fi rows
// are flagged (isWiFi) so the screen can give them the single lime accent
// (GL-003 §8.15 case-3) — the home turf the reader cares about. Region-variance
// rows (where "what operates where" genuinely changes by regulator) are flagged
// separately and surfaced in their own warning-toned list.
//
// Source: every load-bearing figure cross-verified against >=2 independent
// sources (see DATA.md provenance table). Figures are nominal band edges /
// center frequencies, not channel plans. ASCII +/- and hyphen-minus in prose; no
// em dash.

/// One frequency row: where a technology lives and what it is used for.
class RfBandRow {
  const RfBandRow({
    required this.band,
    required this.tech,
    required this.use,
    required this.note,
    this.isWiFi = false,
  });

  /// Band edges or center frequency, e.g. `902-928 MHz (US)` or `1575.42 MHz`.
  final String band;

  /// Technology that occupies the band, e.g. `Wi-Fi HaLow (802.11ah)`.
  final String tech;

  /// Typical use of the technology in plain words.
  final String use;

  /// One-line clarifying note (region split, range, caveat).
  final String note;

  /// `true` for Wi-Fi rows — the reader's home turf, given the single lime
  /// accent so the eye finds Wi-Fi inside each crowded neighborhood.
  final bool isWiFi;
}

/// One spectrum neighborhood: a titled group of frequency rows plus a one-line
/// "why these are clustered" takeaway.
class RfBandGroup {
  const RfBandGroup({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.takeaway,
  });

  /// Section title, e.g. `Sub-1-GHz / ISM`.
  final String title;

  /// One-line framing under the title.
  final String subtitle;

  /// The frequency rows in this neighborhood, low -> high.
  final List<RfBandRow> rows;

  /// The "why this neighborhood matters to a Wi-Fi pro" takeaway.
  final String takeaway;
}

/// The five spectrum neighborhoods, low -> high frequency.
const List<RfBandGroup> kRfBandGroups = <RfBandGroup>[
  RfBandGroup(
    title: 'Sub-1-GHz / ISM',
    subtitle: 'The long-range, low-data-rate world.',
    takeaway:
        'Sub-GHz buys range and wall penetration at the cost of data rate. '
        'LoRa, Z-Wave, Zigbee sub-GHz, HaLow, and UHF RFID all crowd the 900 '
        'MHz neighborhood (US) or 868 MHz (EU): the radios riding under Wi-Fi.',
    rows: <RfBandRow>[
      RfBandRow(
        band: '125-134 kHz (LF)',
        tech: 'RFID (LF)',
        use: 'Animal ID, access fobs, immobilizers',
        note: 'Globally license-free; about 10 cm range',
      ),
      RfBandRow(
        band: '13.56 MHz (HF)',
        tech: 'RFID (HF) / NFC',
        use: 'Smart cards, tap-to-pay, transit, NFC',
        note: 'ITU ISM 13.553-13.567 MHz; NFC = ISO/IEC 14443 here',
      ),
      RfBandRow(
        band: '433.05-434.79 MHz',
        tech: 'ISM / LoRa (EU433)',
        use: 'Remotes, sensors, some LoRa',
        note: 'ITU Region 1 ISM; common globally for cheap remotes',
      ),
      RfBandRow(
        band: '863-868 MHz (EU)',
        tech: 'LoRaWAN EU868, Zigbee, Wi-Fi HaLow',
        use: 'EU sub-GHz IoT',
        note: 'EU short-range-device band; LoRa EU868 about 863-870 MHz',
      ),
      RfBandRow(
        band: '868.42 MHz (EU)',
        tech: 'Z-Wave (EU)',
        use: 'EU home automation',
        note: 'Region-specific Z-Wave center; CEPT countries',
      ),
      RfBandRow(
        band: '902-928 MHz (US)',
        tech: 'LoRaWAN US915, Zigbee, Z-Wave, Wi-Fi HaLow, RFID',
        use: 'US sub-GHz IoT, RFID, HaLow',
        note: 'The big US sub-GHz ISM band (26 MHz); many techs share it',
      ),
      RfBandRow(
        band: '908.42 MHz (US)',
        tech: 'Z-Wave (US)',
        use: 'US home automation',
        note: 'Region-specific Z-Wave center inside the 902-928 band',
      ),
      RfBandRow(
        band: '860-960 MHz',
        tech: 'RFID (UHF)',
        use: 'Inventory, supply chain, asset tags',
        note: 'No single global allocation: EU about 865-868, US 902-928',
      ),
    ],
  ),
  RfBandGroup(
    title: 'GPS / GNSS',
    subtitle: 'Mid-L-band, between sub-GHz and cellular mid-band.',
    takeaway:
        'GLONASS, Galileo, BeiDou, and NavIC overlap this L-band (about '
        '1.1-1.6 GHz) with their own offsets. L1 (about 1.575 GHz) is the one a '
        'Wi-Fi pro should know: the band GPS jammers and bad cabling disturb.',
    rows: <RfBandRow>[
      RfBandRow(
        band: '1575.42 MHz',
        tech: 'GPS L1',
        use: 'Civilian positioning (the one everyone uses)',
        note: 'Primary civil GPS signal; also Galileo E1',
      ),
      RfBandRow(
        band: '1227.60 MHz',
        tech: 'GPS L2',
        use: 'Dual-frequency / survey, military',
        note: 'L2C civil plus military',
      ),
      RfBandRow(
        band: '1176.45 MHz',
        tech: 'GPS L5',
        use: 'High-precision, aviation safety-of-life',
        note: 'Newest civil signal; shared with Galileo E5a',
      ),
    ],
  ),
  RfBandGroup(
    title: 'Cellular',
    subtitle: 'Sub-GHz up through mmWave, shown as ranges, not a band list.',
    takeaway:
        '5G FR1 runs right up to about 7 GHz: its C-band mid-band is the '
        'immediate downstairs neighbor of Wi-Fi 5/6 GHz, and FR2 mmWave shares '
        'the 24 GHz neighborhood with the 24 GHz ISM band.',
    rows: <RfBandRow>[
      RfBandRow(
        band: 'about 450 MHz - 5.9 GHz',
        tech: '4G LTE (all bands)',
        use: 'Mainstream mobile broadband',
        note: 'Low-band coverage, mid-band capacity, up to U-NII-4 about 5.9 GHz',
      ),
      RfBandRow(
        band: '410 MHz - 7.125 GHz',
        tech: '5G NR FR1 (sub-7 GHz)',
        use: '5G low plus mid band, the workhorse',
        note: 'C-band (about 3.3-4.2 GHz) sits just below Wi-Fi',
      ),
      RfBandRow(
        band: '24.25 - 52.6 GHz',
        tech: '5G NR FR2 (mmWave)',
        use: '5G high-capacity, dense urban',
        note: 'Huge bandwidth, tiny range; extended to 71 GHz in 3GPP Rel-17',
      ),
    ],
  ),
  RfBandGroup(
    title: '2.4 GHz ISM',
    subtitle: 'The crowded one: 2.400-2.4835 GHz, all shared.',
    takeaway:
        'In 2.4 GHz, Wi-Fi, Bluetooth, Zigbee/Thread, and ovens all sit on top '
        'of each other in 83.5 MHz. The single most contested neighborhood in '
        'the chart.',
    rows: <RfBandRow>[
      RfBandRow(
        band: '2.401-2.495 GHz',
        tech: 'Wi-Fi (2.4 GHz)',
        use: 'Legacy plus IoT Wi-Fi',
        note: '14 channels; only 1/6/11 non-overlapping in North America',
        isWiFi: true,
      ),
      RfBandRow(
        band: '2.402-2.480 GHz',
        tech: 'Bluetooth / BLE',
        use: 'Audio, peripherals, beacons',
        note: 'Classic 79x1 MHz; BLE 40x2 MHz; adaptive hopping',
      ),
      RfBandRow(
        band: '2.4-2.4835 GHz',
        tech: 'Zigbee / Thread / 802.15.4',
        use: 'Smart-home mesh, sensors',
        note: '16 channels, 5 MHz spaced; Thread shares the 802.15.4 PHY',
      ),
      RfBandRow(
        band: '2.4-2.5 GHz',
        tech: 'Microwave ovens, cordless, video',
        use: 'Non-comm interference',
        note: 'Ovens leak near 2.45 GHz: a real Wi-Fi noise source',
      ),
    ],
  ),
  RfBandGroup(
    title: 'Wi-Fi across all its bands',
    subtitle: 'The home turf.',
    takeaway:
        'The 5 GHz band is a patchwork of U-NII sub-bands with different '
        'regional rules (DFS, indoor-only, power limits); the per-channel plan '
        'is its own reference.',
    rows: <RfBandRow>[
      RfBandRow(
        band: '2.401-2.495 GHz',
        tech: 'Wi-Fi 2.4 GHz',
        use: 'Range / IoT',
        note: 'Crowded; only 3 clean 20 MHz channels in NA',
        isWiFi: true,
      ),
      RfBandRow(
        band: '5.150-5.925 GHz',
        tech: 'Wi-Fi 5 GHz (U-NII-1 ... U-NII-4)',
        use: 'Mainstream Wi-Fi',
        note: 'Most channels; DFS on U-NII-2; availability varies by region',
        isWiFi: true,
      ),
      RfBandRow(
        band: '5.925-7.125 GHz (US)',
        tech: 'Wi-Fi 6E / 7 (6 GHz)',
        use: 'Clean wide channels',
        note: 'US/FCC: full 1.2 GHz; EU opened only 5.945-6.425 GHz',
        isWiFi: true,
      ),
      RfBandRow(
        band: '57-71 GHz',
        tech: 'WiGig (802.11ad / ay, 60 GHz)',
        use: 'Short-range multi-Gb, VR, docking',
        note: 'V-band mmWave; meters of range; 4-6 channels by region',
        isWiFi: true,
      ),
    ],
  ),
];

/// One region-variance flag: a band whose "what operates where" genuinely
/// changes by regulator, surfaced in its own warning-toned list.
class RfRegionFlag {
  const RfRegionFlag(this.topic, this.detail);

  /// Short topic, e.g. `6 GHz Wi-Fi`.
  final String topic;

  /// The US-vs-EU (and others) split in one line.
  final String detail;
}

/// The region-variance flags (US FCC vs EU ETSI and others). The graphic and
/// screen carry an explicit warning treatment on each.
const List<RfRegionFlag> kRfRegionFlags = <RfRegionFlag>[
  RfRegionFlag(
    '6 GHz Wi-Fi',
    'US = 5.925-7.125 GHz (full 1.2 GHz). EU = 5.945-6.425 GHz (lower 480 '
        'MHz only). Some regions have not opened 6 GHz at all. Highest-stakes '
        'variance for a Wi-Fi pro.',
  ),
  RfRegionFlag(
    'Sub-GHz ISM',
    'US = 902-928 MHz (ITU Region 2). EU = 863-868 MHz. This shifts LoRa, '
        'Z-Wave, Zigbee sub-GHz, HaLow, and UHF RFID to different homes by '
        'region.',
  ),
  RfRegionFlag(
    'Z-Wave center',
    'US 908.42 MHz vs EU 868.42 MHz, plus AU/NZ, Japan, and others on their '
        'own offsets.',
  ),
  RfRegionFlag(
    'Wi-Fi HaLow (802.11ah)',
    'US 902-928 MHz vs EU 863-868 MHz (narrower).',
  ),
  RfRegionFlag(
    'UHF RFID',
    'EU about 865-868 MHz vs US 902-928 MHz; no single global allocation.',
  ),
  RfRegionFlag(
    '2.4 GHz channel count',
    'Channel 14 is Japan-only; channels 12-13 are restricted in the US. Band '
        'edges are global, channel use is not.',
  ),
  RfRegionFlag(
    '60 GHz WiGig',
    'US opened 57-71 GHz (6 channels); EU classic 57-66 GHz (4 channels), '
        'with 66-71 GHz a later addition.',
  ),
  RfRegionFlag(
    '5 GHz Wi-Fi',
    'U-NII-2/2e DFS rules and U-NII-4 availability differ US vs EU vs '
        'elsewhere.',
  ),
];

/// Framing note carried on-screen under the band groups.
const String kRfBandsNote =
    'All band edges are nominal allocations, not guaranteed-clear channels. '
    'Local power limits, DFS, and licensing further constrain real use. This is '
    'a frequency map, not a channel plan.';
