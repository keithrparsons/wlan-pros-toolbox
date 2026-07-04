import 'package:flutter/services.dart';

/// Locale-flexible decimal input helpers.
///
/// Comma-decimal locales (most of the EU) type `0,95` where en-US types
/// `0.95`. Before this util the calculator fields (a) filtered the comma out
/// as a dead key and (b) fed the raw string straight to `double.tryParse`,
/// which only understands `.` — so EU users could not enter decimals at all,
/// or silently got a wrong answer. These helpers are purely *additive*: they
/// accept the comma in addition to everything already allowed, then normalize
/// it to `.` at parse time. A period-locale user cannot regress — every input
/// that parsed before still parses to the same value.
///
/// Scope is INPUT ONLY. Output formatting (`toStringAsFixed`, etc.) is
/// deliberately untouched here.

/// Digits + `.` + `,` — positive-only decimal fields.
final List<TextInputFormatter> unsignedDecimalFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

/// Digits + `.` + `,` + leading `-` — fields that accept negatives
/// (coordinates, dBm, tilt).
final List<TextInputFormatter> signedDecimalFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
];

/// Digits + `.` + `,` + scientific/sign chars — fields that accept a pasted
/// exponent form like `1.5e3`.
final List<TextInputFormatter> scientificDecimalFormatters =
    <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,eE+\-]')),
    ];

/// Parse a decimal string that may use a comma as the decimal separator.
///
/// - Trims; empty → `null`.
/// - Replaces `,` with `.` so comma-decimal locales parse correctly.
/// - Ambiguity guard: if more than one `.` remains after replacement, returns
///   `null`. This rejects grouped/garbled input like `1,234,5` or `1.2.3`.
///   Grouping separators were never supported and still aren't — safe here
///   because these fields take small, ungrouped magnitudes.
/// - Then delegates to `double.tryParse`, so scientific notation (`1,5e3` →
///   `1.5e3` → 1500.0) and signed values (`-3,5` → -3.5) still work.
double? tryParseFlexibleDouble(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final String normalized = trimmed.replaceAll(',', '.');
  // Reject grouped/ambiguous input: more than one decimal point.
  if ('.'.allMatches(normalized).length > 1) return null;
  return double.tryParse(normalized);
}
