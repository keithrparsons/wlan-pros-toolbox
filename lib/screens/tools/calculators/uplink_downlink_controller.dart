// State for the Wi-Fi Classroom Uplink vs Downlink tool (uplink-downlink).
//
// One ChangeNotifier over an immutable UdConfig (the pure model in
// lib/services/wifi_lab/uplink_downlink_model.dart), shared by the stage and
// the controls so the two lay out independently: stacked on a phone, side by
// side on a wide window, and in the full-screen presenter layout, which uses
// this same object (state is shared, not copied).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/uplink_downlink_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

export '../../../services/wifi_lab/uplink_downlink_model.dart';

class UplinkDownlinkController extends ChangeNotifier {
  UplinkDownlinkController([UdConfig initial = const UdConfig()])
    : _config = initial;

  UdConfig _config;

  /// Bearing of the client from the AP, radians, 0 = east, clockwise. Only
  /// where the dot is drawn; the physics depends on distance alone.
  double _clientAngle = -math.pi / 5;

  bool _revealed = false;
  int _revision = 0;

  UdConfig get config => _config;
  double get clientAngle => _clientAngle;

  /// Whether the predict-then-reveal answer is showing.
  bool get revealed => _revealed;

  /// Bumped on every change that alters what the stage draws.
  int get revision => _revision;

  /// The link as it was before "turn AP down to match", or null.
  UdConfig? get beforeMatch => _config.isMatched ? _config.beforeMatch : null;

  /// The nice view ranges the stage steps through, m. Each halves to a round
  /// number, since the stage labels the half-way circle too.
  static const List<double> viewRanges = <double>[
    10,
    20,
    30,
    50,
    80,
    100,
    150,
    200,
    300,
    500,
    800,
    1000,
    1500,
    2000,
    3000,
    5000,
  ];

  /// Meters from the AP to the stage edge: the next nice range past the
  /// larger ring (and, while a match is shown, past the downlink ring as it
  /// was before), so the two rings always fill the view and the ring that
  /// "turn AP down to match" shrinks is seen shrinking. The range moves in
  /// nice steps only, so small slider moves leave it alone.
  double get viewRangeM => viewRangeFor(_config);

  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  /// Switches units. The view range steps through round feet in imperial,
  /// so the client is pulled inside it as on any other change.
  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    _set(_config);
  }

  double viewRangeFor(UdConfig c) {
    double far = math.max(c.downlinkRingM, c.uplinkRingM);
    if (c.isMatched) far = math.max(far, c.beforeMatch.downlinkRingM);
    far *= 1.12;
    return NiceTicks.viewRange(far, _units, viewRanges);
  }

  void _set(UdConfig next) {
    // The client never sits off the stage.
    _config = next.withClientDistance(
      math.min(next.clientDistanceM, viewRangeFor(next)),
    );
    _revision++;
    notifyListeners();
  }

  void setBand(WifiBand b) => _set(_config.withBand(b));
  void setWidth(int w) => _set(_config.withWidth(w));
  void setPreset(UdPreset p) => _set(_config.withPreset(p));
  void setApTx(double v) => _set(_config.withApTx(v));
  void setClientTx(double v) => _set(_config.withClientTx(v));
  void setApGain(double v) => _set(_config.withApGain(v));
  void setClientGain(double v) => _set(_config.withClientGain(v));
  void setExponent(double v) => _set(_config.withExponent(v));
  void setClientDistance(double d) => _set(_config.withClientDistance(d));

  /// Places the client from a drag: distance and bearing.
  void setClientPolar(double distanceM, double angle) {
    _clientAngle = angle;
    setClientDistance(distanceM);
  }

  void matchApToClient() => _set(_config.matchApToClient());
  void undoMatch() => _set(_config.undoMatch());

  /// The one match control: match when possible, put back when matched.
  void toggleMatch() => _config.isMatched ? undoMatch() : matchApToClient();

  void setRevealed(bool v) {
    _revealed = v;
    _revision++;
    notifyListeners();
  }

  void toggleReveal() => setRevealed(!_revealed);

  /// Moves the client into the asymmetry zone, when there is one.
  void moveClientIntoZone() {
    final double? d = _config.zoneMiddleM;
    if (d != null) setClientDistance(d);
  }

  /// Back to the defaults (the client keeps its place, the answer hides).
  void reset() {
    _revealed = false;
    _set(_config.reset());
  }

  /// Presenter keyboard. Nothing animates, so there is no play or step. Up
  /// and Down move the client out and in along its bearing, a quarter of a
  /// doubling at a time; R resets; P reveals the answer; M turns the AP down
  /// to match and puts it back.
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () => setClientDistance(_config.clientDistanceM / _keyStep),
    sliderUp: () => setClientDistance(_config.clientDistanceM * _keyStep),
    sliderLabel: 'Client distance',
    reset: reset,
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Show or hide the prediction answer',
        onPressed: toggleReveal,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyM,
        keyLabel: 'M',
        description: 'Turn AP down to match, or put it back',
        onPressed: toggleMatch,
      ),
    ],
  );

  /// 2^(1/4): four presses double or halve the distance.
  static final double _keyStep = math.pow(2, 0.25).toDouble();

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final UdConfig c = _config;
    final String Function(double, [int]) n = UdFormat.n;
    final UdDirection dl = c.downlink;
    final UdDirection ul = c.uplink;
    final StringBuffer b = StringBuffer()
      ..writeln('Uplink vs Downlink')
      ..writeln(
        '${c.band.label} ch ${c.channel} (${c.freqMHz.round()} MHz), '
        '${c.widthMHz} MHz, path-loss exponent ${n(c.exponent)}, '
        'rule: ${c.preset.short}',
      )
      ..writeln(
        'AP ${n(c.apTxDbm)} dBm + ${n(c.apGainDbi, 0)} dBi = '
        '${n(c.apEirpDbm)} dBm EIRP; client ${n(c.clientTxEffectiveDbm)} dBm '
        '+ ${n(c.clientGainDbi, 0)} dBi = ${n(c.clientEirpDbm)} dBm EIRP '
        '(illustrative values)',
      )
      ..writeln(
        'Client at ${UdFormat.dist(c.clientDistanceM, _units)}: downlink '
        '${UdFormat.dbm(dl.rssiDbm)}, ${UdFormat.mcs(dl.mcs)}; uplink '
        '${UdFormat.dbm(ul.rssiDbm)}, ${UdFormat.mcs(ul.mcs)}',
      )
      ..writeln(
        'Imbalance ${n(c.imbalanceDb)} dB. Client decodes AP to '
        '${UdFormat.dist(c.downlinkRingM, _units)}; AP decodes client to '
        '${UdFormat.dist(c.uplinkRingM, _units)}; asymmetry zone '
        '${UdFormat.dist(c.asymmetryZoneM, _units)} wide',
      );
    final UdConfig? before = beforeMatch;
    if (before != null) b.writeln(udMatchSummary(before, c, _units));
    return b.toString().trimRight();
  }
}
