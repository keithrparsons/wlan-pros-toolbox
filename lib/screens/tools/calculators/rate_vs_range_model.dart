// State for the Wi-Fi Lab Rate vs Range tool (rate-vs-range).
//
// One ChangeNotifier holds every input and derives every number the stage and
// the controls show, so the two lay out independently (stacked on a phone,
// side by side on desktop, and later a full-screen presenter layout) without
// either owning the other. All math is in
// lib/services/wifi_lab/rate_vs_range_math.dart; rate labels come from the
// MCS Index tool's table (McsIndexScreen.rate, 802.11be, 800 ns GI), never
// hand-copied here.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/rate_vs_range_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../reference/mcs_index_screen.dart';
import 'fspl_simulator_model.dart' show kFsplDefaultChannels;

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kRateVsRangeToolId = 'rate-vs-range';

/// One MCS ring at the current settings.
@immutable
class RvrRing {
  const RvrRing({
    required this.mcs,
    required this.sensitivityDbm,
    required this.radiusM,
    required this.rateMbps,
  });

  final int mcs;

  /// Sensitivity at the chosen width, before the margin.
  final double sensitivityDbm;
  final double radiusM;

  /// PHY rate at the chosen width and stream count, or null when the MCS
  /// Index table has no figure.
  final double? rateMbps;
}

/// What the client dot reads.
@immutable
class RvrClientReading {
  const RvrClientReading({
    required this.distanceM,
    required this.receivedDbm,
    required this.noiseFloorDbm,
    required this.snrDb,
    required this.mcs,
    required this.rateMbps,
    required this.insideCell,
  });

  final double distanceM;
  final double receivedDbm;
  final double noiseFloorDbm;
  final double snrDb;

  /// Highest MCS the client can use, or null below MCS 0.
  final int? mcs;
  final double? rateMbps;

  /// True when the client can decode beacons at the minimum basic rate.
  final bool insideCell;
}

/// Number formatting shared by stage and controls.
abstract final class RvrFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String dist(double d) {
    if (d < 1) return 'under 1 m';
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(2)} km';
  }

  static String rate(double? mbps) {
    if (mbps == null) return 'no rate';
    return mbps >= 100 ? '${mbps.round()} Mbps' : '${n(mbps)} Mbps';
  }

  static String pct(double v) => '${v < 10 ? n(v, 2) : n(v, 1)}%';
}

class RateVsRangeModel extends ChangeNotifier {
  RateVsRangeModel();

  static const double eirpMin = 0;
  static const double eirpMax = 36;
  static const double gainMin = -5;
  static const double gainMax = 6;
  static const double exponentMin = 2;
  static const double exponentMax = 4;
  static const double marginMax = 20;
  static const int ssidMin = 1;
  static const int ssidMax = 16;
  static const int streamsMax = McsIndexScreen.maxSourcedStreams;

  /// The nice view ranges the stage steps through, meters from AP to edge.
  /// Each halves to a round number, since the stage labels the half-way
  /// circle too.
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

  WifiBand _band = WifiBand.band5;
  int _widthMHz = 20;
  int _streams = 2;
  double _eirpDbm = 20;
  double _clientGainDbi = 0;
  double _exponent = 3;
  double _marginDb = 0;
  RvrBasicRate _basicRate = RvrBasicRate.mbps6;
  int _ssids = 4;
  double _clientDistanceM = 20;

  /// Bearing of the client from the AP, radians, 0 = east, clockwise. Only
  /// where the dot is drawn; the physics depends on distance alone.
  double _clientAngle = -math.pi / 4;

  int _revision = 0;

  // ── Getters ─────────────────────────────────────────────────────────────

  WifiBand get band => _band;
  int get widthMHz => _widthMHz;
  int get streams => _streams;
  double get eirpDbm => _eirpDbm;
  double get clientGainDbi => _clientGainDbi;
  double get exponent => _exponent;
  double get marginDb => _marginDb;
  RvrBasicRate get basicRate => _basicRate;
  int get ssids => _ssids;
  double get clientDistanceM => _clientDistanceM;
  double get clientAngle => _clientAngle;
  double get noiseFigureDb => RateVsRangeMath.defaultNoiseFigureDb;

  /// Bumped on every change that alters what the stage draws.
  int get revision => _revision;

  /// Widths this band allows.
  List<int> get bandWidths => _band.widthsMHz;

  /// The 20 MHz channel the path loss is computed at: the FSPL Simulator's
  /// default per band (2.4 GHz ch 6, 5 GHz ch 100, 6 GHz ch 37).
  int get channel => kFsplDefaultChannels[_band]!;

  double get freqMHz => channelToFrequency(_band, channel)!.toDouble();

  // ── Setters ─────────────────────────────────────────────────────────────

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void setBand(WifiBand b) {
    _band = b;
    if (!b.widthsMHz.contains(_widthMHz)) _widthMHz = b.widthsMHz.last;
    _clientDistanceM = _clientDistanceM.clamp(1, viewRangeM);
    _changed();
  }

  void setWidth(int w) {
    if (!_band.widthsMHz.contains(w)) return;
    _widthMHz = w;
    _changed();
  }

  void setStreams(int s) {
    _streams = s.clamp(1, streamsMax);
    _changed();
  }

  void setEirp(double v) {
    _eirpDbm = v.clamp(eirpMin, eirpMax);
    _clampClient();
    _changed();
  }

  void setClientGain(double v) {
    _clientGainDbi = v.clamp(gainMin, gainMax);
    _clampClient();
    _changed();
  }

  void setExponent(double v) {
    _exponent = v.clamp(exponentMin, exponentMax);
    _clampClient();
    _changed();
  }

  void setMargin(double v) {
    _marginDb = v.clamp(0, marginMax);
    _changed();
  }

  void setBasicRate(RvrBasicRate r) {
    _basicRate = r;
    _changed();
  }

  void setSsids(int n) {
    _ssids = n.clamp(ssidMin, ssidMax);
    _changed();
  }

  void setClientDistance(double d) {
    _clientDistanceM = d.clamp(1, viewRangeM);
    _changed();
  }

  /// Places the client from a drag: distance and bearing.
  void setClientPolar(double distanceM, double angle) {
    _clientDistanceM = distanceM.clamp(1, viewRangeM);
    _clientAngle = angle;
    _changed();
  }

  /// Presenter keyboard. Nothing animates, so there is no play, step or
  /// reset: Up and Down move the client out and in along its bearing, a
  /// quarter of a doubling at a time, so a few presses cross a ring.
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () => setClientDistance(_clientDistanceM / _keyStep),
    sliderUp: () => setClientDistance(_clientDistanceM * _keyStep),
    sliderLabel: 'Client distance',
  );

  /// 2^(1/4): four presses double or halve the distance.
  static final double _keyStep = math.pow(2, 0.25).toDouble();

  void _clampClient() {
    _clientDistanceM = _clientDistanceM.clamp(1, viewRangeM);
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  double _radius(double thresholdDbm) => RateVsRangeMath.radiusM(
    thresholdDbm: thresholdDbm,
    eirpDbm: _eirpDbm,
    clientGainDbi: _clientGainDbi,
    freqMHz: freqMHz,
    exponent: _exponent,
  );

  double? rateFor(int mcs) => McsIndexScreen.rate(
    std: McsStd.be,
    mcs: mcs,
    columnIndex: RateVsRangeMath.widthIndex(_widthMHz),
    spatialStreams: _streams,
  );

  /// Every MCS ring at the chosen width, MCS 0 (largest) first.
  List<RvrRing> get rings => <RvrRing>[
    for (int m = 0; m <= RateVsRangeMath.maxMcs; m++)
      RvrRing(
        mcs: m,
        sensitivityDbm: RateVsRangeMath.sensitivityDbm(m, _widthMHz),
        radiusM: _radius(
          RateVsRangeMath.sensitivityDbm(m, _widthMHz) + _marginDb,
        ),
        rateMbps: rateFor(m),
      ),
  ];

  double get cellEdgeDbm =>
      RateVsRangeMath.basicRateSensitivityDbm(_basicRate) + _marginDb;

  /// Where beacons at the minimum basic rate stop being decodable, m.
  double get cellEdgeM => _radius(cellEdgeDbm);

  /// Cell edge with a 6 Mbps basic rate, for comparison.
  double get cellEdge6M => _radius(
    RateVsRangeMath.basicRateSensitivityDbm(RvrBasicRate.mbps6) + _marginDb,
  );

  /// Meters from the AP to the stage edge. Set by the largest circle this
  /// link could draw (MCS 0 at 20 MHz or a 6 Mbps cell edge, no margin), so
  /// width, margin and basic rate never rescale the view: their rings visibly
  /// shrink instead.
  double get viewRangeM {
    final double far = _radius(RateVsRangeMath.sensitivityDbm(0, 20)) * 1.08;
    for (final double r in viewRanges) {
      if (r >= far) return r;
    }
    return viewRanges.last;
  }

  RvrClientReading get client {
    final double rx = RateVsRangeMath.receivedDbm(
      eirpDbm: _eirpDbm,
      clientGainDbi: _clientGainDbi,
      distanceM: _clientDistanceM,
      freqMHz: freqMHz,
      exponent: _exponent,
    );
    final double nf = RateVsRangeMath.noiseFloorDbm(_widthMHz, noiseFigureDb);
    final int? mcs = RateVsRangeMath.mcsFor(rx, _widthMHz, marginDb: _marginDb);
    return RvrClientReading(
      distanceM: _clientDistanceM,
      receivedDbm: rx,
      noiseFloorDbm: nf,
      snrDb: rx - nf,
      mcs: mcs,
      rateMbps: mcs == null ? null : rateFor(mcs),
      insideCell: rx >= cellEdgeDbm,
    );
  }

  double get beaconPercent =>
      RateVsRangeMath.beaconAirtimePercent(_basicRate, _ssids);

  double get beaconPercentAt6 =>
      RateVsRangeMath.beaconAirtimePercent(RvrBasicRate.mbps6, _ssids);

  String mcsLabel(int m) {
    final RvrMcsInfo i = RateVsRangeMath.mcsInfo[m];
    return 'MCS $m, ${i.modulation} ${i.codeRate}';
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final String Function(double, [int]) n = RvrFormat.n;
    final RvrClientReading c = client;
    final StringBuffer b = StringBuffer()
      ..writeln('Rate vs Range')
      ..writeln(
        '${_band.label} ch $channel (${freqMHz.round()} MHz), $_widthMHz MHz, '
        '$_streams SS, EIRP ${n(_eirpDbm, 0)} dBm, client gain '
        '${n(_clientGainDbi, 0)} dBi, path-loss exponent ${n(_exponent)}, '
        'margin ${n(_marginDb, 0)} dB',
      )
      ..writeln('MCS\tSensitivity dBm\tRadius m\tRate Mbps');
    for (final RvrRing r in rings) {
      b.writeln(
        '${r.mcs}\t${n(r.sensitivityDbm, 0)}\t${n(r.radiusM)}\t'
        '${r.rateMbps == null ? '-' : n(r.rateMbps!)}',
      );
    }
    b
      ..writeln(
        'Minimum basic rate ${_basicRate.label} '
        '(${_basicRate.isSourcedDirectly ? 'same floor as MCS 0' : 'MCS-equivalent: MCS ${_basicRate.equivalentMcs}'}): cell edge '
        '${n(cellEdgeDbm, 0)} dBm at ${n(cellEdgeM)} m',
      )
      ..writeln(
        'Beacons, $_ssids SSIDs: ${RvrFormat.pct(beaconPercent)} of airtime '
        '(${RvrFormat.pct(beaconPercentAt6)} at 6 Mbps)',
      )
      ..writeln(
        'Client at ${RvrFormat.dist(c.distanceM)}: ${n(c.receivedDbm)} dBm, '
        'SNR ${n(c.snrDb)} dB, '
        '${c.mcs == null ? 'below MCS 0' : 'MCS ${c.mcs} ${RvrFormat.rate(c.rateMbps)}'}',
      );
    return b.toString().trimRight();
  }
}
