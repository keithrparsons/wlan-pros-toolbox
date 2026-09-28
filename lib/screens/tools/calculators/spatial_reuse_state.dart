// State for the Wi-Fi Classroom Spatial Reuse simulator (spatial-reuse).
//
// One ChangeNotifier holds the scenario and caches its analysis. The stage
// and the controls never talk to each other, only to this object, so a phone
// can stack them and a presenter layout can put them side by side (spec 00).
// The numbers come from services/wifi_lab/spatial_reuse_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/spatial_reuse_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kSpatialReuseToolId = 'spatial-reuse';

/// Length of the line the four radios sit on, metres.
const double kReuseLineM = 60;

/// The four radios, in the order the stage and controls list them.
enum ReuseNode {
  apA('AP A', 'A', isAp: true, bssA: true),
  clientA('Client A', 'a', isAp: false, bssA: true),
  clientB('Client B', 'b', isAp: false, bssA: false),
  apB('AP B', 'B', isAp: true, bssA: false);

  const ReuseNode(
    this.label,
    this.glyph, {
    required this.isAp,
    required this.bssA,
  });

  final String label;

  /// The letter drawn in the node.
  final String glyph;
  final bool isAp;

  /// Belongs to BSS A (else BSS B).
  final bool bssA;
}

class SpatialReuseState extends ChangeNotifier {
  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. Positions stay in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  ReuseScenario _s = const ReuseScenario();
  ReuseAnalysis? _analysis;

  ReuseScenario get scenario => _s;
  ReuseAnalysis get analysis => _analysis ??= ReuseAnalysis.of(_s);

  double position(ReuseNode n) => switch (n) {
    ReuseNode.apA => _s.layout.apA,
    ReuseNode.clientA => _s.layout.clientA,
    ReuseNode.clientB => _s.layout.clientB,
    ReuseNode.apB => _s.layout.apB,
  };

  void _set(ReuseScenario s) {
    _s = s;
    _analysis = null;
    notifyListeners();
  }

  /// Move [n] to [metres] on the line, rounded to 0.5 m, or to a whole
  /// foot in imperial.
  void move(ReuseNode n, double metres) {
    final double c = metres.clamp(0, kReuseLineM).toDouble();
    final double m = _units.isMetric
        ? (c * 2).round() / 2
        : LengthUnits.feetToMetres(
            LengthUnits.metresToFeet(c).roundToDouble(),
          ).clamp(0, kReuseLineM).toDouble();
    final ReuseLayout l = _s.layout;
    _set(
      _s.copyWith(
        layout: switch (n) {
          ReuseNode.apA => l.copyWith(apA: m),
          ReuseNode.clientA => l.copyWith(clientA: m),
          ReuseNode.clientB => l.copyWith(clientB: m),
          ReuseNode.apB => l.copyWith(apB: m),
        },
      ),
    );
  }

  void setObssPd(double v) =>
      _set(_s.copyWith(obssPdDbm: clampObssPd(v.roundToDouble())));
  void setColoring(bool v) => _set(_s.copyWith(coloring: v));
  void setColorA(int v) =>
      _set(_s.copyWith(colorA: v.clamp(kMinBssColor, kMaxBssColor)));
  void setColorB(int v) =>
      _set(_s.copyWith(colorB: v.clamp(kMinBssColor, kMaxBssColor)));
  void setWidth(int v) => _set(_s.copyWith(widthMHz: v));
  void setTxPwrRef(TxPwrRefClass v) => _set(_s.copyWith(txPwrRef: v));
  void setApPower(double v) => _set(_s.copyWith(apPowerDbm: v.roundToDouble()));
  void setExponent(double v) =>
      _set(_s.copyWith(exponent: (v * 10).round() / 10));
  void setMcsA(int v) => _set(_s.copyWith(mcsA: v.clamp(0, kReuseMaxMcs)));
  void setMcsB(int v) => _set(_s.copyWith(mcsB: v.clamp(0, kReuseMaxMcs)));
  void reset() => _set(const ReuseScenario());

  /// OBSS_PD one step from the keyboard. Does nothing with coloring off,
  /// where the slider is disabled too.
  void nudgeObssPd(double delta) {
    if (!_s.coloring) return;
    setObssPd(_s.obssPdDbm + delta);
  }

  /// Presenter keys: Up and Down move OBSS_PD 1 dB, R resets the scenario.
  /// Nothing runs on a clock, so there is no play or step.
  PresenterActions get presenterActions => PresenterActions(
    reset: reset,
    sliderDown: () => nudgeObssPd(-1),
    sliderUp: () => nudgeObssPd(1),
    sliderLabel: 'OBSS_PD',
  );

  /// Plain-text summary for the Copy action.
  String copyText() {
    final ReuseAnalysis a = analysis;
    final ReuseScenario s = _s;
    String db(double v) => v.toStringAsFixed(1);
    String pos(double m) =>
        LengthFormat(_units).dist(m, decimals: 1, keepZeros: true);
    String link(String name, ReuseLink k) =>
        '$name: signal ${db(k.signalDbm)} dBm, '
        '${k.interferenceDbm == null ? 'no interference' : 'interference ${db(k.interferenceDbm!)} dBm'}, '
        'SINR ${db(k.sinrDb)} dB (SNR alone ${db(k.snrDb)} dB), '
        'best ${k.bestMcs == null ? 'no MCS' : mcsLabel(k.bestMcs!)}, '
        '${k.holds ? 'holds' : 'does not hold'} MCS ${k.targetMcs} '
        '(needs ${db(k.requiredSnrDb)} dB)';
    return <String>[
      'Spatial Reuse (Wi-Fi Classroom)',
      'AP A ${pos(s.layout.apA)}, client A ${pos(s.layout.clientA)}, '
          'client B ${pos(s.layout.clientB)}, AP B ${pos(s.layout.apB)}; '
          'n ${s.exponent.toStringAsFixed(1)}, ${s.widthMHz} MHz, '
          'AP power ${db(s.apPowerDbm)} dBm',
      s.coloring
          ? 'BSS coloring on: BSS A color ${s.colorA}, BSS B color ${s.colorB}; '
                'OBSS_PD ${db(s.obssPdDbm)} dBm per 20 MHz; '
                'TX_PWRref ${s.txPwrRef.short} (single source)'
          : 'BSS coloring off (legacy)',
      'AP B hears AP A at ${db(a.heardByBDbm)} dBm per 20 MHz',
      'Decision: ${a.together ? 'AP B sends at the same time' : 'AP B waits'} '
          '(${a.decision.rule.label})',
      'AP B transmit power: ${db(a.txPowerBDbm)} dBm',
      link('Link A', a.linkA),
      link('Link B', a.linkB),
      'Airtime for one frame each: ${a.frameTimes} frame-time'
          '${a.frameTimes == 1 ? '' : 's'}',
      'MCS: SNR each MCS needs = minimum sensitivity (conformance floor) '
          'minus the noise floor with a 7 dB noise figure.',
      'SRG and parameterized spatial reuse are out of scope.',
    ].join('\n');
  }
}
