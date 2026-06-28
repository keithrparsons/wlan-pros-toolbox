// Ham Radio band reference data — the single source of the band-dependent
// amateur-radio reference values used by the four Ham Radio reference screens
// (US Amateur Band Plan, Band Names & Wavelengths, RF Spectrum Designations,
// Part 15 vs Part 97) and one Educational Resources screen (Ham Radio Study
// Resources).
//
// SOURCE OF TRUTH: Deliverables/2026-06-28-ham-radio-toolbox-research/
// build-spec.md (Pax, accuracy-gated). Every numeric/factual value here is
// traceable to FCC Part 97 (eCFR Title 47), the FCC Online Table of Frequency
// Allocations, ARRL, or NCVEC, current as of June 2026. The CORRECTED values
// are used, never an older chart:
//   - General class runs 1500 W PEP on 80/40/15/10 m (the old "200 W" entries
//     were wrong); only 30 m = 200 W PEP, 60 m = 100 W ERP (channels) /
//     9.15 W ERP (segment); 2200 m / 630 m are EIRP-limited.
//   - 60 m = 4 channels + the 5351.5-5366.5 kHz segment @ 9.15 W ERP,
//     effective 13 Feb 2026 (the old 5-channel chart is wrong).
//   - 630 m and 2200 m are IN. 9 cm (3.3-3.5 GHz) is OUT (sunset).
//   - NO baud column: the HF symbol-rate limit was removed (FCC 23-93),
//     replaced by a 2.8 kHz bandwidth limit. The VHF/UHF baud status is
//     unconfirmed [VERIFY], so no baud value is shown anywhere.
//
// GLYPHS: ASCII hyphen-minus for every frequency range (matches the rest of the
// app's reference data, e.g. spectrum_screen.dart "2400 - 2484 MHz"); no em
// dash anywhere (GL-004). Privilege absence reads as a sentence ("No Technician
// privileges"), never a bare dash.
//
// All datasets are plain Dart consts with no Flutter import, so the data-
// integrity tests can assert against them directly without pumping a widget.

// ─────────────────────────────────────────────────────────────────────────
// 1. US Amateur Band Plan
// ─────────────────────────────────────────────────────────────────────────

/// The ITU spectrum region a band sits in, used to group the band-plan screen.
enum HamRegion { hf, vhf, uhf, shf }

extension HamRegionLabel on HamRegion {
  /// Section header for the grouped band-plan list.
  String get label {
    switch (this) {
      case HamRegion.hf:
        return 'HF (and the 2200 m / 630 m LF/MF bands)';
      case HamRegion.vhf:
        return 'VHF';
      case HamRegion.uhf:
        return 'UHF';
      case HamRegion.shf:
        return 'SHF (microwave)';
    }
  }
}

/// One amateur band row in the corrected US band plan.
///
/// Privileges are shown for Technician (T) / General (G) / Amateur Extra (E)
/// only — Novice and Advanced are closed to new applicants and grandfathered,
/// so they are omitted per the spec.
///
/// Two shapes are supported:
///   * Per-class HF bands set [tech] / [general] / [extra]. A null [tech] means
///     a Technician has no privileges on that band.
///   * Bands where every license class shares the same access (VHF/UHF/SHF, and
///     the all-mode LF/MF bands) set [allClasses] instead; [tech]/[general]/
///     [extra] are then ignored at render time.
class HamBand {
  const HamBand({
    required this.band,
    required this.freqRange,
    required this.region,
    required this.power,
    this.modes,
    this.tech,
    this.general,
    this.extra,
    this.allClasses,
  });

  /// Band name = its nominal wavelength, e.g. "20 m" or "70 cm".
  final String band;

  /// Federal frequency allocation, e.g. "14.000-14.350 MHz".
  final String freqRange;

  final HamRegion region;

  /// Maximum power per §97.313, e.g. "1500 W PEP (Technician: 200 W)".
  final String power;

  /// Key mode segments / band notes (CW-only sub-band, repeater split,
  /// overlap with Wi-Fi). Optional.
  final String? modes;

  /// Technician privileges; null when a Technician has none on this band.
  final String? tech;

  /// General privileges (per-class shape).
  final String? general;

  /// Amateur Extra privileges (per-class shape). "Same as General" where the
  /// allocation is identical to General.
  final String? extra;

  /// When set, every license class (Technician and up) shares this single
  /// privilege description; the per-class fields are not rendered.
  final String? allClasses;

  /// True when the band uses the shared all-classes shape.
  bool get isAllClasses => allClasses != null;
}

/// The corrected US amateur band plan, HF through SHF. Power column rebuilt from
/// §97.313 (table B5); 60 m updated to the 4-channel + 9.15 W ERP segment;
/// 9 cm omitted (sunset) and footnoted on the screen.
const List<HamBand> kHamBandPlan = <HamBand>[
  // ── HF + the two LF/MF bands ──
  HamBand(
    band: '2200 m',
    freqRange: '135.7-137.8 kHz',
    region: HamRegion.hf,
    allClasses: 'All modes (CW, RTTY/data, phone, image)',
    power: '1 W EIRP (prior UTC notification required)',
  ),
  HamBand(
    band: '630 m',
    freqRange: '472-479 kHz',
    region: HamRegion.hf,
    allClasses: 'All modes (CW, RTTY/data, phone, image)',
    power: '5 W EIRP (1 W EIRP in parts of AK near Russia); prior UTC '
        'notification',
  ),
  HamBand(
    band: '160 m',
    freqRange: '1.800-2.000 MHz',
    region: HamRegion.hf,
    tech: null,
    general: 'CW, RTTY/data, phone, image band-wide',
    extra: 'Same as General',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '80 m',
    freqRange: '3.500-4.000 MHz',
    region: HamRegion.hf,
    tech: 'CW 3.525-3.600 only',
    general: 'CW/data 3.525-3.600; phone/image 3.800-4.000',
    extra: 'CW/data 3.500-3.600; phone/image 3.600-4.000',
    modes: 'The 3.8-4.0 phone portion is the 75 m phone band',
    power: '1500 W PEP (Technician: 200 W)',
  ),
  HamBand(
    band: '60 m',
    freqRange: '5 channels area, ~5.332-5.405 MHz',
    region: HamRegion.hf,
    tech: null,
    general: '4 channels (USB/CW/digital) plus the 5351.5-5366.5 kHz segment '
        '(all modes, 2.8 kHz max)',
    extra: 'Same as General',
    modes: 'Channelized band; see the 60 m channel detail below',
    power: 'Channels 100 W ERP; segment 9.15 W ERP',
  ),
  HamBand(
    band: '40 m',
    freqRange: '7.000-7.300 MHz',
    region: HamRegion.hf,
    tech: 'CW 7.025-7.125 only',
    general: 'CW/data 7.025-7.125; phone/image 7.175-7.300',
    extra: 'CW/data 7.000-7.125; phone/image 7.125-7.300',
    power: '1500 W PEP (Technician: 200 W)',
  ),
  HamBand(
    band: '30 m',
    freqRange: '10.100-10.150 MHz',
    region: HamRegion.hf,
    tech: null,
    general: 'CW and RTTY/data ONLY (no phone, no image)',
    extra: 'Same as General',
    power: '200 W PEP (band cap)',
  ),
  HamBand(
    band: '20 m',
    freqRange: '14.000-14.350 MHz',
    region: HamRegion.hf,
    tech: null,
    general: 'CW/data 14.025-14.150; phone/image 14.225-14.350',
    extra: 'CW/data 14.000-14.150; phone/image 14.150-14.350',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '17 m',
    freqRange: '18.068-18.168 MHz',
    region: HamRegion.hf,
    tech: null,
    general: 'CW/data 18.068-18.110; phone/image 18.110-18.168',
    extra: 'Same as General',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '15 m',
    freqRange: '21.000-21.450 MHz',
    region: HamRegion.hf,
    tech: 'CW 21.025-21.200 only',
    general: 'CW/data 21.025-21.200; phone/image 21.275-21.450',
    extra: 'CW/data 21.000-21.200; phone/image 21.200-21.450',
    power: '1500 W PEP (Technician: 200 W)',
  ),
  HamBand(
    band: '12 m',
    freqRange: '24.890-24.990 MHz',
    region: HamRegion.hf,
    tech: null,
    general: 'CW/data 24.890-24.930; phone/image 24.930-24.990',
    extra: 'Same as General',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '10 m',
    freqRange: '28.000-29.700 MHz',
    region: HamRegion.hf,
    tech: 'CW/RTTY/data 28.000-28.300; phone (SSB) 28.300-28.500',
    general: 'CW/data 28.000-28.300; phone/image 28.300-29.700',
    extra: 'Same as General',
    modes: '29.0-29.7 MHz is commonly FM and repeaters',
    power: '1500 W PEP (Technician: 200 W)',
  ),
  // ── VHF ──
  HamBand(
    band: '6 m',
    freqRange: '50-54 MHz',
    region: HamRegion.vhf,
    allClasses: 'All modes',
    modes: 'CW only 50.0-50.1 MHz; all modes above',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '2 m',
    freqRange: '144-148 MHz',
    region: HamRegion.vhf,
    allClasses: 'All modes',
    modes: 'CW only 144.0-144.1 MHz; all modes above; 600 kHz repeater split',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '1.25 m',
    freqRange: '222-225 MHz (plus 219-220 fixed digital, secondary)',
    region: HamRegion.vhf,
    allClasses: 'All modes',
    modes: '219-220 MHz is point-to-point digital, secondary',
    power: '1500 W PEP',
  ),
  // ── UHF ──
  HamBand(
    band: '70 cm',
    freqRange: '420-450 MHz',
    region: HamRegion.uhf,
    allClasses: 'All modes',
    modes: 'Secondary; Line A restriction near the Canadian border; 435-438 '
        'satellite subband; 5 MHz repeater split',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '33 cm',
    freqRange: '902-928 MHz',
    region: HamRegion.uhf,
    allClasses: 'All modes',
    modes: 'Secondary; shares the 900 MHz ISM band (Part 15) and Part 90',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '23 cm',
    freqRange: '1240-1300 MHz',
    region: HamRegion.uhf,
    allClasses: 'All modes',
    modes: 'Secondary; legacy Novice segment 1270-1295 at 5 W',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '13 cm',
    freqRange: '2300-2310 and 2390-2450 MHz',
    region: HamRegion.uhf,
    allClasses: 'All modes',
    modes: '2310-2390 withdrawn (satellite radio); 2390-2450 overlaps 2.4 GHz '
        'Wi-Fi',
    power: '1500 W PEP',
  ),
  // ── SHF (9 cm / 3.3-3.5 GHz omitted: sunset; footnoted on the screen) ──
  HamBand(
    band: '5 cm',
    freqRange: '5650-5925 MHz',
    region: HamRegion.shf,
    allClasses: 'All modes',
    modes: 'Overlaps 5 GHz U-NII Wi-Fi (see Part 15 vs Part 97)',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '3 cm',
    freqRange: '10.0-10.5 GHz',
    region: HamRegion.shf,
    allClasses: 'All modes',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '1.2 cm',
    freqRange: '24.0-24.25 GHz',
    region: HamRegion.shf,
    allClasses: 'All modes',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '6 mm',
    freqRange: '47.0-47.2 GHz',
    region: HamRegion.shf,
    allClasses: 'All modes',
    power: '1500 W PEP',
  ),
  HamBand(
    band: '4 mm',
    freqRange: '76.0-81.0 GHz',
    region: HamRegion.shf,
    allClasses: 'All modes',
    power: '1500 W PEP',
  ),
];

/// One 60 m channel (or the new segment). The FCC references 60 m by channel
/// CENTER; operators tune USB 1.5 kHz below center (the dial frequency), shown
/// as a secondary annotation per the spec.
class Ham60mChannel {
  const Ham60mChannel({
    required this.label,
    required this.center,
    required this.dial,
    required this.power,
    this.notes,
  });

  /// "Channel 1" ... "Channel 4", or "Segment".
  final String label;

  /// Canonical center frequency, e.g. "5332.0 kHz".
  final String center;

  /// USB dial frequency (1.5 kHz below center), or "n/a" for the segment.
  final String dial;

  final String power;
  final String? notes;
}

/// The current 60 m channel plan: 4 channels at 100 W ERP plus the
/// 5351.5-5366.5 kHz segment at 9.15 W ERP, effective 13 Feb 2026. The dropped
/// 5th channel was dial 5357.0 / center 5358.5.
const List<Ham60mChannel> kHam60mChannels = <Ham60mChannel>[
  Ham60mChannel(
    label: 'Channel 1',
    center: '5332.0 kHz',
    dial: '5330.5 kHz',
    power: '100 W ERP',
  ),
  Ham60mChannel(
    label: 'Channel 2',
    center: '5348.0 kHz',
    dial: '5346.5 kHz',
    power: '100 W ERP',
  ),
  Ham60mChannel(
    label: 'Channel 3',
    center: '5373.0 kHz',
    dial: '5371.5 kHz',
    power: '100 W ERP',
  ),
  Ham60mChannel(
    label: 'Channel 4',
    center: '5405.0 kHz',
    dial: '5403.5 kHz',
    power: '100 W ERP',
  ),
  Ham60mChannel(
    label: 'Segment',
    center: '5351.5-5366.5 kHz (15 kHz wide)',
    dial: 'n/a',
    power: '9.15 W ERP (= 15 W EIRP)',
    notes: 'All modes, 2.8 kHz max. New 13 Feb 2026; absorbs the retired '
        'channel (old center 5358.5 / dial 5357.0).',
  ),
];

/// The single-paragraph power-limit summary, surfaced on the band-plan screen.
const String kHamPowerSummary =
    'General ceiling is 1500 W PEP. Exceptions: 30 m = 200 W PEP; 60 m = '
    '100 W ERP (channels) and 9.15 W ERP (segment); 2200 m = 1 W EIRP; '
    '630 m = 5 W EIRP; a Technician on any HF band = 200 W PEP. Always '
    'subject to the "minimum necessary power" rule (97.313(a)).';

/// The HF data rule that replaced the obsolete baud column.
const String kHamHfDataRule =
    'No symbol-rate (baud) limit on HF. Data emissions are capped at 2.8 kHz '
    'maximum bandwidth, effective 8 Jan 2024 (FCC 23-93).';

/// The 9 cm sunset footnote (rendered conservatively; no claim of residual
/// usability, per the [VERIFY] tag in the spec).
const String kHam9cmSunsetNote =
    '9 cm (3300-3500 MHz) is omitted from this chart: 3450-3500 MHz ceased '
    '14 Apr 2022 and 3300-3450 MHz is a secondary allocation in active sunset. '
    'It is not a band to plan new operation on, and it does not overlap '
    '5 GHz Wi-Fi.';

// ─────────────────────────────────────────────────────────────────────────
// 2. Band Names <-> Wavelength bridge
// ─────────────────────────────────────────────────────────────────────────

/// One row of the band-name (wavelength) to frequency translation. The
/// wavelength is the nominal band name; the range is the actual allocation.
class BandBridgeRow {
  const BandBridgeRow({
    required this.bandName,
    required this.freqRange,
    required this.region,
    this.sunset = false,
  });

  /// The wavelength band name, e.g. "20 m" or "13 cm".
  final String bandName;

  /// The amateur frequency range, e.g. "14.000-14.350 MHz".
  final String freqRange;

  /// Short region tag shown in the third column ("HF", "VHF", "UHF", "SHF",
  /// "LF", "MF", "MF/HF").
  final String region;

  /// True for the 9 cm sunset band (annotated, not a current allocation).
  final bool sunset;
}

/// The band-name to frequency table. Hams name bands by wavelength in
/// meters/cm, not frequency; this is the two-worlds translation a Wi-Fi pro
/// uses to cross over.
const List<BandBridgeRow> kBandBridge = <BandBridgeRow>[
  BandBridgeRow(bandName: '2200 m', freqRange: '135.7-137.8 kHz', region: 'LF'),
  BandBridgeRow(bandName: '630 m', freqRange: '472-479 kHz', region: 'MF'),
  BandBridgeRow(
      bandName: '160 m', freqRange: '1.800-2.000 MHz', region: 'MF/HF'),
  BandBridgeRow(bandName: '80 m', freqRange: '3.500-4.000 MHz', region: 'HF'),
  BandBridgeRow(
      bandName: '60 m',
      freqRange: '~5.332-5.405 MHz (4 ch + segment)',
      region: 'HF'),
  BandBridgeRow(bandName: '40 m', freqRange: '7.000-7.300 MHz', region: 'HF'),
  BandBridgeRow(bandName: '30 m', freqRange: '10.100-10.150 MHz', region: 'HF'),
  BandBridgeRow(bandName: '20 m', freqRange: '14.000-14.350 MHz', region: 'HF'),
  BandBridgeRow(bandName: '17 m', freqRange: '18.068-18.168 MHz', region: 'HF'),
  BandBridgeRow(bandName: '15 m', freqRange: '21.000-21.450 MHz', region: 'HF'),
  BandBridgeRow(bandName: '12 m', freqRange: '24.890-24.990 MHz', region: 'HF'),
  BandBridgeRow(bandName: '10 m', freqRange: '28.000-29.700 MHz', region: 'HF'),
  BandBridgeRow(bandName: '6 m', freqRange: '50-54 MHz', region: 'VHF'),
  BandBridgeRow(bandName: '2 m', freqRange: '144-148 MHz', region: 'VHF'),
  BandBridgeRow(bandName: '1.25 m', freqRange: '222-225 MHz', region: 'VHF'),
  BandBridgeRow(bandName: '70 cm', freqRange: '420-450 MHz', region: 'UHF'),
  BandBridgeRow(bandName: '33 cm', freqRange: '902-928 MHz', region: 'UHF'),
  BandBridgeRow(bandName: '23 cm', freqRange: '1240-1300 MHz', region: 'UHF'),
  BandBridgeRow(
      bandName: '13 cm',
      freqRange: '2300-2310 / 2390-2450 MHz',
      region: 'UHF'),
  BandBridgeRow(
      bandName: '9 cm',
      freqRange: '3300-3500 MHz (sunset / out)',
      region: 'SHF',
      sunset: true),
  BandBridgeRow(bandName: '5 cm', freqRange: '5650-5925 MHz', region: 'SHF'),
  BandBridgeRow(bandName: '3 cm', freqRange: '10.0-10.5 GHz', region: 'SHF'),
];

// ─────────────────────────────────────────────────────────────────────────
// 3. ITU spectrum band designations + the neighbors a Wi-Fi pro should know
// ─────────────────────────────────────────────────────────────────────────

/// One ITU decade band designation (HF / VHF / UHF / SHF) with its propagation
/// character.
class ItuBandDesignation {
  const ItuBandDesignation({
    required this.designation,
    required this.name,
    required this.frequency,
    required this.wavelength,
    required this.propagation,
  });

  /// Short designation, e.g. "HF".
  final String designation;

  /// Full name, e.g. "High Frequency".
  final String name;

  /// Frequency span, e.g. "3-30 MHz".
  final String frequency;

  /// Wavelength span, e.g. "100-10 m".
  final String wavelength;

  /// What the band's propagation implies operationally.
  final String propagation;
}

/// The four ITU decade bands a Wi-Fi pro lives near. Each band is x10 the
/// previous. (MF/LF below and EHF above are noted on the screen, not tabled.)
const List<ItuBandDesignation> kItuBands = <ItuBandDesignation>[
  ItuBandDesignation(
    designation: 'HF',
    name: 'High Frequency',
    frequency: '3-30 MHz',
    wavelength: '100-10 m',
    propagation: 'Sky-wave / ionospheric skip: worldwide DX by bouncing off '
        'the F-layer. Day/night and solar-cycle dependent. The "talk around '
        'the world" bands.',
  ),
  ItuBandDesignation(
    designation: 'VHF',
    name: 'Very High Frequency',
    frequency: '30-300 MHz',
    wavelength: '10-1 m',
    propagation: 'Mostly line-of-sight plus a little beyond the horizon. '
        'Sporadic-E and tropo openings. FM voice, repeaters, 2 m / 6 m.',
  ),
  ItuBandDesignation(
    designation: 'UHF',
    name: 'Ultra High Frequency',
    frequency: '300 MHz-3 GHz',
    wavelength: '1 m-10 cm',
    propagation: 'Line-of-sight with building-penetration trade-offs. '
        'Wi-Fi 2.4 GHz lives here, along with repeaters, 70 cm, and satellites.',
  ),
  ItuBandDesignation(
    designation: 'SHF',
    name: 'Super High Frequency',
    frequency: '3-30 GHz',
    wavelength: '10 cm-1 cm',
    propagation: 'Strict line-of-sight; rain fade begins. Wi-Fi 5/6 GHz lives '
        'here, along with microwave and point-to-point links.',
  ),
];

/// One non-amateur service a Wi-Fi pro will recognize as a band neighbor.
class SpectrumNeighbor {
  const SpectrumNeighbor({
    required this.service,
    required this.allocation,
    required this.mode,
    required this.why,
  });

  final String service;
  final String allocation;
  final String mode;
  final String why;
}

/// The verified neighbors: the VHF aviation airband and military UHF airband
/// Keith cited, plus the ISM/U-NII bands that overlap amateur allocations.
const List<SpectrumNeighbor> kSpectrumNeighbors = <SpectrumNeighbor>[
  SpectrumNeighbor(
    service: 'VHF aviation airband',
    allocation: '108-137 MHz, AM',
    mode: 'Navigation 108-117.975 MHz (VOR/ILS); voice 117.975-136.975 MHz',
    why: 'AM voice and nav. 121.5 MHz is the civil emergency "Guard." '
        '8.33 / 25 kHz channel spacing. Sits just below the 2 m ham band.',
  ),
  SpectrumNeighbor(
    service: 'Military UHF airband',
    allocation: '225-400 MHz, AM',
    mode: 'Tactical air voice (HAVE QUICK / SATURN frequency-hopping)',
    why: '243.0 MHz is the military "Guard." 380-400 MHz shares US military '
        'land-mobile. Brackets the 70 cm ham band (420-450 MHz).',
  ),
  SpectrumNeighbor(
    service: '2.4 GHz ISM (Part 15)',
    allocation: '2400-2483.5 MHz',
    mode: 'Wi-Fi / Bluetooth',
    why: 'Overlaps the amateur 13 cm band (2390-2450 MHz).',
  ),
  SpectrumNeighbor(
    service: '5 GHz U-NII (Part 15)',
    allocation: '5150-5895 MHz',
    mode: 'Wi-Fi',
    why: 'Overlaps the amateur 5 cm band (5650-5925 MHz).',
  ),
  SpectrumNeighbor(
    service: '900 MHz ISM (Part 15)',
    allocation: '902-928 MHz',
    mode: 'IoT / LoRa',
    why: 'Co-channel with the amateur 33 cm band.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────
// 4. Part 15 vs Part 97 over 2.4 / 5 GHz
// ─────────────────────────────────────────────────────────────────────────

/// One amateur allocation that overlaps a Wi-Fi band, mapped to the Wi-Fi grid.
class WifiHamOverlap {
  const WifiHamOverlap({
    required this.wifiBand,
    required this.hamBand,
    required this.overlap,
    required this.channelsInside,
  });

  final String wifiBand;
  final String hamBand;
  final String overlap;
  final String channelsInside;
}

/// The overlapping allocations. 9 cm (3.3-3.5 GHz) does NOT overlap Wi-Fi and
/// is deliberately excluded.
const List<WifiHamOverlap> kWifiHamOverlaps = <WifiHamOverlap>[
  WifiHamOverlap(
    wifiBand: '2.4 GHz ISM (2400-2483.5 MHz)',
    hamBand: '13 cm: 2390-2450 MHz',
    overlap: 'Amateur covers the lower ~60 MHz of the Wi-Fi band.',
    channelsInside: 'Channels 1-6 fully inside; ch 7 partially (center 2442 '
        'OK, upper skirt past 2450).',
  ),
  WifiHamOverlap(
    wifiBand: '5 GHz U-NII (5150-5895 MHz)',
    hamBand: '5 cm: 5650-5925 MHz',
    overlap: 'Amateur covers from mid-U-NII-2C up through U-NII-4.',
    channelsInside: 'Upper U-NII-2C (ch 132/136/140/144), all of U-NII-3 '
        '(149-165), and U-NII-4 (169-177).',
  ),
  WifiHamOverlap(
    wifiBand: '900 MHz ISM (902-928 MHz)',
    hamBand: '33 cm: 902-928 MHz',
    overlap: 'Full co-channel.',
    channelsInside: 'Not a Wi-Fi band in the US.',
  ),
];

/// One row of the Part 15 vs Part 97 rule-delta table.
class RuleDelta {
  const RuleDelta({
    required this.dimension,
    required this.part15,
    required this.part97,
  });

  final String dimension;

  /// The Part 15 (unlicensed Wi-Fi AP) rule.
  final String part15;

  /// The Part 97 (licensed amateur, e.g. an AREDN node) rule.
  final String part97;
}

/// The heart of the Part 15 vs Part 97 comparison.
const List<RuleDelta> kRuleDeltas = <RuleDelta>[
  RuleDelta(
    dimension: 'License',
    part15: 'None',
    part97: 'Required: the control operator must be licensed (Technician or '
        'higher on these bands).',
  ),
  RuleDelta(
    dimension: 'Authority',
    part15: '47 CFR Part 15 (15.247 / 15.407)',
    part97: '47 CFR Part 97',
  ),
  RuleDelta(
    dimension: 'Status',
    part15: 'Secondary; must accept interference and must not cause harmful '
        'interference.',
    part97: 'Secondary on these bands; coordinate; the same "do not interfere" '
        'ethic.',
  ),
  RuleDelta(
    dimension: 'Power (2.4 GHz)',
    part15: '1 W (30 dBm) conducted; 4 W (36 dBm) EIRP at up to 6 dBi. '
        'Point-to-point may use higher-gain antennas, reducing conducted '
        '1 dB per 3 dB over 6 dBi.',
    part97: 'Up to the 1500 W PEP ceiling (real-world far less), plus '
        'amateur-grade gain antennas.',
  ),
  RuleDelta(
    dimension: 'Power (5 GHz, U-NII-3)',
    part15: '1 W conducted, 4 W EIRP; fixed point-to-point may use '
        'higher-gain antennas without power reduction.',
    part97: 'Up to the 1500 W PEP ceiling.',
  ),
  RuleDelta(
    dimension: 'Station ID',
    part15: 'None',
    part97: 'Callsign every 10 minutes and at the end of a contact, including '
        'digital and mesh links.',
  ),
  RuleDelta(
    dimension: 'Encryption',
    part15: 'Allowed (WPA2 / WPA3).',
    part97: 'Prohibited: no codes or ciphers meant to obscure the meaning of a '
        'message. Mesh traffic must be in the clear.',
  ),
  RuleDelta(
    dimension: 'Business use',
    part15: 'Allowed',
    part97: 'Prohibited: no business communications, no broadcasting, no '
        'pecuniary interest.',
  ),
  RuleDelta(
    dimension: 'Content',
    part15: 'Open',
    part97: 'No music, no obscenity, no broadcast.',
  ),
];

/// The AREDN / Broadband-Hamnet real-world example (the "Wi-Fi silicon, ham
/// rules" demonstration).
const String kAredNote =
    'AREDN (Amateur Radio Emergency Data Network) and its predecessor '
    'Broadband-Hamnet run commodity 802.11 a/b/g/n hardware on the overlapping '
    'ham channels under Part 97 instead of Part 15. They trade Part 15\'s '
    'encryption and commercial freedom for Part 97\'s higher power ceiling, at '
    'the cost of mandatory callsign ID and no encryption. The active project '
    'is at aredn.org.';

/// The note keeping 9 cm distinct from the Wi-Fi 5 GHz overlap.
const String kPart97NineCmNote =
    'The 3.3-3.5 GHz amateur band (9 cm) is being sunset and does NOT overlap '
    'Wi-Fi 5 GHz. Do not confuse it with the 5 cm band (5650-5925 MHz), which '
    'does.';

// ─────────────────────────────────────────────────────────────────────────
// 5. Ham Radio study resources
// ─────────────────────────────────────────────────────────────────────────

/// One vetted study or reference resource for the amateur-radio exams.
class HamStudyResource {
  const HamStudyResource({
    required this.title,
    required this.forWhat,
    required this.classes,
    required this.authority,
    required this.credit,
    required this.vetNote,
    this.url,
  });

  final String title;

  /// What it is for.
  final String forWhat;

  /// License classes covered, e.g. "Technician / General / Extra".
  final String classes;

  /// Authority / currency note.
  final String authority;

  /// Credit line.
  final String credit;

  /// The vet note (why it is on the list / how to use it).
  final String vetNote;

  /// External link, opened with url_launcher. Null for the in-app references
  /// that have no single canonical URL.
  final String? url;
}

/// The vetted study-materials list. The hamstudy STUDY PLATFORM is featured
/// (not its dead-link page); the ARRL copyrighted band chart is cited, not
/// reproduced (the Toolbox renders its own band plan from FCC data).
const List<HamStudyResource> kHamStudyResources = <HamStudyResource>[
  HamStudyResource(
    title: 'hamstudy.org',
    forWhat: 'Practice tests, flashcards, and study mode.',
    classes: 'Technician / General / Extra (plus commercial)',
    authority: 'Current: pools shown with live expiration dates; tracks the '
        '1 Jul 2026 Technician pool.',
    credit: 'hamstudy.org (Signal Stuff)',
    vetNote: 'The strongest external pointer. Free, current, all three '
        'classes. Use the study platform, not its links page.',
    url: 'https://hamstudy.org',
  ),
  HamStudyResource(
    title: 'ARRL License Manuals',
    forWhat: 'Full study text and theory (Technician / General / Extra).',
    classes: 'Technician / General / Extra',
    authority: 'New editions track each question pool.',
    credit: 'ARRL, The National Association for Amateur Radio',
    vetNote: 'The authority reference. Cite and link it; the Toolbox renders '
        'its own band plan from FCC data rather than reproducing ARRL\'s '
        'copyrighted chart.',
    url: 'https://www.arrl.org',
  ),
  HamStudyResource(
    title: 'FCC Part 97 + Frequency Allocation Table',
    forWhat: 'The actual federal rules behind the band plan.',
    classes: 'All',
    authority: 'Primary regulator, live (eCFR).',
    credit: '47 CFR Part 97 / FCC',
    vetNote: 'The source of truth for the band data in this app. Cite it as '
        'the law.',
    url: 'https://www.ecfr.gov/current/title-47/chapter-I/subchapter-D/part-97',
  ),
  HamStudyResource(
    title: 'AREDN documentation',
    forWhat: 'Wi-Fi-adjacent mesh networking on the ham bands.',
    classes: 'Technician / General / Extra',
    authority: 'Active project, current.',
    credit: 'AREDN Project',
    vetNote: 'The explicit Wi-Fi tie-in: commodity 802.11 hardware run under '
        'Part 97. See the Part 15 vs Part 97 reference.',
    url: 'https://www.arednmesh.org',
  ),
];

/// One stable exam-structure fact (citing NCVEC / 97.503). The pool QUESTION
/// COUNT rotates every four years and is deliberately NOT encoded here; only the
/// stable "N questions, M to pass" exam structure is.
class HamExamFact {
  const HamExamFact({
    required this.element,
    required this.questions,
    required this.toPass,
  });

  /// Class + element, e.g. "Technician (Element 2)".
  final String element;

  /// Number of questions on the exam, e.g. "35 questions".
  final String questions;

  /// Pass threshold, e.g. "26 correct to pass".
  final String toPass;
}

/// The stable exam structure (NCVEC / 97.503). No Morse requirement since
/// 23 Feb 2007; the FCC application fee is $35.
const List<HamExamFact> kHamExamStructure = <HamExamFact>[
  HamExamFact(
    element: 'Technician (Element 2)',
    questions: '35 questions',
    toPass: '26 correct to pass',
  ),
  HamExamFact(
    element: 'General (Element 3)',
    questions: '35 questions',
    toPass: '26 correct to pass',
  ),
  HamExamFact(
    element: 'Amateur Extra (Element 4)',
    questions: '50 questions',
    toPass: '37 correct to pass',
  ),
];

/// The two currency caveats the study page must surface (do NOT hard-code
/// around them). Encoded as the displayed guardrail strings.
const String kHamPoolCaveat =
    'A new Technician question pool takes effect 1 Jul 2026 (the 2026-2030 '
    'pool). The exam structure is stable at 35 questions, 26 to pass; the '
    'pool question count rotates every four years, so do not memorize a pool '
    'count.';

const String kHam60mCaveat =
    'The 60 m rules changed effective 13 Feb 2026 (now 4 channels plus the '
    '9.15 W ERP segment). Any chart or notes that predate it are wrong on 60 m.';

const String kHamExamNoMorse =
    'No Morse code requirement (dropped 23 Feb 2007). FCC application fee: '
    '\$35.';
