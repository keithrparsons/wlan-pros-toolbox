// Design targets for the Wi-Fi Classroom FSPL Simulator (fspl-simulator).
//
// Keith, 2026-09-27: "could we add the ability for the user to set their own
// levels for the Voice and Video - with a number and a 'label'. We have -67
// and -70 but others may want to emphasize something different."
//
// The dashed lines in the Received view are now user-editable: up to
// [kFsplMaxTargets] lines, each a dBm value and a short label. The defaults
// are still read from the Signal Thresholds tool (fsplDesignTargets in
// fspl_simulator_model.dart), so a teacher who never touches them sees the
// -67 voice and -70 HD video lines the Teacher's Guide exercises rely on.
//
// PERSISTENCE mirrors UnitSystemController (lib/units/unit_system.dart): one
// shared_preferences string key, loaded before the first frame in main.dart,
// and a read or write failure never blocks the tool (it stays on defaults).
// Only valid lines are written, so what loads is always drawable. Reset
// REMOVES the key rather than writing the defaults, so the defaults keep
// following the Signal Thresholds table.
//
// ASCII only, no em dashes (GL-004).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Most design-target lines the chart carries. Four keeps the labels legible
/// on a phone and in a stack when the values sit close together.
const int kFsplMaxTargets = 4;

/// Accepted design-target span, dBm. Weaker than -100 is below any Wi-Fi
/// receiver's sensitivity; stronger than -30 is a client beside the AP.
const double kFsplTargetMinDbm = -100;
const double kFsplTargetMaxDbm = -30;

/// Longest label accepted, characters, so a line's label stays one short
/// phrase on the chart.
const int kFsplTargetLabelMax = 24;

/// A horizontal design-target line.
@immutable
class FsplDesignTarget {
  const FsplDesignTarget(this.dbm, this.label);

  /// Level in dBm, at most one decimal.
  final double dbm;

  /// User label. May be empty; see [displayLabel].
  final String label;

  /// "-67" or "-67.5": whole values print whole.
  String get valueText => fsplTargetValueText(dbm);

  /// What the chart and legend print: "-67 dBm voice", or "-67 dBm" when the
  /// label is empty.
  String get displayLabel {
    final String l = label.trim();
    return l.isEmpty ? '$valueText dBm' : '$valueText dBm $l';
  }

  @override
  bool operator ==(Object other) =>
      other is FsplDesignTarget &&
      other.dbm == dbm &&
      other.label.trim() == label.trim();

  @override
  int get hashCode => Object.hash(dbm, label.trim());

  @override
  String toString() => 'FsplDesignTarget($displayLabel)';
}

/// "-67" for whole values, "-67.5" otherwise.
String fsplTargetValueText(double dbm) {
  final bool whole = dbm == dbm.roundToDouble();
  return dbm.toStringAsFixed(whole ? 0 : 1);
}

/// One editable line in the controls: what the user typed, kept as text so
/// a half-typed value ("-", "-6") can sit in the field with its error while
/// the chart keeps drawing the valid lines.
@immutable
class FsplTargetRow {
  const FsplTargetRow({
    required this.id,
    required this.valueText,
    required this.label,
  });

  /// Stable within a model's life, so text fields keep their controllers
  /// when a row above them is removed.
  final int id;
  final String valueText;
  final String label;

  FsplTargetRow copyWith({String? valueText, String? label}) => FsplTargetRow(
    id: id,
    valueText: valueText ?? this.valueText,
    label: label ?? this.label,
  );

  /// The parsed level, rounded to one decimal, or null when empty, not a
  /// number, or outside [kFsplTargetMinDbm]..[kFsplTargetMaxDbm].
  double? get dbm {
    final double? v = fsplParseTargetNumber(valueText);
    if (v == null || v < kFsplTargetMinDbm || v > kFsplTargetMaxDbm) {
      return null;
    }
    return (v * 10).roundToDouble() / 10;
  }

  /// The in-field error, or null when the value is valid.
  String? get error => dbm == null ? kFsplTargetError : null;

  /// The drawable line, or null while the value is invalid.
  FsplDesignTarget? get target {
    final double? v = dbm;
    return v == null ? null : FsplDesignTarget(v, label.trim());
  }
}

/// The one validation message, shown under the value field.
const String kFsplTargetError = 'Enter -100 to -30 dBm';

/// Accepts a comma decimal separator and the Unicode minus sign (same rules
/// as the measured-point fields).
double? fsplParseTargetNumber(String raw) {
  final String s = raw.trim().replaceAll(',', '.').replaceAll('−', '-');
  if (s.isEmpty) return null;
  final double? v = double.tryParse(s);
  return (v == null || !v.isFinite) ? null : v;
}

/// App-wide persisted design targets. One instance per process
/// ([instance]); main.dart loads it before the first frame.
class FsplTargetStore {
  FsplTargetStore();

  /// The process-wide store.
  static FsplTargetStore instance = FsplTargetStore();

  /// The shared_preferences key: a JSON list of {"dbm": n, "label": s}.
  static const String prefsKey = 'fspl_design_targets';

  bool _loaded = false;
  List<FsplDesignTarget>? _saved;

  /// True once [load] has finished (successfully or not).
  bool get isLoaded => _loaded;

  /// The saved lines, or null when nothing is saved (use the defaults).
  List<FsplDesignTarget>? get saved =>
      _saved == null ? null : List<FsplDesignTarget>.unmodifiable(_saved!);

  /// Loads the persisted lines once. Never throws: on any storage error, or a
  /// value it cannot read, it leaves [saved] null (defaults).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _saved = decode(prefs.getString(prefsKey));
    } catch (_) {
      _saved = null;
    }
    _loaded = true;
  }

  /// Saves [targets] (an empty list is a real choice: no lines). The
  /// in-memory copy updates first, so a failed write still applies for this
  /// session.
  Future<void> save(List<FsplDesignTarget> targets) async {
    _saved = List<FsplDesignTarget>.of(targets);
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, encode(targets));
    } catch (_) {
      // Persist failed: the in-memory copy still applies this session.
    }
  }

  /// Forgets the saved lines, so the defaults apply again.
  Future<void> clear() async {
    _saved = null;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {
      // Remove failed: the in-memory reset still applies this session.
    }
  }

  static String encode(List<FsplDesignTarget> targets) =>
      jsonEncode(<Map<String, Object>>[
        for (final FsplDesignTarget t in targets)
          <String, Object>{'dbm': t.dbm, 'label': t.label},
      ]);

  /// Null for a missing or unreadable value. Out-of-range or malformed
  /// entries are dropped, and at most [kFsplMaxTargets] are kept.
  static List<FsplDesignTarget>? decode(String? raw) {
    if (raw == null) return null;
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! List<Object?>) return null;
      final List<FsplDesignTarget> out = <FsplDesignTarget>[];
      for (final Object? e in parsed) {
        if (e is! Map<String, Object?>) continue;
        final Object? d = e['dbm'];
        final Object? l = e['label'];
        if (d is! num || l is! String) continue;
        final double v = d.toDouble();
        if (!v.isFinite || v < kFsplTargetMinDbm || v > kFsplTargetMaxDbm) {
          continue;
        }
        final String label = l.length > kFsplTargetLabelMax
            ? l.substring(0, kFsplTargetLabelMax)
            : l;
        out.add(FsplDesignTarget((v * 10).roundToDouble() / 10, label));
        if (out.length == kFsplMaxTargets) break;
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// A fresh, unloaded store in place of [instance]. Tests only.
  @visibleForTesting
  static void resetForTest() => instance = FsplTargetStore();
}
