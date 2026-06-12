// Cable & Connector reference data — compile-time const, source of truth for the
// data-driven Cable & Connector screen (Tier-1, Pass 2b 2026-06-12).
//
// Two blocks:
//   A. Twisted-pair Category capability chart (Cat5e -> Cat8): speed, bandwidth,
//      max distance, PoE relevance. Figures per current TIA-568 (ANSI/TIA-
//      568.2-D) except Cat 7, which is flagged as ISO/IEC Class F (NOT a TIA
//      standard) per the staged DATA caveat.
//   B. RJ-45 8P8C pinout for the two wiring standards (T568B / T568A). The wire
//      colors are domain-canonical DATA (the color IS the standard, GL-003
//      §8.6.2 / §8.15 case-1) and are always paired with the worded color name.
//
// DEDUPE: this is the twisted-pair / Ethernet side only; coax has its own
// `coax-cable` tool. It is a NEW combined tile (id `cable-connector`) distinct
// from the existing `ethernet-cable` and `ethernet-pinout` tiles.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" casing not required
// here (cabling), but kept consistent in prose.

/// One twisted-pair Category row.
class CableCategory {
  const CableCategory({
    required this.category,
    required this.maxSpeed,
    required this.bandwidth,
    required this.maxDistance,
    required this.poe,
    this.caveat = false,
  });

  /// Category label, e.g. `Cat 6A`.
  final String category;

  /// Headline max speed, e.g. `10 Gbps` (the row's measured capability).
  final String maxSpeed;

  /// Rated bandwidth, e.g. `500 MHz`.
  final String bandwidth;

  /// Max channel distance, e.g. `100 m`.
  final String maxDistance;

  /// PoE relevance note.
  final String poe;

  /// True for the Cat 7 outlier (ISO/IEC Class F, not a TIA standard).
  final bool caveat;
}

/// The Category capability chart (Cat5e -> Cat8).
const List<CableCategory> kCableCategories = <CableCategory>[
  CableCategory(
    category: 'Cat 5e',
    maxSpeed: '1 Gbps',
    bandwidth: '100 MHz',
    maxDistance: '100 m',
    poe: 'Carries all PoE types (up to 90 W, Type 4) to 100 m',
  ),
  CableCategory(
    category: 'Cat 6',
    maxSpeed: '1 / 10 Gbps',
    bandwidth: '250 MHz',
    maxDistance: '100 m (1G), 10G to 55 m',
    poe: 'PoE to 100 m; heat de-rates dense bundles',
  ),
  CableCategory(
    category: 'Cat 6A',
    maxSpeed: '10 Gbps',
    bandwidth: '500 MHz',
    maxDistance: '100 m',
    poe: 'Preferred for high-power PoE; larger conductors shed heat',
  ),
  CableCategory(
    category: 'Cat 7',
    maxSpeed: '10 Gbps',
    bandwidth: '600 MHz',
    maxDistance: '100 m',
    poe: 'GG45 / TERA, not native RJ-45',
    caveat: true,
  ),
  CableCategory(
    category: 'Cat 8',
    maxSpeed: '25 / 40 Gbps',
    bandwidth: '2000 MHz',
    maxDistance: '30 m',
    poe: '802.3bt PoE; data-center top-of-rack reach (short runs)',
  ),
];

/// The Cat 7 caveat carried as an on-screen warning verdict (paired with the
/// word, never color-only; GL-003 §8.13).
const String kCat7Caveat =
    'Cat 7 is NOT a TIA standard. TIA never ratified Category 7; it exists only '
    'as ISO/IEC Class F (Cat 7A as Class FA) and is specified for GG45 / TERA '
    'connectors, not native RJ-45. For 10G structured cabling, Cat 6A is the '
    'TIA-recognized choice.';

/// PoE note carried beneath the Category chart.
const String kCablePoeNote =
    'Every category from Cat 5e up carries all PoE types (through 802.3bt Type '
    '4, about 90 W) to 100 m. Cat 6A is preferred for dense high-power runs '
    'because its larger conductors shed heat better.';

// ── RJ-45 pinout (8P8C, 4 pairs) ─────────────────────────────────────────────

/// Which wiring standard's pinout is shown.
enum CableWiringStandard { t568b, t568a }

/// Canonical twisted-pair wire-color hexes (match the staged ethernet SVGs).
/// These are domain-canonical DATA colors (the color IS the standard), NOT
/// design-system tokens; they stay literal in both light and dark.
class WireColors {
  WireColors._();

  static const int orange = 0xFFF58A1F;
  static const int green = 0xFF3CA03C;
  static const int blue = 0xFF2D6CDF;
  static const int brown = 0xFF7A4A22;

  /// The "white" of a striped white/color pair.
  static const int white = 0xFFE5E5E5;
}

/// One pin row: the pin number and its wire color (name + the canonical hex,
/// with the white-stripe flag for a striped wire).
class CablePin {
  const CablePin({
    required this.pin,
    required this.colorName,
    required this.colorHex,
    required this.striped,
  });

  /// RJ-45 pin number, 1-8.
  final int pin;

  /// Worded wire color, e.g. `White/Orange`.
  final String colorName;

  /// Solid (non-stripe) color hex for the swatch.
  final int colorHex;

  /// True for a striped white/color wire (rendered as a split swatch).
  final bool striped;
}

const List<CablePin> _t568b = <CablePin>[
  CablePin(
    pin: 1,
    colorName: 'White/Orange',
    colorHex: WireColors.orange,
    striped: true,
  ),
  CablePin(
    pin: 2,
    colorName: 'Orange',
    colorHex: WireColors.orange,
    striped: false,
  ),
  CablePin(
    pin: 3,
    colorName: 'White/Green',
    colorHex: WireColors.green,
    striped: true,
  ),
  CablePin(
    pin: 4,
    colorName: 'Blue',
    colorHex: WireColors.blue,
    striped: false,
  ),
  CablePin(
    pin: 5,
    colorName: 'White/Blue',
    colorHex: WireColors.blue,
    striped: true,
  ),
  CablePin(
    pin: 6,
    colorName: 'Green',
    colorHex: WireColors.green,
    striped: false,
  ),
  CablePin(
    pin: 7,
    colorName: 'White/Brown',
    colorHex: WireColors.brown,
    striped: true,
  ),
  CablePin(
    pin: 8,
    colorName: 'Brown',
    colorHex: WireColors.brown,
    striped: false,
  ),
];

const List<CablePin> _t568a = <CablePin>[
  CablePin(
    pin: 1,
    colorName: 'White/Green',
    colorHex: WireColors.green,
    striped: true,
  ),
  CablePin(
    pin: 2,
    colorName: 'Green',
    colorHex: WireColors.green,
    striped: false,
  ),
  CablePin(
    pin: 3,
    colorName: 'White/Orange',
    colorHex: WireColors.orange,
    striped: true,
  ),
  CablePin(
    pin: 4,
    colorName: 'Blue',
    colorHex: WireColors.blue,
    striped: false,
  ),
  CablePin(
    pin: 5,
    colorName: 'White/Blue',
    colorHex: WireColors.blue,
    striped: true,
  ),
  CablePin(
    pin: 6,
    colorName: 'Orange',
    colorHex: WireColors.orange,
    striped: false,
  ),
  CablePin(
    pin: 7,
    colorName: 'White/Brown',
    colorHex: WireColors.brown,
    striped: true,
  ),
  CablePin(
    pin: 8,
    colorName: 'Brown',
    colorHex: WireColors.brown,
    striped: false,
  ),
];

/// Pin -> wire mapping per wiring standard.
const Map<CableWiringStandard, List<CablePin>> kCablePinout =
    <CableWiringStandard, List<CablePin>>{
      CableWiringStandard.t568b: _t568b,
      CableWiringStandard.t568a: _t568a,
    };

/// Pinout footnote: how the two standards relate.
const String kPinoutNote =
    'Straight-through uses the same standard on both ends (the norm). Crossover '
    'uses T568A on one end and T568B on the other (legacy; Auto-MDIX makes it '
    'rarely needed). Only pairs 2 and 3 (orange and green) differ between A and '
    'B.';
