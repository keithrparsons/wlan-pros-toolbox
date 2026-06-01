// Cellular Information — normalized, iOS-only mobile-network model (TICKET-02).
//
// The single model the "Cellular Information" screen renders. It mirrors the
// honest-null pattern of [ConnectedAp]: every field is nullable, and a missing
// field renders an explicit "Unavailable" row rather than a fabricated value or
// a silent drop (GL-005 / GL-008).
//
// DATA SOURCE — Shortcuts bridge ONLY. There is intentionally NO native
// CoreTelephony path:
//   * CTCarrier is deprecated since iOS 16.4 and returns dummy values
//     (placeholder carrier name, MNC 65535) — reading it natively is junk.
//   * Cellular signal strength (RSRP / RSRQ / RSSI / dBm) is hard-blocked for
//     third-party apps; the only way to it is a private API and an App Store
//     rejection. We never reach for it.
// The stock Shortcuts "Get Network Details" action, running in Apple's privacy
// context, hands over carrier name, radio technology, signal bars, country
// code, and roaming — more than a native app can read — via the same App Group
// bridge already proven for Wi-Fi. See [CellularInfoBridge].
//
// SIGNAL BARS — a coarse 0-to-4 status-bar indicator, NOT a calibrated reading.
// It is presented as bars or "0 to 4" ONLY and is NEVER relabeled dBm, RSRP, or
// RSRQ. We do not have a raw signal value and must not imply we do.
//
// macOS / web / Android / Windows have no cellular radio (or no bridge), so the
// screen shows an honest unavailable state rather than this model.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A normalized snapshot of the device's cellular connection. Immutable.
///
/// Every field is nullable: the companion Shortcut may omit any of them, and a
/// missing field renders an honest "Unavailable" row (never fabricated).
@immutable
class CellularInfo {
  const CellularInfo({
    this.carrier,
    this.radioTechnology,
    this.signalBars,
    this.countryCode,
    this.roaming,
  });

  /// Mobile carrier / operator name (e.g. "Verizon"). Null when the Shortcut
  /// omitted it. NEVER read from the deprecated CTCarrier (which returns a
  /// placeholder) — only from the Shortcut context.
  final String? carrier;

  /// Radio access technology label as emitted (e.g. "LTE", "5G NR",
  /// "5G NRNSA"). Kept verbatim — it is descriptive text, not math. Null when
  /// absent.
  final String? radioTechnology;

  /// Signal bars — a coarse 0-to-4 status-bar indicator. NOT a dBm / RSRP /
  /// RSRQ value, and never to be presented as one (the platform does not expose
  /// a raw signal reading to apps). Clamped to 0..4 on parse; null when absent.
  final int? signalBars;

  /// Regulatory country code (e.g. "US"). Null when absent. Distinct from the
  /// mobile network code (MNC), which the Shortcut does not surface as a field.
  final String? countryCode;

  /// Whether the device is roaming abroad. Null when the Shortcut omitted it.
  final bool? roaming;

  /// The minimum and maximum number of signal bars iOS reports (the status-bar
  /// scale). Exposed so the screen can render the bars without hardcoding the
  /// scale in two places.
  static const int minSignalBars = 0;
  static const int maxSignalBars = 4;

  /// `true` when at least one field is present — i.e. a real reading arrived.
  /// An all-null model means the Shortcut delivered an empty/garbage object, so
  /// the screen shows its empty / waiting state rather than a grid of
  /// "Unavailable".
  bool get hasAnyData =>
      carrier != null ||
      radioTechnology != null ||
      signalBars != null ||
      countryCode != null ||
      roaming != null;

  /// Parse a JSON string from the Shortcut into a [CellularInfo]. Returns null
  /// when the string is not a JSON object (malformed, an array, a scalar) —
  /// callers treat null as "no valid payload yet" and show the empty state.
  /// Never throws.
  static CellularInfo? fromJsonString(String jsonString) {
    if (jsonString.trim().isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;
      return CellularInfo.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Build from an already-decoded map. Matches keys CASE-INSENSITIVELY against
  /// the canonical contract (`carrier`, `radioTechnology`, `signalBars`,
  /// `countryCode`, `roaming`) plus documented human-readable variants from the
  /// stock "Get Network Details" action, so both the published Shortcut and a
  /// hand-built one populate the model. (Case-insensitive keys are a Wi-Fi
  /// bridge learning, TICKET-01.)
  ///
  /// Keys are normalized with both `.trim()` and `.toLowerCase()`: the incoming
  /// map keys are hand-assembled in Shortcuts and can carry stray whitespace
  /// (a real on-device bug saw the key arrive as `"signalBars "` with a trailing
  /// space and silently fail to match). Lookup keys below are already clean, so
  /// trimming only the incoming side is safe.
  factory CellularInfo.fromMap(Map<dynamic, dynamic> map) {
    final Map<String, dynamic> ci = <String, dynamic>{};
    map.forEach((dynamic k, dynamic v) {
      if (k != null) ci[k.toString().trim().toLowerCase()] = v;
    });

    String? pickString(List<String> keys) {
      for (final String key in keys) {
        final dynamic v = ci[key.trim().toLowerCase()];
        if (v == null) continue;
        final String s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    int? pickBars(List<String> keys) {
      final String? s = pickString(keys);
      if (s == null) return null;
      final RegExp numRe = RegExp(r'\d+');
      final Match? m = numRe.firstMatch(s);
      if (m == null) return null;
      final int? n = int.tryParse(m.group(0)!);
      if (n == null) return null;
      // Clamp to the iOS status-bar scale; never trust an out-of-range value.
      return n.clamp(minSignalBars, maxSignalBars);
    }

    bool? pickBool(List<String> keys) {
      final String? s = pickString(keys);
      if (s == null) return null;
      final String v = s.toLowerCase();
      if (v == 'true' || v == 'yes' || v == '1') return true;
      if (v == 'false' || v == 'no' || v == '0') return false;
      return null;
    }

    return CellularInfo(
      carrier: pickString(<String>['carrier', 'Carrier', 'Carrier Name']),
      radioTechnology: normalizeRadioTechnology(pickString(<String>[
        'radioTechnology',
        'Radio Technology',
        'radio',
      ])),
      signalBars: pickBars(<String>[
        'signalBars',
        'Signal Bars',
        'Number of Signal Bars',
        'bars',
      ]),
      countryCode: pickString(<String>[
        'countryCode',
        'Country Code',
        'country',
      ]),
      roaming: pickBool(<String>[
        'roaming',
        'Roaming',
        'Is Roaming Abroad',
        'Is Roaming Abroad?',
      ]),
    );
  }

  /// Maps known raw `CTRadioAccessTechnology*` constants (the form iOS emits via
  /// CoreTelephony / the Shortcuts cellular branch on some payloads) to friendly
  /// labels. Values that are already friendly pass through unchanged — the
  /// iPhone returned a clean value on the 2026-06-01 device test, so the default
  /// is pass-through and a value is NEVER blanked when no mapping matches.
  ///
  /// Returns null only for a null input; an empty / whitespace-only string also
  /// returns null (the caller already drops empties via [pickString]).
  static String? normalizeRadioTechnology(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    const Map<String, String> friendly = <String, String>{
      'CTRadioAccessTechnologyNRNSA': '5G (NSA)',
      'CTRadioAccessTechnologyNR': '5G',
      'CTRadioAccessTechnologyLTE': 'LTE',
      'CTRadioAccessTechnologyWCDMA': 'WCDMA',
      'CTRadioAccessTechnologyHSDPA': 'HSDPA',
      'CTRadioAccessTechnologyHSUPA': 'HSUPA',
      'CTRadioAccessTechnologyCDMA1x': 'CDMA 1x',
      'CTRadioAccessTechnologyCDMAEVDORev0': 'CDMA EV-DO Rev. 0',
      'CTRadioAccessTechnologyCDMAEVDORevA': 'CDMA EV-DO Rev. A',
      'CTRadioAccessTechnologyCDMAEVDORevB': 'CDMA EV-DO Rev. B',
      'CTRadioAccessTechnologyeHRPD': 'eHRPD',
      'CTRadioAccessTechnologyEdge': 'Edge',
      'CTRadioAccessTechnologyGPRS': 'GPRS',
    };

    final String? mapped = friendly[trimmed];
    // Pass through anything already friendly (never blank a value).
    return mapped ?? trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is CellularInfo &&
      other.carrier == carrier &&
      other.radioTechnology == radioTechnology &&
      other.signalBars == signalBars &&
      other.countryCode == countryCode &&
      other.roaming == roaming;

  @override
  int get hashCode =>
      Object.hash(carrier, radioTechnology, signalBars, countryCode, roaming);

  @override
  String toString() =>
      'CellularInfo(carrier: $carrier, radioTechnology: $radioTechnology, '
      'signalBars: $signalBars, countryCode: $countryCode, roaming: $roaming)';
}
