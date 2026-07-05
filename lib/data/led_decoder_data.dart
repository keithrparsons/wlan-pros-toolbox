// AP Status-LED Decoder (cross-vendor) — typed const datasets for the
// INTERACTIVE drill-down reference screen (Field & Trade Reference set,
// 2026-07-05). Unlike the static reference screens, this one carries selection
// state: pick a vendor -> pick a model line (when the vendor has more than one)
// -> read that line's own LED state table.
//
// Every string is rendered VERBATIM from Penn's / Pax's voice-gated,
// fact-confirmed copy
// (Deliverables/2026-07-05-field-trade-reference/content/18-led-decoder.md,
// SOP-020 PASS). No copy is rewritten here; the screen only lays it out.
//
// GL-005 / truthfulness — the load-bearing rules this data encodes:
//   1. The same color means DIFFERENT things across vendors, so the model is
//      vendor -> line -> state and NEVER a flat universal legend. The screen
//      surfaces this as a warning band before any color is shown.
//   2. A row's [confidence] is one of three honest markers:
//        - confirmed  -> anchored to a dated official vendor doc; ship the color.
//        - byDesign   -> the vendor deliberately ships NO distinct signal; the
//          "reads as X" note IS the answer, not a gap.
//        - labConfirm -> not documented in any reachable vendor doc. The signal
//          renders as [kLabConfirmMarker] with NO invented color (GL-005). There
//          are exactly six such rows; the widget test asserts each one shows the
//          honest marker, never a fabricated color.
//   3. MikroTik ships as an honest "no standardized status LEDs" note, never a
//      color legend.
//
// VISUAL INDICATOR (added 2026-07-05, Felix, Keith-directed): each state also
// carries a small structured [indicators] list — the literal LED color(s) plus
// a solid/flashing pattern — so the screen can render a colored "ball" per state
// (green / amber / red / blue / white / purple / magenta), solid or gently
// blinking, beside the verbatim text. These are LITERAL LIGHT COLORS, not brand
// or status tokens: they fall under the GL-003 §8.15 case-1 / §8.6.2
// canonical-color exception ("the color IS the data" — same clause as the
// T568A/B wire colors and the TIA-598-C fiber jacket swatches). The color is
// ALWAYS paired with the color named in words in [signal], so it is never
// color-only (WCAG 1.4.1). GL-005 honesty carries through: a [labConfirm] row's
// indicators are [LedColor.unknown] (a neutral hollow "?" — never a guessed
// color), and a [byDesign] row's are [LedColor.none] (no distinct signal, not a
// gap). The verbatim [signal] text remains the authority for every nuance the
// dots cannot carry (sequences, "alternating", blink-count error codes).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; "802.3af/at/bt" casing preserved.

import 'package:flutter/foundation.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
/// Permanent. Interactive drill-down: no bundled plate.
const String kLedDecoderToolId = 'led-decoder';

/// The verbatim honest marker every [LedConfidence.labConfirm] row renders in
/// place of a color. Never invent a color for these (GL-005). The widget/data
/// tests assert every lab-confirm row's [LedStateRow.signal] equals this string.
const String kLabConfirmMarker =
    'Not documented by the vendor, confirm on a lab AP.';

/// How much a single LED state row can be trusted.
enum LedConfidence {
  /// Anchored to a dated official vendor doc captured during research. Ship the
  /// color as-is.
  confirmed,

  /// The vendor deliberately ships NO distinct signal for this state. The
  /// "reads as X" note is the correct answer, not a gap.
  byDesign,

  /// Not documented in any reachable vendor doc. Renders [kLabConfirmMarker]
  /// with no invented color.
  labConfirm,
}

/// The membership section a vendor sits in on the picker. Consumer mesh is kept
/// clearly separate so no one reads a consumer color into an enterprise AP.
enum LedVendorClass { enterprise, consumer }

/// A single literal LED light color — the physical color shown on the front of
/// the AP, NOT a brand or status token. Sanctioned under the GL-003 §8.15
/// case-1 / §8.6.2 canonical-color exception (the color IS the data). The screen
/// maps each value to a legible literal hue at render; the color is always
/// paired with the color named in words in [LedStateRow.signal], so it is never
/// color-only (WCAG 1.4.1).
enum LedColor {
  green,
  amber,
  red,
  blue,
  white,
  purple,
  magenta,

  /// A documented "the LED is dark / off" state (e.g. Extreme WiNG "Dark"). Not
  /// a color: renders a hollow grey ring.
  off,

  /// Documented "no distinct signal" — a [LedConfidence.byDesign] state, or a
  /// vendor-confirmed "no dedicated color" (e.g. a generic blink-to-find). Not a
  /// gap and not a color: renders a neutral dash.
  none,

  /// Undocumented ([LedConfidence.labConfirm]). NEVER a guessed color: renders a
  /// neutral hollow "?" so the honest disclosure carries visually too.
  unknown,
}

/// Whether an indicator is a steady light or a blinking / pulsing one.
enum LedBlink { solid, flashing }

/// One rendered LED indicator: a literal [color] and its [blink] pattern. A row
/// with several documented sub-signals ("solid green ... solid blue ...") or an
/// "alternating" pattern carries more than one; the verbatim [LedStateRow.signal]
/// stays the authority for any nuance beyond color + pattern.
class LedIndicator {
  const LedIndicator(this.color, this.blink);

  final LedColor color;
  final LedBlink blink;
}

/// One row of a line's LED state table.
class LedStateRow {
  const LedStateRow({
    required this.state,
    required this.indicators,
    required this.signal,
    required this.meaning,
    required this.confidence,
  });

  /// The state, e.g. `Booting`, `Healthy / operational`, `Factory reset`.
  final String state;

  /// The literal LED indicator(s) for this row — the colored "ball(s)" plus
  /// solid/flashing pattern. A [LedConfidence.labConfirm] row's indicators are
  /// all [LedColor.unknown] (no invented color, GL-005); a [LedConfidence.byDesign]
  /// row's are [LedColor.none]. The [signal] text remains the authority.
  final List<LedIndicator> indicators;

  /// The color + blink pattern for a documented row; for a
  /// [LedConfidence.labConfirm] row this is [kLabConfirmMarker] (no color); for
  /// a [LedConfidence.byDesign] row this is the "no distinct signal" note.
  final String signal;

  /// What the signal means in the field.
  final String meaning;

  /// Confidence marker for this row.
  final LedConfidence confidence;
}

/// One management line (firmware / mode) under a vendor. A vendor with more than
/// one line makes the model-line pick a required second step.
class LedModelLine {
  const LedModelLine({
    required this.id,
    required this.name,
    required this.rows,
    this.blurb,
    this.extraNote,
    this.source,
  });

  /// Stable id within the vendor, e.g. `catalyst`, `meraki`, `iq-engine`.
  final String id;

  /// The line name shown in the picker and as the detail heading.
  final String name;

  /// The state rows for this line.
  final List<LedStateRow> rows;

  /// Optional one-line framing shown under the line name.
  final String? blurb;

  /// Optional extra note (e.g. the Aruba radio LED, the Meraki bonus rows).
  final String? extraNote;

  /// Optional source attribution line.
  final String? source;
}

/// One vendor. [lines] holds one or more management lines; a vendor with an
/// [honestNote] (MikroTik) ships that note instead of a table.
class LedVendor {
  const LedVendor({
    required this.id,
    required this.name,
    required this.vendorClass,
    this.lines = const <LedModelLine>[],
    this.honestNote,
  });

  /// Stable vendor id, e.g. `cisco`, `aruba`, `mikrotik`.
  final String id;

  /// The vendor name shown in the picker.
  final String name;

  /// Enterprise vs consumer grouping.
  final LedVendorClass vendorClass;

  /// The vendor's management lines. Empty when [honestNote] is set.
  final List<LedModelLine> lines;

  /// When set, the vendor has no standardized LED scheme and ships this note
  /// instead of any table (MikroTik). GL-005: never a fabricated legend.
  final String? honestNote;

  /// True when the vendor forks into more than one line, so the picker must ask
  /// for the model line before showing a table.
  bool get hasMultipleLines => lines.length > 1;
}

/// Whether the confidence chips (Confirmed / By design / Lab-confirm) render.
/// Defaults to [kDebugMode]: the chips are a DEBUG-ONLY QA affordance so Keith
/// can eyeball the confidence taxonomy while testing a debug build, and they do
/// NOT ship in a release build (Keith-directed 2026-07-05). The user-facing
/// honest disclosure is unaffected: the [kLabConfirmMarker] signal text ("Not
/// documented by the vendor, confirm on a lab AP.") and the [LedColor.unknown]
/// hollow "?" indicator on the six undocumented rows stay visible in release —
/// that is genuine disclosure to the user, not a QA stamp. It is a mutable flag
/// (not a const) so the widget test can exercise both the debug (present) and
/// release (absent) branches; production code reads it but never assigns it.
bool debugShowLedConfidenceChips = kDebugMode;

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kLedLead =
    'A field-triage reference that turns an access point\'s status LED into a '
    'plain meaning. Pick the vendor, pick the model line, then read that line\'s '
    'own state table. The color on the front of an AP is the fastest read you '
    'get before you open a laptop, but it only helps if you resolve the model '
    'line first, because the same color means opposite things across vendors.';

/// The cross-vendor collision warning, rendered as a warning band UP FRONT so
/// the color collision is never presented as a universal key.
const String kLedCollisionWarning =
    'The same color carries opposite meaning across vendors. A single "green '
    'equals healthy" master sheet is actively wrong. Solid green: Meraki = '
    'healthy but no clients; Ruckus = healthy with clients; Juniper Mist = '
    'configured by the cloud; Aruba = ready and operational. Solid white: UniFi '
    '= needs adoption (do something); Extreme = healthy on cloud (do nothing); '
    'Eero = healthy; Orbi = ready to sync. This is a per-vendor lookup, never a '
    'universal key.';

/// The standing caveat shown on every lookup (info band).
const String kLedStandingCaveat =
    'An LED meaning is a heuristic, not a guarantee. Confirm against the exact '
    'model\'s official install or getting-started guide. LED behavior can change '
    'with a firmware or dashboard release on cloud-managed lines.';

/// The reference-only defer footer (info band).
const String kLedDeferNote =
    'This is a field reference, not a guarantee. LED meanings are heuristics '
    'that fork by model line, firmware, and management mode. Confirm against the '
    'exact model\'s official install or getting-started guide before acting on a '
    'color.';

// ──────────────────────────────── the data ──────────────────────────────────

/// Every vendor, in picker order. Enterprise lines first, then consumer mesh.
const List<LedVendor> kLedVendors = <LedVendor>[
  // ─────────────────────────────── CISCO ───────────────────────────────
  LedVendor(
    id: 'cisco',
    name: 'Cisco',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'catalyst',
        name: 'Catalyst / IOS-XE (controller or embedded wireless)',
        blurb:
            'Confirmed against the Catalyst 9120AX / 9130AX Getting Started '
            'Guide and the 9136 hardware install guide.',
        source:
            'Cisco Catalyst 9130AX Getting Started Guide (LED table) and the '
            'C9136 hardware install guide.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.red, LedBlink.flashing),
              LedIndicator(LedColor.green, LedBlink.solid),
            ],
            signal:
                'Blinks sequentially green, then red, then off; solid green = '
                'executing the boot loader',
            meaning: 'Power-up, boot loader running',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'No uplink / no controller',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.red, LedBlink.flashing),
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal:
                'Cycles green-red-(blue) repeatedly while joining, can take up '
                'to 5 min; cycling beyond 5 min = cannot find a controller',
            meaning: 'Discovery / join in progress or failing',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.blue, LedBlink.solid),
            ],
            signal:
                'Chirping (pulsing) green = up, no clients associated; solid '
                'blue = at least one client associated',
            meaning: 'Operational (blue here means clients present)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal:
                'Blinking blue = downloading the OS image from the Wireless LAN '
                'Controller',
            meaning: 'Image download in progress, do not interrupt power',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.red, LedBlink.flashing),
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal:
                'Blinking green = boot-loader signing verification failure; '
                'cycling red-off-green-off-blue-off = general warning or '
                'insufficient inline (PoE) power',
            meaning: 'Boot integrity fail or power fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.flashing),
            ],
            signal:
                '"Flash State Enabled" blinks the existing status LED '
                'continuously to locate the AP (triggered from controller or '
                'GUI); no dedicated color',
            meaning: 'Locate mode, user-activated',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.solid),
              LedIndicator(LedColor.red, LedBlink.solid),
            ],
            signal:
                'Mode button held over 20s and under 60s clears internal '
                'storage; status LED changes from blue to red as files clear '
                '(under 20s clears config only)',
            meaning: 'Full reset in progress',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
      LedModelLine(
        id: 'meraki',
        name: 'Meraki MR (cloud-managed)',
        blurb:
            'Confirmed against the MR46 Installation Guide and the Meraki '
            'factory-reset doc.',
        extraNote:
            'Bonus: blinking green = site-survey mode; "run dark" mode = LED '
            'off (dashboard-configurable).',
        source:
            'MR46 Installation Guide and the Meraki factory-reset doc.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Rainbow / orange startup cycle',
            meaning: 'Powering on',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'No cloud / needs config',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal:
                'Solid orange (amber); permanent orange can also mean a boot or '
                'hardware issue',
            meaning: 'No cloud connection yet',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Joining / no internet',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Flashing orange',
            meaning: 'Reaching for the cloud, no internet yet',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
              LedIndicator(LedColor.blue, LedBlink.solid),
            ],
            signal:
                'Solid green = operational, no clients; solid blue = '
                'operational, clients associated',
            meaning: 'Operational (blue means clients present)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal: 'Blinking blue = "AP is upgrading"',
            meaning: 'Firmware upgrade in progress',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.solid),
              LedIndicator(LedColor.off, LedBlink.solid),
            ],
            signal:
                'Permanent solid orange = boot or hardware issue; no LEDs lit = '
                'faulty unit, needs replacement',
            meaning: 'Hardware fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.flashing),
            ],
            signal: 'Dashboard "blink LED" action; no distinct documented color',
            meaning: 'Locate mode',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal:
                'No distinct signal (by design). Meraki documents no dedicated '
                'reset color. After reset the AP reboots into the normal rainbow '
                '/ orange startup and re-downloads config (5 to 10 min).',
            meaning: 'Reset reads as an ordinary reboot',
            confidence: LedConfidence.byDesign,
          ),
        ],
      ),
    ],
  ),

  // ─────────────────────────── JUNIPER MIST ────────────────────────────
  LedVendor(
    id: 'juniper-mist',
    name: 'Juniper Mist',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'mist',
        name: 'Juniper Mist (cloud-managed)',
        blurb:
            'Single multicolor status LED. The cleanest, richest official '
            'scheme in the set. Captured directly from the official Juniper '
            'doc.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.flashing),
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal:
                'Blinking red (~3s), then alternating green and yellow (~12s)',
            meaning: 'Powering on',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'No uplink / joining cloud',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal:
                'Blinking green plus yellow (~30 to 40s); yellow blink-count '
                'error codes report the fault (3 blinks = no IP; other counts = '
                'gateway, DNS, or cloud-auth codes)',
            meaning: 'Reaching the cloud, or reporting why it cannot',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Connected to cloud (pre-config)',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
            ],
            signal: 'Solid white',
            meaning: 'Reached the cloud, not yet configured',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
              LedIndicator(LedColor.blue, LedBlink.solid),
            ],
            signal:
                'Solid green = configured by the Mist cloud; solid blue = at '
                'least one wireless client connected',
            meaning: 'Operational',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Blinking orange',
            meaning: 'Upgrading; do not interrupt',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.solid),
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal:
                'Solid red = AP failed; green fading to off = insufficient PoE '
                'power',
            meaning: 'Hardware fault or power shortfall',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.purple, LedBlink.flashing),
            ],
            signal: 'Blinking green plus purple',
            meaning:
                'Locate mode, user-activated (the only enterprise line with a '
                'documented distinct locate color)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
              LedIndicator(LedColor.red, LedBlink.solid),
            ],
            signal:
                'White fading to off = reset pending; white then red = the '
                'Reset button is being held',
            meaning: 'Reset in progress',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),

  // ───────────────────────────── HPE ARUBA ─────────────────────────────
  LedVendor(
    id: 'aruba',
    name: 'HPE Aruba',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'campus',
        name: 'Aruba Campus (AOS / Instant)',
        blurb:
            'Confirmed against the official AP-635 (630 Series) Installation '
            'Guide read page-by-page via the FCC filing mirror, corroborated by '
            'the AP-500 Series guide.',
        extraNote:
            'Radio LED (separate from the system LED): green solid = access '
            'mode; green flashing-off = uplink / mesh mode; amber solid = '
            'monitor or spectrum-analysis mode.',
        source:
            'AP-635 (630 Series) Install Guide, Table 1 / Table 2, via the FCC '
            'filing mirror; AP-500 Series guide corroborating.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal: 'Green blinking (1s on, 1s off)',
            meaning: 'Booting, not yet ready',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'No uplink / needs config',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal:
                'No distinct signal (by design). The campus scheme has no '
                '"unadopted / needs-config" color. Before it reaches a '
                'controller or Central the AP simply shows green-blinking '
                '(booting); once provisioned it goes green-solid.',
            meaning: 'No adoption state to display',
            confidence: LedConfidence.byDesign,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal:
                'Green solid = ready and fully functional, no network '
                'restrictions; green flashing-off = ready but uplink negotiated '
                'sub-optimal speed (under 1 Gbps); green flashing-on = '
                'deep-sleep; amber solid = ready, restricted power mode '
                '(limited PoE)',
            meaning: 'Operational',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning:
                'No dedicated upgrade LED in any campus hardware guide; upgrade '
                'is orchestrated by the controller / Central and typically '
                'presents on the AP as a reboot (green-blinking).',
            confidence: LedConfidence.labConfirm,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.solid),
            ],
            signal: 'Red = system error condition, immediate attention required',
            meaning: 'Fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal:
                'Blink mode (software-selectable: Default / Off / Blink) = all '
                'LEDs blink green, synchronized',
            meaning: 'Locate / identify, user-activated',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal:
                'Reset button held over 10s (or held during power-up); the '
                'system status LED flashes again within 15s indicating the reset '
                'is complete, then the AP boots green-blinking with factory '
                'defaults',
            meaning: 'Full reset in progress',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
      LedModelLine(
        id: 'instant-on',
        name: 'Aruba Instant On (SMB)',
        blurb:
            'A separate scheme from Campus, confirmed across the official '
            'Instant On install guide, ManualsLib page-render, and the '
            'Cradlepoint AP22 LED KB. Two LEDs (System + Radio).',
        source:
            'Instant On official LED doc and AP22 Installation Guide, '
            'ManualsLib page-render, and the Cradlepoint AP22 LED KB.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal: 'Blinking green',
            meaning: 'Booting',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'No uplink / needs setup',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Alternating green and amber',
            meaning: 'Ready to onboard, run the app',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
            ],
            signal: 'Solid green',
            meaning: 'Connected and configured',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal: 'Blinking green (same signal as boot)',
            meaning: 'Booting or upgrading',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.solid),
              LedIndicator(LedColor.red, LedBlink.solid),
            ],
            signal:
                'Solid amber = a problem was detected (e.g. no or limited '
                'internet); solid red = issue requiring attention',
            meaning: 'Attention or fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning:
                'The mobile app has a "Locate" that flashes the LED, but no '
                'distinct documented color, it is a generic flash of the '
                'existing LED.',
            confidence: LedConfidence.labConfirm,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal:
                'No distinct signal (by design). Hold reset over 10s (or during '
                'power-up ~15s); the device reboots into blinking green. No '
                'unique reset color.',
            meaning: 'Reset reads as a reboot',
            confidence: LedConfidence.byDesign,
          ),
        ],
      ),
    ],
  ),

  // ─────────────────────────── EXTREME NETWORKS ────────────────────────
  LedVendor(
    id: 'extreme',
    name: 'Extreme Networks',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'iq-engine',
        name: 'ExtremeCloud IQ / IQ Engine (AP3000 / AP4000, CAPWAP)',
        blurb:
            'The AP3000 / AP4000 class ships different LED semantics under '
            'ExtremeCloud IQ (IQ Engine, CAPWAP) versus legacy WiNG. A single '
            '"Extreme" table would be wrong. Confirmed from Extreme\'s own doc '
            'portal.',
        source:
            'Extreme AP4000 / AP3000 IQ Engine LED tables '
            '(documentation.extremenetworks.com).',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting / no CAPWAP',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal: 'Solid amber',
            meaning: 'Booting, or running without a CAPWAP connection to Cloud IQ',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
            ],
            signal: 'Solid white',
            meaning: 'CAPWAP to ExtremeCloud IQ, ready / normal',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Reduced power (CAPWAP up)',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Slow-blinking white',
            meaning:
                'CAPWAP up but on 802.3af instead of 802.3at (AP4000: 802.3at '
                'instead of 802.3bt)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Reduced power (no CAPWAP)',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Slow-blinking amber',
            meaning: 'No CAPWAP and running on 802.3af',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Fast-blinking amber',
            meaning: 'IQ Engine firmware upgrade in progress',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal:
                'No distinct signal (by design). No dedicated red / error '
                'color. Persistent solid amber (no CAPWAP) is the "something is '
                'wrong" signal.',
            meaning: 'Persistent amber reads as the fault',
            confidence: LedConfidence.byDesign,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning: 'Not in the IQ Engine LED table.',
            confidence: LedConfidence.labConfirm,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning: 'Not in the IQ Engine LED table.',
            confidence: LedConfidence.labConfirm,
          ),
        ],
      ),
      LedModelLine(
        id: 'wing',
        name: 'ExtremeWireless WiNG (legacy, separate table)',
        blurb:
            'A genuinely distinct scheme. Same hardware, different firmware '
            'image.',
        source:
            'Extreme AP4000 / AP3000 WiNG LED tables '
            '(documentation.extremenetworks.com).',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'No power / LED off',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.off, LedBlink.solid),
            ],
            signal: 'Dark',
            meaning: 'Not powered, or controller-disabled LED',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
            ],
            signal: 'Solid white',
            meaning: 'Booting, or already taken over by the controller',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Being adopted / adoption failed',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Slow-blinking white',
            meaning: 'Controller takeover in progress, or takeover failed',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Getting IP',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal: 'Fast-blinking amber',
            meaning: 'Acquiring a DHCP IP address',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal: 'Solid amber',
            meaning: 'Firmware upgrade in progress',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Flashing fading white',
            meaning: 'Location aid to help find the AP (controller-configured)',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),

  // ─────────────────────────── UBIQUITI UNIFI ──────────────────────────
  LedVendor(
    id: 'unifi',
    name: 'Ubiquiti UniFi',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'unifi',
        name: 'Ubiquiti UniFi',
        blurb:
            'Single scheme, standardized white and blue across the UniFi line. '
            'Anchored to the official Help Center.',
        source:
            'help.ui.com "Understanding Device LED Status Indicators".',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting / init',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Flashing white (~1 to 2s on and off)',
            meaning: 'Powering on',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Needs adoption',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
            ],
            signal: 'Steady white',
            meaning: 'Ready for adoption (do something)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal: 'Quick-flash white and blue',
            meaning: 'Upgrading; do not interrupt',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.solid),
            ],
            signal: 'Steady blue',
            meaning: 'Adopted, normal operation',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.flashing),
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal:
                'Steady blue with a brief off every ~5s = lost uplink; strobing '
                'white / off = recovery mode, power-cycle the AP',
            meaning: 'Uplink loss or recovery',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal:
                'Rapid flashing blue / off (activated from the UniFi Network '
                'app)',
            meaning: 'Locate mode, user-activated',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal:
                'Steady white = "device has been factory reset and must be set '
                'up from scratch"; flashing white-blue-off (hold reset before '
                'power-on until this appears) = TFTP recovery mode',
            meaning: 'Reset complete, ready for adoption',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),

  // ─────────────────────────────── RUCKUS ──────────────────────────────
  LedVendor(
    id: 'ruckus',
    name: 'Ruckus (indoor R / H series)',
    vendorClass: LedVendorClass.enterprise,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'indoor',
        name: 'Ruckus indoor (R / H series)',
        blurb:
            'Two LEDs on indoor APs: a controller (CTL / DIR) LED and a power '
            '(PWR) / radio LED. A headline collision case: solid green on the '
            'radio LED means clients are present, the opposite of Meraki.',
        source:
            'Ruckus KB "LED Status on Indoor APs" (article 000001629) and the '
            'physical-reset KBs.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.solid),
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal:
                'PWR LED solid red = boot-up in progress; sequence progresses '
                'red, then amber, then flashing amber (searching for controller)',
            meaning: 'Powering up, seeking controller',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Joined controller',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
            ],
            signal: 'CTL LED solid green',
            meaning: 'Joined the controller',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.solid),
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal:
                'Radio LED green = clients associated; radio LED amber = up, no '
                'clients',
            meaning: 'Operational (green here means clients present)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Firmware upgrading',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal:
                'DIR / CTL LED fast-flashing green = managed by a controller '
                'and receiving configuration updates or a firmware image',
            meaning: 'Config push or image download',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning:
                'No dedicated fault color exists; closest signals are PWR stuck '
                'solid red (boot hang) and DIR slow-flashing green (managed but '
                'unable to reach the controller).',
            confidence: LedConfidence.labConfirm,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.unknown, LedBlink.solid),
            ],
            signal: kLabConfirmMarker,
            meaning:
                'No per-AP blink-to-find color for indoor APs; in Unleashed the '
                'Master AP shows CTL solid green, but there is no locate-flash '
                'for member APs.',
            confidence: LedConfidence.labConfirm,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.solid),
              LedIndicator(LedColor.green, LedBlink.flashing),
            ],
            signal:
                'After reset, PWR solid red (boot) then blinks green = '
                'factory-default state, no routable IP; broadcasts '
                'CONFIGURE.ME-XXXXXX',
            meaning: 'Reset complete, awaiting setup',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),

  // ────────────────────────────── MIKROTIK ─────────────────────────────
  LedVendor(
    id: 'mikrotik',
    name: 'MikroTik',
    vendorClass: LedVendorClass.enterprise,
    honestNote:
        'MikroTik APs do not ship a defined enterprise status-LED semantic. '
        'There is no "healthy / error / joining" color language, so there is no '
        'table to show here. What is real: RouterOS LEDs are user-configurable '
        '(/system leds maps signal-strength or interface-activity to LEDs); on '
        'cAP ax the mode button defaults to "dark mode" with the LEDs off; and '
        'during CAP / CAPsMAN provisioning, holding the mode button turns the '
        'User LED solid when the device enters CAP mode, and in CAP mode the AP '
        'LED flashes. Behavior is model- and config-dependent, so read the '
        'specific product\'s manual. Building a color legend here would '
        'fabricate meaning.',
  ),

  // ───────────────────────── CONSUMER MESH: ORBI ───────────────────────
  LedVendor(
    id: 'orbi',
    name: 'Netgear Orbi',
    vendorClass: LedVendorClass.consumer,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'orbi',
        name: 'Netgear Orbi (consumer)',
        blurb:
            'Single ring LED. Well-documented, so High. Note that Orbi Pro uses '
            'a slightly different scheme.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Pulsing white (also shown when Sync is pressed)',
            meaning: 'Powering on',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Needs pairing',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
            ],
            signal: 'Solid white',
            meaning: 'Ready to sync (press Sync)',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Joining / syncing',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Pulsing white',
            meaning: 'Syncing',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.solid),
              LedIndicator(LedColor.amber, LedBlink.solid),
            ],
            signal:
                'Solid blue = good router-to-satellite backhaul (the LED then '
                'auto-off after a few minutes, which is normal); solid amber = '
                'fair backhaul, consider repositioning',
            meaning: 'Operational',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.magenta, LedBlink.solid),
              LedIndicator(LedColor.magenta, LedBlink.flashing),
              LedIndicator(LedColor.red, LedBlink.flashing),
            ],
            signal:
                'Solid magenta = no backhaul or no internet; pulsing magenta = '
                'connection failed or lost; pulsing red = needs attention '
                '(hardware or connectivity)',
            meaning: 'Fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal: 'None (single ring)',
            meaning: 'Not available',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.amber, LedBlink.flashing),
            ],
            signal:
                'Pulsing amber (shared signal: firmware update or factory reset)',
            meaning: 'Reset or update in progress',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),

  // ───────────────────────── CONSUMER MESH: EERO ───────────────────────
  LedVendor(
    id: 'eero',
    name: 'Amazon Eero',
    vendorClass: LedVendorClass.consumer,
    lines: <LedModelLine>[
      LedModelLine(
        id: 'eero',
        name: 'Amazon Eero (consumer)',
        blurb: 'Single LED. Well-documented, so High.',
        rows: <LedStateRow>[
          LedStateRow(
            state: 'Booting',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.flashing),
            ],
            signal: 'Blinking white',
            meaning: 'Starting up, connection in progress',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Needs config',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.flashing),
            ],
            signal: 'Blinking blue',
            meaning: 'Ready to set up in the app',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Joining',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.blue, LedBlink.solid),
            ],
            signal: 'Solid blue',
            meaning: 'App connected, configuring the network',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Healthy / operational',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.white, LedBlink.solid),
              LedIndicator(LedColor.off, LedBlink.solid),
            ],
            signal: 'Solid white (or off if the LED is disabled)',
            meaning: 'Operational',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Fault / error',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.solid),
            ],
            signal: 'Solid red = no internet or WAN fault upstream',
            meaning: 'Upstream fault',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Locate / blink-to-find',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.none, LedBlink.solid),
            ],
            signal: 'None (single LED)',
            meaning: 'Not available',
            confidence: LedConfidence.confirmed,
          ),
          LedStateRow(
            state: 'Factory reset',
            indicators: <LedIndicator>[
              LedIndicator(LedColor.red, LedBlink.flashing),
            ],
            signal: 'Flashing red (during a hard reset)',
            meaning: 'Reset in progress',
            confidence: LedConfidence.confirmed,
          ),
        ],
      ),
    ],
  ),
];
