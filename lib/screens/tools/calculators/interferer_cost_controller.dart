// State for the Wi-Fi Classroom tool What an Interferer Costs
// (interferer-cost).
//
// One ChangeNotifier holds the configuration, the computed result and the
// opening question, so the stage and the controls lay out independently
// (stacked on a phone, side by side on a computer, and the presenter layout)
// over the SAME object. All math is in
// lib/services/wifi_lab/interferer_cost_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/interferer_cost_model.dart'
    show kInterfererCostToolId;

/// The student's answer to the opening question.
enum IcPrediction { neighbor, microwave, same }

/// Number formatting shared by stage and controls.
abstract final class IcFormat {
  static String n(double v, [int decimals = 0]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String dbm(double v) => '${n(v)} dBm';

  /// A share of airtime as a percent: one decimal under 10%, else whole.
  static String pct(double share) {
    final double p = share * 100;
    if (p == 0) return '0%';
    if (p < 0.1) return 'under 0.1%';
    return p < 10 ? '${p.toStringAsFixed(1)}%' : '${p.round()}%';
  }

  /// "4.6x", "21.5x"; whole when within 0.05 of a whole number ("10x",
  /// "100x"), so the screen agrees with the help's figures.
  static String times(double x) => (x - x.round()).abs() < 0.05
      ? '${x.round()}x'
      : '${x.toStringAsFixed(1)}x';

  /// A distance in [u]: whole metres (or feet), tenths under 10; km or
  /// miles past 1,000 m (or 5,280 ft).
  static String dist(double m, [UnitSystem u = UnitSystem.metric]) {
    if (u.isMetric) {
      if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
      if (m < 10) return '${m.toStringAsFixed(1)} m';
      return '${m.round()} m';
    }
    final double ft = LengthUnits.metresToFeet(m);
    if (ft >= LengthUnits.feetPerMile) {
      return '${(ft / LengthUnits.feetPerMile).toStringAsFixed(1)} mi';
    }
    if (ft < 10) return '${ft.toStringAsFixed(1)} ft';
    return '${ft.round()} ft';
  }
}

class InterfererCostController extends ChangeNotifier {
  InterfererCostController({IcConfig? initial})
    : _config = initial ?? const IcConfig() {
    _result = computeInterfererCost(_config);
  }

  IcConfig _config;
  late IcResult _result;
  IcPrediction? _prediction;
  bool _revealed = false;
  UnitSystem _units = UnitSystem.metric;

  IcConfig get config => _config;
  IcResult get result => _result;
  IcPrediction? get prediction => _prediction;
  bool get revealed => _revealed;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  String dist(double m) => IcFormat.dist(m, _units);

  /// Widths offered: 20 to 160 in 5 GHz, 20 only in 2.4 GHz.
  List<int> get widths => _config.channel.is24 ? const <int>[20] : kIcWidthsMHz;

  void _apply(IcConfig next) {
    if (next == _config) return;
    _config = next;
    _result = computeInterfererCost(next);
    notifyListeners();
  }

  set source(IcSource s) => _apply(_config.copyWith(source: s));

  set channel(IcChannel c) => _apply(
    _config.copyWith(channel: c, widthMHz: c.is24 ? 20 : _config.widthMHz),
  );

  set widthMHz(int w) {
    if (!widths.contains(w)) return;
    _apply(_config.copyWith(widthMHz: w));
  }

  set mains(IcMains m) => _apply(_config.copyWith(mains: m));

  set exponent(double n) {
    if (!kIcExponents.contains(n)) return;
    _apply(_config.copyWith(exponent: n));
  }

  set neighborAirtime(double a) => _apply(
    _config.copyWith(
      neighborAirtime: a.clamp(kIcNeighborAirtimeMin, kIcNeighborAirtimeMax),
    ),
  );

  /// The selected source's level.
  double get level => _config.levelFor(_config.source);

  set level(double v) => _apply(_config.withLevel(_config.source, v));

  /// Back to the defaults. The opening question keeps its answer.
  void reset() => _apply(const IcConfig());

  void nextSource() => source =
      IcSource.values[(_config.source.index + 1) % IcSource.values.length];

  void nextChannel() => channel =
      IcChannel.values[(_config.channel.index + 1) % IcChannel.values.length];

  // ── Predict, then reveal ──────────────────────────────────────────────────

  set prediction(IcPrediction? p) {
    if (p == _prediction) return;
    _prediction = p;
    notifyListeners();
  }

  /// Loads the question's scene and shows the answer.
  void reveal() {
    _revealed = true;
    if (_config == kIcQuestionScene) {
      notifyListeners();
      return;
    }
    _apply(kIcQuestionScene);
  }

  void askAgain() {
    _prediction = null;
    _revealed = false;
    notifyListeners();
  }

  // ── Presenter keyboard ────────────────────────────────────────────────────

  /// Nothing animates, so there is no play or step. Up and Down move the
  /// selected source's level 1 dB; N picks the next source, C the next
  /// channel; R resets.
  PresenterActions get presenterActions => PresenterActions(
    reset: reset,
    sliderDown: () => level = level - 1,
    sliderUp: () => level = level + 1,
    sliderLabel: 'Interferer level',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyN,
        keyLabel: 'N',
        description: 'Next source',
        onPressed: nextSource,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Next channel',
        onPressed: nextChannel,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ───────────────────────────────────────────

  String copyText() {
    final IcResult r = _result;
    final IcConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln('What an Interferer Costs')
      ..writeln(
        'Your channel: ${c.channel.prose}, ${c.widthMHz} MHz. Preamble detect '
        '${IcFormat.dbm(r.preambleDetectDbm)} (other Wi-Fi), energy detect '
        '${IcFormat.dbm(r.energyDetectDbm)} (anything): a ${IcFormat.n(r.gapDb)} '
        'dB gap, ${IcFormat.times(r.gapPowerRatio)} the power.',
      )
      ..writeln(
        'A ${IcFormat.n(kIcReferenceEirpDbm)} dBm transmitter (illustrative), '
        'path-loss exponent ${c.exponent.toStringAsFixed(1)}: Wi-Fi makes you '
        'wait out to ${dist(r.wifiHeardAtM)}, non-Wi-Fi energy out to '
        '${dist(r.energyHeardAtM)} (${IcFormat.times(r.distanceRatio)} the '
        'distance).',
      );
    for (final IcSource s in IcSource.values) {
      final IcSourceResult x = r.sources[s]!;
      if (x.heard == IcHeard.absent) {
        b.writeln('${s.label}: not on this band.');
        continue;
      }
      b.writeln(
        '${s.label}: ${IcFormat.dbm(x.levelInChannelDbm!)} in your channel, '
        '${_heardWords(x.heard)}; waiting ${IcFormat.pct(x.deferralShare)}, '
        'corrupted frames ${IcFormat.pct(x.corruptionShare)} (illustrative).',
      );
    }
    return b.toString().trimRight();
  }

  static String _heardWords(IcHeard h) => switch (h) {
    IcHeard.preamble => 'heard as Wi-Fi, your radio waits',
    IcHeard.energy => 'heard as energy, your radio waits',
    IcHeard.notHeard => 'not heard, your radio sends into it',
    IcHeard.absent => 'not on this band',
  };
}
