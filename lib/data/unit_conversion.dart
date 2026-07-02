// Unit-conversion model — pure Dart, no Flutter, no network.
//
// Batch 4a (the general-purpose sibling of the distance-only
// metric_conversion_screen.dart, per the FELIX-BUILD-BRIEF). One tool, multiple
// selectable categories; each category is a set of units that share a single
// linear (or, for temperature, affine) pivot so every pair converts by
// "to base, then from base".
//
// CORRECTNESS NOTES (the brief is explicit about these):
//   * Data storage and transfer-rate units distinguish DECIMAL (SI, powers of
//     1000 — KB, MB, GB, TB) from BINARY (IEC, powers of 1024 — KiB, MiB, GiB,
//     TiB). A "KB" is 1000 bytes; a "KiB" is 1024 bytes. We never conflate them.
//   * The base unit per category is the smallest natural unit (bit for storage,
//     bit/s for rate, meter for length, watt for power, etc.) so factors are
//     exact small integers or exact decimals where possible.
//   * Power includes dBm as a NON-LINEAR member. dBm cannot be a linear factor
//     of watts, so the power category is handled with an explicit log/antilog
//     pair that REUSES the same math the dbm_watt converter uses
//     (W = 10^(dBm/10)/1000; dBm = 10*log10(W*1000)) rather than forking it.
//   * Temperature is affine (offset + scale), not a single multiplicative
//     factor, so it is handled with explicit to/from-Kelvin functions.
//
// Each non-linear category (power, temperature) overrides the linear path; all
// the others use the shared factor table. The math lives in top-level pure
// functions so tests call them directly without pumping a widget.

import 'dart:math' as math;

/// The selectable conversion categories. Order here is the on-screen order in
/// the category `AppSelect`.
enum UnitCategory {
  dataRate,
  dataStorage,
  length,
  power,
  metricPrefix,
  speed,
  temperature,
  time,
}

/// Human label for a category (the `AppSelect` display string).
String categoryLabel(UnitCategory c) {
  switch (c) {
    case UnitCategory.dataRate:
      return 'Data transfer rate';
    case UnitCategory.dataStorage:
      return 'Data storage';
    case UnitCategory.length:
      return 'Length';
    case UnitCategory.power:
      return 'Power';
    case UnitCategory.metricPrefix:
      return 'Metric prefix';
    case UnitCategory.speed:
      return 'Speed';
    case UnitCategory.temperature:
      return 'Temperature';
    case UnitCategory.time:
      return 'Time';
  }
}

/// One unit within a category. [factorToBase] is "how many base units in one of
/// this unit" — multiply a value by it to reach the category base, divide to
/// leave it. For the two non-linear categories (power's dBm, temperature) the
/// factor is unused and the conversion routes through the affine/log helpers
/// keyed on [id]; those units carry `factorToBase: 0` as a sentinel and MUST
/// not be reached by the linear path.
class Unit {
  const Unit({
    required this.id,
    required this.symbol,
    required this.factorToBase,
    this.nonLinear = false,
  });

  /// Stable kebab-ish identifier, unique within its category. Backs the
  /// non-linear routing (dBm, temperature units) and the `AppSelect` value.
  final String id;

  /// Short display symbol shown in the selector and result.
  final String symbol;

  /// Base units per one of this unit (linear path). Unused when [nonLinear].
  final double factorToBase;

  /// True for units that are not a linear multiple of the base (dBm, °C/°F/K).
  /// The linear `convert` path throws if it ever sees one; the category-aware
  /// [UnitConversion.convert] routes these through the dedicated helpers.
  final bool nonLinear;
}

/// The unit set for each category, in display order. The FIRST unit in each
/// list is the category default "from"; the SECOND is the default "to".
class UnitConversion {
  UnitConversion._();

  // ─── Data transfer rate ───────────────────────────────────────────────────
  // Base: bit per second (bps). Decimal SI multiples (kbps/Mbps/Gbps/Tbps) are
  // powers of 1000 — the NETWORKING convention, where "Mbps" means 1,000,000
  // bits/s, not 2^20. Byte-rate units (KB/s, MB/s) are decimal-byte (×8 bits,
  // ×1000). Ethernet presets are the nominal line rates (10/100/1000 Mb/s,
  // 2.5/5/10/25/40/100 Gb/s) expressed in bits/s.
  static const List<Unit> dataRateUnits = <Unit>[
    Unit(id: 'bps', symbol: 'bps', factorToBase: 1),
    Unit(id: 'kbps', symbol: 'kbps', factorToBase: 1e3),
    Unit(id: 'mbps', symbol: 'Mbps', factorToBase: 1e6),
    Unit(id: 'gbps', symbol: 'Gbps', factorToBase: 1e9),
    Unit(id: 'tbps', symbol: 'Tbps', factorToBase: 1e12),
    Unit(id: 'kBps', symbol: 'KB/s', factorToBase: 8 * 1e3),
    Unit(id: 'mBps', symbol: 'MB/s', factorToBase: 8 * 1e6),
    // Ethernet line-rate presets (bits/s).
    Unit(id: 'eth10', symbol: '10BASE-T', factorToBase: 10 * 1e6),
    Unit(id: 'eth100', symbol: '100BASE-TX', factorToBase: 100 * 1e6),
    Unit(id: 'eth1000', symbol: '1000BASE-T', factorToBase: 1000 * 1e6),
    Unit(id: 'eth2g5', symbol: '2.5GBASE-T', factorToBase: 2.5 * 1e9),
    Unit(id: 'eth5g', symbol: '5GBASE-T', factorToBase: 5 * 1e9),
    Unit(id: 'eth10g', symbol: '10GBASE-T', factorToBase: 10 * 1e9),
    Unit(id: 'eth25g', symbol: '25GBASE-T', factorToBase: 25 * 1e9),
    Unit(id: 'eth40g', symbol: '40GbE', factorToBase: 40 * 1e9),
    Unit(id: 'eth100g', symbol: '100GbE', factorToBase: 100 * 1e9),
  ];

  // ─── Data storage ──────────────────────────────────────────────────────────
  // Base: bit. DECIMAL (SI) multiples are powers of 1000 (kB/MB/GB/TB); BINARY
  // (IEC) multiples are powers of 1024 (KiB/MiB/GiB/TiB). 1 byte = 8 bits. This
  // is the distinction the brief calls out — a KB (1000 B) is NOT a KiB (1024 B).
  static const double _b = 8; // bits per byte
  static const List<Unit> dataStorageUnits = <Unit>[
    Unit(id: 'bit', symbol: 'bit', factorToBase: 1),
    Unit(id: 'byte', symbol: 'B', factorToBase: _b),
    // Decimal (SI, ×1000).
    Unit(id: 'kb', symbol: 'KB', factorToBase: _b * 1e3),
    Unit(id: 'mb', symbol: 'MB', factorToBase: _b * 1e6),
    Unit(id: 'gb', symbol: 'GB', factorToBase: _b * 1e9),
    Unit(id: 'tb', symbol: 'TB', factorToBase: _b * 1e12),
    // Binary (IEC, ×1024).
    Unit(id: 'kib', symbol: 'KiB', factorToBase: _b * 1024),
    Unit(id: 'mib', symbol: 'MiB', factorToBase: _b * 1024 * 1024),
    Unit(id: 'gib', symbol: 'GiB', factorToBase: _b * 1024 * 1024 * 1024),
    Unit(
      id: 'tib',
      symbol: 'TiB',
      factorToBase: _b * 1024.0 * 1024.0 * 1024.0 * 1024.0,
    ),
  ];

  // ─── Length ──────────────────────────────────────────────────────────────
  // Base: meter. Mirrors the metric_conversion_screen.dart toM factors exactly
  // (so the two tools agree to the decimal), plus mm for completeness.
  static const List<Unit> lengthUnits = <Unit>[
    Unit(id: 'm', symbol: 'm', factorToBase: 1),
    Unit(id: 'ft', symbol: 'ft', factorToBase: 0.3048),
    Unit(id: 'km', symbol: 'km', factorToBase: 1000),
    Unit(id: 'mi', symbol: 'mi', factorToBase: 1609.344),
    Unit(id: 'cm', symbol: 'cm', factorToBase: 0.01),
    Unit(id: 'mm', symbol: 'mm', factorToBase: 0.001),
    Unit(id: 'in', symbol: 'in', factorToBase: 0.0254),
    Unit(id: 'yd', symbol: 'yd', factorToBase: 0.9144),
    Unit(id: 'nmi', symbol: 'nmi', factorToBase: 1852),
  ];

  // ─── Power ─────────────────────────────────────────────────────────────────
  // Base: watt (linear members), with dBm as a NON-LINEAR member routed through
  // the same log math the dBm/Watt converter uses (not forked). mW and kW are
  // linear factors of the watt; dBm is decibels-relative-to-1-mW.
  static const List<Unit> powerUnits = <Unit>[
    Unit(id: 'dbm', symbol: 'dBm', factorToBase: 0, nonLinear: true),
    Unit(id: 'mw', symbol: 'mW', factorToBase: 1e-3),
    Unit(id: 'w', symbol: 'W', factorToBase: 1),
    Unit(id: 'kw', symbol: 'kW', factorToBase: 1e3),
  ];

  // ─── Metric prefix ──────────────────────────────────────────────────────────
  // Base: the unprefixed unit (1). Each prefix is its decimal power. Pico→tera
  // per the brief; the value is dimensionless ("5 mega-units = 5,000,000 units").
  static const List<Unit> metricPrefixUnits = <Unit>[
    Unit(id: 'pico', symbol: 'p (10^-12)', factorToBase: 1e-12),
    Unit(id: 'nano', symbol: 'n (10^-9)', factorToBase: 1e-9),
    Unit(id: 'micro', symbol: 'µ (10^-6)', factorToBase: 1e-6),
    Unit(id: 'milli', symbol: 'm (10^-3)', factorToBase: 1e-3),
    Unit(id: 'base', symbol: '(none)', factorToBase: 1),
    Unit(id: 'kilo', symbol: 'k (10^3)', factorToBase: 1e3),
    Unit(id: 'mega', symbol: 'M (10^6)', factorToBase: 1e6),
    Unit(id: 'giga', symbol: 'G (10^9)', factorToBase: 1e9),
    Unit(id: 'tera', symbol: 'T (10^12)', factorToBase: 1e12),
  ];

  // ─── Speed ─────────────────────────────────────────────────────────────────
  // Base: meter per second. m/s, km/h, mph, ft/s, knots.
  static const List<Unit> speedUnits = <Unit>[
    Unit(id: 'mps', symbol: 'm/s', factorToBase: 1),
    Unit(id: 'kmh', symbol: 'km/h', factorToBase: 1000 / 3600),
    Unit(id: 'mph', symbol: 'mph', factorToBase: 1609.344 / 3600),
    Unit(id: 'fps', symbol: 'ft/s', factorToBase: 0.3048),
    Unit(id: 'knot', symbol: 'knot', factorToBase: 1852 / 3600),
  ];

  // ─── Temperature ─────────────────────────────────────────────────────────────
  // AFFINE, not multiplicative — handled by [_tempToKelvin] / [_tempFromKelvin].
  // Base: Kelvin. factorToBase is a sentinel 0 and unused (nonLinear).
  static const List<Unit> temperatureUnits = <Unit>[
    Unit(id: 'c', symbol: '°C', factorToBase: 0, nonLinear: true),
    Unit(id: 'f', symbol: '°F', factorToBase: 0, nonLinear: true),
    Unit(id: 'k', symbol: 'K', factorToBase: 0, nonLinear: true),
  ];

  // ─── Time ──────────────────────────────────────────────────────────────────
  // Base: second.
  static const List<Unit> timeUnits = <Unit>[
    Unit(id: 'ns', symbol: 'ns', factorToBase: 1e-9),
    Unit(id: 'us', symbol: 'µs', factorToBase: 1e-6),
    Unit(id: 'ms', symbol: 'ms', factorToBase: 1e-3),
    Unit(id: 's', symbol: 's', factorToBase: 1),
    Unit(id: 'min', symbol: 'min', factorToBase: 60),
    Unit(id: 'hr', symbol: 'hr', factorToBase: 3600),
    Unit(id: 'day', symbol: 'day', factorToBase: 86400),
    Unit(id: 'week', symbol: 'week', factorToBase: 604800),
  ];

  /// The unit list for [category], in display order.
  static List<Unit> unitsFor(UnitCategory category) {
    switch (category) {
      case UnitCategory.dataRate:
        return dataRateUnits;
      case UnitCategory.dataStorage:
        return dataStorageUnits;
      case UnitCategory.length:
        return lengthUnits;
      case UnitCategory.power:
        return powerUnits;
      case UnitCategory.metricPrefix:
        return metricPrefixUnits;
      case UnitCategory.speed:
        return speedUnits;
      case UnitCategory.temperature:
        return temperatureUnits;
      case UnitCategory.time:
        return timeUnits;
    }
  }

  // ─── Non-linear helpers ─────────────────────────────────────────────────────

  /// Power: convert a value in unit [u] to WATTS (the power base).
  /// dBm uses W = 10^(dBm/10) / 1000 — the SAME formula as dbm_watt_converter
  /// (`_dbmToWatts`); linear members use their factor.
  static double _powerToWatts(double value, Unit u) {
    if (u.id == 'dbm') return math.pow(10, value / 10).toDouble() / 1000.0;
    return value * u.factorToBase;
  }

  /// Power: convert WATTS to unit [u]. dBm uses dBm = 10*log10(W*1000) — the
  /// SAME formula as dbm_watt_converter (`_wattsTodBm`). Watts ≤ 0 → NaN for
  /// dBm (log of a non-positive number is undefined), surfaced as "—".
  static double _powerFromWatts(double watts, Unit u) {
    if (u.id == 'dbm') {
      if (watts <= 0) return double.nan;
      return 10 * (math.log(watts * 1000) / math.ln10);
    }
    return watts / u.factorToBase;
  }

  /// Temperature: convert [value] in unit [u] to KELVIN.
  static double _tempToKelvin(double value, Unit u) {
    switch (u.id) {
      case 'c':
        return value + 273.15;
      case 'f':
        return (value - 32) * 5 / 9 + 273.15;
      case 'k':
        return value;
      default:
        throw ArgumentError('not a temperature unit: ${u.id}');
    }
  }

  /// Temperature: convert KELVIN to unit [u].
  static double _tempFromKelvin(double kelvin, Unit u) {
    switch (u.id) {
      case 'c':
        return kelvin - 273.15;
      case 'f':
        return (kelvin - 273.15) * 9 / 5 + 32;
      case 'k':
        return kelvin;
      default:
        throw ArgumentError('not a temperature unit: ${u.id}');
    }
  }

  /// Convert [value] from [from] to [to] within [category].
  ///
  /// Routes:
  ///   * temperature → affine to/from Kelvin (offset + scale).
  ///   * power → to/from watts, with dBm via the log/antilog pair.
  ///   * everything else → the shared linear factor pivot
  ///     (value * from.factorToBase / to.factorToBase).
  ///
  /// Returns NaN where the conversion is undefined (e.g. a non-positive watt
  /// value converted to dBm) so the UI can render an honest "—".
  static double convert(
    double value,
    UnitCategory category,
    Unit from,
    Unit to,
  ) {
    switch (category) {
      case UnitCategory.temperature:
        return _tempFromKelvin(_tempToKelvin(value, from), to);
      case UnitCategory.power:
        return _powerFromWatts(_powerToWatts(value, from), to);
      default:
        // Linear pivot. A non-linear unit must never reach here.
        assert(
          !from.nonLinear && !to.nonLinear,
          'linear convert reached a non-linear unit',
        );
        final double base = value * from.factorToBase;
        return base / to.factorToBase;
    }
  }

  /// Format a result for display. General-purpose tool, so no per-unit decimal
  /// table (the distance tool had one): use a compact, lossless-ish format that
  /// keeps small and large magnitudes readable.
  ///   * non-finite → "—".
  ///   * |v| ≥ 1e12 or (0 < |v| < 1e-4) → scientific (6 sig-fig) — readable for
  ///     RF watt levels and multi-terabyte sizes.
  ///   * otherwise → up to 6 significant figures, trailing zeros trimmed.
  static String formatResult(double v) {
    if (!v.isFinite) return '—';
    if (v == 0) return '0';
    final double mag = v.abs();
    if (mag >= 1e12 || mag < 1e-4) {
      return v.toStringAsExponential(5);
    }
    // 6 significant figures, then trim trailing zeros / a dangling dot.
    String s = v.toStringAsPrecision(6);
    if (s.contains('.') && !s.contains('e')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
}
