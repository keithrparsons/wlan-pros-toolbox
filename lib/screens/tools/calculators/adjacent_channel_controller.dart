// State for the Wi-Fi Classroom Adjacent Channels and AP Stacking tool
// (adjacent-channel).
//
// One ChangeNotifier holds the configuration, the computed result and the
// opening question, so the stage and the controls lay out independently
// (stacked on a phone, side by side on a computer, and the presenter layout)
// over the SAME object. All math is in
// lib/services/wifi_lab/adjacent_channel_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kAdjacentChannelToolId = 'adjacent-channel';

/// The student's answer to the opening question.
enum AciPrediction { problem, noProblem }

/// The opening question's scene: two APs on 36 and 44, 30 cm apart, the
/// listening AP hearing its own client 10 m away (the scene Pax worked in
/// the 2026-09-27 rejection check).
const AciConfig kAciQuestionScene = AciConfig(
  band: WifiBand.band5,
  family: AciMaskFamily.heEht,
  neighborWidthMHz: 20,
  separation: AciSeparation.oneGap,
  listener: AciListener.ap,
  neighborDistanceM: 0.3,
  wantedDistanceM: 10,
);

/// Number formatting shared by stage and controls.
abstract final class AciFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String db(double v) => '${n(v)} dB';
  static String dbm(double v) => '${n(v)} dBm';
  static String dbr(double v) => '${n(v)} dBr';

  /// A distance in [u]: whole cm under a metre, tenths of a metre under 10,
  /// else whole metres; imperial whole inches under a foot, tenths of a foot
  /// under 10 ft, else whole feet.
  static String dist(double d, [UnitSystem u = UnitSystem.metric]) {
    if (u.isMetric) {
      if (d < 1) return '${(d * 100).round()} cm';
      if (d < 10) return '${d.toStringAsFixed(1)} m';
      return '${d.round()} m';
    }
    final double ft = LengthUnits.metresToFeet(d);
    if (ft < 1) return '${LengthUnits.metresToInches(d).round()} in';
    if (ft < 10) return '${ft.toStringAsFixed(1)} ft';
    return '${ft.round()} ft';
  }

  static String mcs(int? m) => m == null ? 'below MCS 0' : 'MCS $m';

  /// "MCS 7" or "Below MCS 0", capitalized for a headline.
  static String mcsHeadline(int? m) => m == null ? 'Below MCS 0' : 'MCS $m';
}

class AdjacentChannelController extends ChangeNotifier {
  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  /// [AciFormat.dist] in the current units.
  String dist(double d) => AciFormat.dist(d, _units);

  AdjacentChannelController({AciConfig? initial})
    : _config = initial ?? const AciConfig() {
    _result = computeAci(_config);
  }

  AciConfig _config;
  late AciResult _result;
  AciPrediction? _prediction;
  bool _revealed = false;

  AciConfig get config => _config;
  AciResult get result => _result;
  AciChannelPlan get plan => _result.plan;
  AciPrediction? get prediction => _prediction;
  bool get revealed => _revealed;

  /// Widths the neighbor may use: the band's widths the mask family has a
  /// table for. 2.4 GHz is held to 20 MHz (its presets are 20 MHz plans).
  List<int> get widths => <int>[
    for (final int w in _config.band.widthsMHz)
      if (_config.family.widthsMHz.contains(w) &&
          (_config.band != WifiBand.band24 || w == 20))
        w,
  ];

  /// The OFDM (802.11a/g) mask is 20 MHz only, and there is no OFDM (a/g)
  /// transmitter in 6 GHz.
  List<AciMaskFamily> get families => <AciMaskFamily>[
    if (_config.band != WifiBand.band6 && _config.neighborWidthMHz == 20)
      AciMaskFamily.ofdm,
    AciMaskFamily.heEht,
  ];

  List<AciSeparation> get separations => AciSeparation.forBand(_config.band);

  void _apply(AciConfig next) {
    _config = next;
    _result = computeAci(next);
    notifyListeners();
  }

  // ── Channel choice ────────────────────────────────────────────────────────

  set band(WifiBand b) {
    if (b == _config.band) return;
    final List<AciSeparation> seps = AciSeparation.forBand(b);
    final AciMaskFamily family = b == WifiBand.band6
        ? AciMaskFamily.heEht
        : _config.family;
    final int width = b == WifiBand.band24
        ? 20
        : (b.widthsMHz.contains(_config.neighborWidthMHz)
              ? _config.neighborWidthMHz
              : 20);
    final AciSeparation sep = seps.contains(_config.separation)
        ? _config.separation
        : (b == WifiBand.band24 ? AciSeparation.ch1and6 : AciSeparation.oneGap);
    _apply(
      _config.copyWith(
        band: b,
        family: family,
        neighborWidthMHz: width,
        separation: sep,
      ),
    );
  }

  set family(AciMaskFamily f) {
    if (!families.contains(f) || f == _config.family) return;
    _apply(_config.copyWith(family: f));
  }

  set neighborWidthMHz(int w) {
    if (!widths.contains(w) || w == _config.neighborWidthMHz) return;
    _apply(_config.copyWith(neighborWidthMHz: w));
  }

  set separation(AciSeparation s) {
    if (!separations.contains(s) || s == _config.separation) return;
    _apply(_config.copyWith(separation: s));
  }

  set listener(AciListener l) {
    if (l == _config.listener) return;
    _apply(_config.copyWith(listener: l));
  }

  // ── Power and distance ────────────────────────────────────────────────────

  set neighborDistanceM(double d) => _apply(
    _config.copyWith(
      neighborDistanceM: d.clamp(
        AciLimits.neighborDistanceMin,
        AciLimits.neighborDistanceMax,
      ),
    ),
  );

  set neighborPowerDbm(double v) => _apply(
    _config.copyWith(
      neighborPowerDbm: v.clamp(AciLimits.powerMin, AciLimits.powerMax),
    ),
  );

  set wantedDistanceM(double d) => _apply(
    _config.copyWith(
      wantedDistanceM: d.clamp(
        AciLimits.wantedDistanceMin,
        AciLimits.wantedDistanceMax,
      ),
    ),
  );

  set wantedPowerDbm(double v) => _apply(
    _config.copyWith(
      wantedPowerDbm: v.clamp(AciLimits.powerMin, AciLimits.powerMax),
    ),
  );

  set pathLossExponent(double v) => _apply(
    _config.copyWith(
      pathLossExponent: v.clamp(AciLimits.exponentMin, AciLimits.exponentMax),
    ),
  );

  // ── Receiver ──────────────────────────────────────────────────────────────

  /// Sets the selectivity for the current separation (next channel, or one
  /// gap or more); the other keeps its value.
  set selectivityDb(double db) => _apply(
    _config.withSelectivity(
      db.clamp(AciLimits.selectivityMin, AciLimits.selectivityMax),
    ),
  );

  set ccaThresholdDbm(double v) => _apply(
    _config.copyWith(
      ccaThresholdDbm: v.clamp(AciLimits.ccaMin, AciLimits.ccaMax),
    ),
  );

  /// Back to the defaults. The opening question keeps its answer.
  void reset() => _apply(const AciConfig());

  // ── Predict, then reveal ──────────────────────────────────────────────────

  set prediction(AciPrediction? p) {
    if (p == _prediction) return;
    _prediction = p;
    notifyListeners();
  }

  /// Loads the question's scene and shows the answer.
  void reveal() {
    _revealed = true;
    _apply(kAciQuestionScene);
  }

  void askAgain() {
    _prediction = null;
    _revealed = false;
    notifyListeners();
  }

  // ── Presenter keyboard ────────────────────────────────────────────────────

  /// 2^(1/4): four presses double or halve the neighbor distance.
  static final double _keyStep = math.pow(2, 0.25).toDouble();

  /// Nothing animates, so there is no play or step. Up moves the neighbor
  /// away, Down brings it closer; R resets.
  PresenterActions get presenterActions => PresenterActions(
    reset: reset,
    sliderDown: () => neighborDistanceM = _config.neighborDistanceM / _keyStep,
    sliderUp: () => neighborDistanceM = _config.neighborDistanceM * _keyStep,
    sliderLabel: 'Neighbor distance',
  );

  // ── Copy payload (GL-003 §8.16) ───────────────────────────────────────────

  String copyText() {
    final AciResult r = _result;
    final AciConfig c = _config;
    final AciChannelPlan p = r.plan;
    final String Function(double, [int]) n = AciFormat.n;
    final StringBuffer b = StringBuffer()
      ..writeln('Adjacent Channels and AP Stacking')
      ..writeln(
        '${c.band.label}: neighbor ${p.neighborLabel}, ${p.neighborWidthMHz} '
        'MHz, ${c.family.label} mask; listening on ${p.receiverLabel} '
        '(${n(p.spacingMHz, 0)} MHz center to center)',
      )
      ..writeln(
        '${c.listener.receiverName} listens. Neighbor ${n(c.neighborPowerDbm, 0)} '
        'dBm at ${dist(c.neighborDistanceM)}; '
        '${c.listener.wantedName} ${n(c.wantedPowerDbm, 0)} dBm at '
        '${dist(c.wantedDistanceM)}; path-loss exponent '
        '${n(c.pathLossExponent)}',
      )
      ..writeln(
        'Wanted ${AciFormat.dbm(r.wantedDbm)}, neighbor in its own channel '
        '${AciFormat.dbm(r.neighborDbm)}, noise ${AciFormat.dbm(r.receiverNoiseDbm)}',
      )
      ..writeln(
        'Transmit mask at your center ${AciFormat.dbr(r.maskAtReceiverCenterDbr)}; '
        'integrated over your 20 MHz ${AciFormat.dbr(r.leakageDbr)} '
        '(worst case the mask allows)',
      )
      ..writeln(
        'Leakage in your 20 MHz ${AciFormat.dbm(r.leakageDbm)}; receiver '
        'selectivity ${n(r.selectivityDb, 0)} dB (illustrative) lets '
        '${AciFormat.dbm(r.filteredDbm)} of the neighbor channel through; '
        'effective interference ${AciFormat.dbm(r.effectiveInterferenceDbm)}',
      )
      ..writeln(
        'SIR ${AciFormat.db(r.sirDb)}, SINR ${AciFormat.db(r.sinrDb)}; CCA '
        '${n(c.ccaThresholdDbm, 0)} dBm: ${r.ccaBusy ? 'busy' : 'clear'}',
      )
      ..writeln(
        'Highest MCS: ${AciFormat.mcs(r.mcsWithout)} without the neighbor, '
        '${AciFormat.mcs(r.mcsWith)} with it',
      );
    return b.toString().trimRight();
  }
}
