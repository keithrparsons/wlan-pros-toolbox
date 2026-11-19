// RSSI scale: the one source of truth for every Wi-Fi signal grade in the app.
//
// Keith Parsons, 19 Nov 2026 (the master scale, replacing every earlier one):
//   Excellent  -66 dBm and stronger
//   Good       -67 to -72
//   Fair       -73 to -78
//   Poor       -79 to -84
//   Unusable   -85 and weaker
//
// These are Keith's DEFAULTS. There is no industry consensus
// on RSSI bands, so the user can move every boundary in the Signal Bands
// settings screen and reset to these defaults at any time. Nothing in the app
// may hardcode a band edge: the grading engine, the Signal Thresholds table,
// the Wi-Fi Info and Check My Connection grades, the Analyze verdicts and the
// triage ladder all read [RssiScaleStore.instance].
//
// A scale is four integer boundaries, each the inclusive weakest reading of
// a band (Excellent, Good, Fair, Poor). Unusable is everything weaker than the
// Poor boundary. Because the bands are defined by their edges, they are
// contiguous by construction: every integer reading falls in exactly one band,
// with no gaps and no overlaps. Validation only has to check that the
// boundaries are integers, inside [RssiScale.strongestAllowedDbm] and
// [RssiScale.weakestAllowedDbm], and strictly ordered strongest to weakest
// (which also keeps every band at least 1 dB wide).
//
// PERSISTENCE mirrors UnitSystemController and FsplTargetStore: one
// shared_preferences string key, loaded before the first frame in main.dart.
// A read or write failure never blocks the app; it stays on the defaults.
// Reset REMOVES the key, so a user who resets follows any future change to
// the defaults.
//
// US spelling, no em dashes.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade;
import 'package:shared_preferences/shared_preferences.dart';

/// One RSSI grade band, as the reference table and help print it.
@immutable
class RssiBand {
  const RssiBand({
    required this.grade,
    required this.label,
    required this.minDbm,
    required this.displayRange,
  });

  /// The grade a reading in this band receives.
  final QualityGrade grade;

  /// "Excellent", "Good", "Fair", "Poor" or "Unusable".
  final String label;

  /// Inclusive weakest reading of the band, dBm. The Unusable band uses
  /// [RssiScale.noFloorDbm]: nothing grades weaker than Unusable.
  final int minDbm;

  /// The range as printed, for example "-67 to -72".
  final String displayRange;

  @override
  bool operator ==(Object other) =>
      other is RssiBand &&
      other.grade == grade &&
      other.label == label &&
      other.minDbm == minDbm &&
      other.displayRange == displayRange;

  @override
  int get hashCode => Object.hash(grade, label, minDbm, displayRange);
}

/// Which boundary a validation message belongs to.
enum RssiBoundary { excellent, good, fair, poor }

/// A five-band RSSI scale, defined by four integer boundaries.
@immutable
class RssiScale {
  const RssiScale({
    required this.excellentMinDbm,
    required this.goodMinDbm,
    required this.fairMinDbm,
    required this.poorMinDbm,
  });

  /// Keith Parsons' default scale (master scale, 19 Nov 2026).
  static const RssiScale defaults = RssiScale(
    excellentMinDbm: -66,
    goodMinDbm: -72,
    fairMinDbm: -78,
    poorMinDbm: -84,
  );

  /// Strongest boundary a user may set, dBm (a client next to the AP).
  static const int strongestAllowedDbm = -30;

  /// Weakest boundary a user may set, dBm (below any Wi-Fi receiver).
  static const int weakestAllowedDbm = -100;

  /// Sentinel floor for the Unusable band.
  static const int noFloorDbm = -1000;

  /// Readings at or above this grade Excellent.
  final int excellentMinDbm;

  /// Readings at or above this, below Excellent, grade Good.
  final int goodMinDbm;

  /// Readings at or above this, below Good, grade Fair.
  final int fairMinDbm;

  /// Readings at or above this, below Fair, grade Poor. Weaker is Unusable.
  final int poorMinDbm;

  /// The four boundaries, strongest first.
  List<int> get boundaries => <int>[
    excellentMinDbm,
    goodMinDbm,
    fairMinDbm,
    poorMinDbm,
  ];

  /// True when this is [defaults].
  bool get isDefault => this == defaults;

  /// Grades [rssiDbm]. Null is [QualityGrade.unavailable], never a guess.
  QualityGrade grade(int? rssiDbm) {
    if (rssiDbm == null) return QualityGrade.unavailable;
    for (final RssiBand band in bands) {
      if (rssiDbm >= band.minDbm) return band.grade;
    }
    return QualityGrade.unusable; // unreachable: Unusable has no floor.
  }

  /// The five bands, strongest first, with their printed ranges.
  List<RssiBand> get bands => <RssiBand>[
    RssiBand(
      grade: QualityGrade.excellent,
      label: 'Excellent',
      minDbm: excellentMinDbm,
      displayRange: '$excellentMinDbm dBm and stronger',
    ),
    RssiBand(
      grade: QualityGrade.good,
      label: 'Good',
      minDbm: goodMinDbm,
      displayRange: _span(excellentMinDbm - 1, goodMinDbm),
    ),
    RssiBand(
      grade: QualityGrade.fair,
      label: 'Fair',
      minDbm: fairMinDbm,
      displayRange: _span(goodMinDbm - 1, fairMinDbm),
    ),
    RssiBand(
      grade: QualityGrade.poor,
      label: 'Poor',
      minDbm: poorMinDbm,
      displayRange: _span(fairMinDbm - 1, poorMinDbm),
    ),
    RssiBand(
      grade: QualityGrade.unusable,
      label: 'Unusable',
      minDbm: noFloorDbm,
      displayRange: '${poorMinDbm - 1} and weaker',
    ),
  ];

  static String _span(int top, int bottom) =>
      top == bottom ? '$top' : '$top to $bottom';

  /// One line, for help text and copy: "Excellent -66 dBm and stronger,
  /// Good -67 to -72, Fair -73 to -78, Poor -79 to -84, Unusable -85 and
  /// weaker".
  String get summary => <String>[
    for (final RssiBand b in bands) '${b.label} ${b.displayRange}',
  ].join(', ');

  /// Checks four boundaries, strongest first. Returns one message per bad
  /// boundary (empty when valid). Null means the field is empty or not a
  /// whole number.
  static Map<RssiBoundary, String> validate(List<int?> boundaries) {
    assert(boundaries.length == 4, 'An RSSI scale has four boundaries.');
    final Map<RssiBoundary, String> errors = <RssiBoundary, String>{};
    for (int i = 0; i < 4; i++) {
      final RssiBoundary which = RssiBoundary.values[i];
      final int? v = boundaries[i];
      if (v == null) {
        errors[which] = 'Enter a whole number, for example -70';
        continue;
      }
      if (v > strongestAllowedDbm || v < weakestAllowedDbm) {
        errors[which] = 'Enter $weakestAllowedDbm to $strongestAllowedDbm dBm';
        continue;
      }
      if (i > 0) {
        final int? above = boundaries[i - 1];
        if (above != null && v >= above) {
          errors[which] = 'Must be weaker than $above';
        }
      }
    }
    return errors;
  }

  /// A scale from four boundaries, or null when [validate] finds a problem.
  static RssiScale? tryFrom(List<int?> boundaries) {
    if (boundaries.length != 4) return null;
    if (validate(boundaries).isNotEmpty) return null;
    return RssiScale(
      excellentMinDbm: boundaries[0]!,
      goodMinDbm: boundaries[1]!,
      fairMinDbm: boundaries[2]!,
      poorMinDbm: boundaries[3]!,
    );
  }

  /// Parses a typed boundary. Accepts the Unicode minus sign. Only whole
  /// numbers: "-70.5" and "abc" are null.
  static int? parseDbm(String raw) {
    final String s = raw.trim().replaceAll('\u2212', '-');
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  String encode() => jsonEncode(<String, int>{
    'excellent': excellentMinDbm,
    'good': goodMinDbm,
    'fair': fairMinDbm,
    'poor': poorMinDbm,
  });

  /// Null for a missing, unreadable or invalid value.
  static RssiScale? decode(String? raw) {
    if (raw == null) return null;
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, Object?>) return null;
      int? read(String k) {
        final Object? v = parsed[k];
        return v is int ? v : null;
      }

      return tryFrom(<int?>[
        read('excellent'),
        read('good'),
        read('fair'),
        read('poor'),
      ]);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RssiScale &&
      other.excellentMinDbm == excellentMinDbm &&
      other.goodMinDbm == goodMinDbm &&
      other.fairMinDbm == fairMinDbm &&
      other.poorMinDbm == poorMinDbm;

  @override
  int get hashCode =>
      Object.hash(excellentMinDbm, goodMinDbm, fairMinDbm, poorMinDbm);

  @override
  String toString() => 'RssiScale($summary)';
}

/// The app-wide RSSI scale: Keith's defaults plus the user's overrides. One
/// instance per process ([instance]); main.dart loads it before the first
/// frame. Listen to it to rebuild when the user changes a boundary.
class RssiScaleStore extends ValueNotifier<RssiScale> {
  RssiScaleStore() : super(RssiScale.defaults);

  /// The process-wide store.
  static RssiScaleStore instance = RssiScaleStore();

  /// The shared_preferences key: JSON {"excellent", "good", "fair", "poor"}.
  static const String prefsKey = 'rssi_scale_v1';

  /// True when the user has saved their own boundaries.
  bool get isCustom => !value.isDefault;

  /// Loads the saved scale, if any. Never throws; an unreadable or invalid
  /// saved value leaves the defaults in place.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final RssiScale? saved = RssiScale.decode(prefs.getString(prefsKey));
      if (saved != null) value = saved;
    } catch (_) {
      // Storage unavailable: stay on the defaults.
    }
  }

  /// Applies and saves [scale]. Listeners fire first, so a failed write
  /// still applies for this session.
  Future<void> save(RssiScale scale) async {
    value = scale;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (scale.isDefault) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, scale.encode());
      }
    } catch (_) {
      // Persist failed: the in-memory scale still applies this session.
    }
  }

  /// Restores Keith's defaults and forgets the saved scale.
  Future<void> reset() => save(RssiScale.defaults);

  /// A fresh store on the defaults in place of [instance]. Tests only.
  @visibleForTesting
  static void resetForTest() {
    instance = RssiScaleStore();
  }
}
