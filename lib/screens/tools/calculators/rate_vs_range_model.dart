// State for the Wi-Fi Classroom Rate vs Range tool (rate-vs-range).
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
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/rate_set_model.dart';
import '../../../services/wifi_lab/rate_vs_range_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
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

  /// True when the client can decode beacons at the minimum basic rate;
  /// null when that rate has no sourced floor (9 Mbps, DSSS), so there is
  /// no cell edge to be inside.
  final bool? insideCell;
}

/// Number formatting shared by stage and controls.
abstract final class RvrFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String dist(double d, [UnitSystem u = UnitSystem.metric]) {
    if (u.isMetric) {
      if (d < 1) return 'under 1 m';
      if (d < 10) return '${d.toStringAsFixed(1)} m';
      if (d < 1000) return '${d.round()} m';
      return '${(d / 1000).toStringAsFixed(2)} km';
    }
    final double ft = LengthUnits.metresToFeet(d);
    if (ft < 3) return 'under 3 ft';
    if (ft < 10) return '${ft.toStringAsFixed(1)} ft';
    if (d < LengthUnits.metresPerMile) return '${ft.round()} ft';
    return '${(d / LengthUnits.metresPerMile).toStringAsFixed(2)} mi';
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

  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    _clientDistanceM = _clientDistanceM.clamp(1, viewRangeM);
    _changed();
  }

  /// [RvrFormat.dist] in the current units.
  String dist(double d) => RvrFormat.dist(d, _units);

  WifiBand _band = WifiBand.band5;
  int _widthMHz = 20;
  int _streams = 2;
  double _eirpDbm = 20;
  double _clientGainDbi = 0;
  double _exponent = 3;
  double _marginDb = 0;

  /// Every rate's state (spec 44). Stored with all 12; [rateSet] reads it
  /// on the band's PHY, so DSSS choices come back on returning to 2.4 GHz.
  RateSet _rates = RateSet.defaults(RsPhy.erp);
  RsClient _rsClient = RsClient.wifi6;
  RsRequiredPhy _requirePhy = RsRequiredPhy.none;
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

  /// The PHY the band runs: ERP at 2.4 GHz, OFDM at 5 and 6 GHz.
  RsPhy get phy => _band == WifiBand.band24 ? RsPhy.erp : RsPhy.ofdm;

  /// The AP's rate set on this band.
  RateSet get rateSet => _rates.onPhy(phy);

  /// The client the Rate set card asks about.
  RsClient get rsClient => _rsClient;

  /// The PHY a membership selector requires.
  RsRequiredPhy get requirePhy => _requirePhy;

  /// HT does not run in 6 GHz, so there the choice is nothing or HE.
  List<RsRequiredPhy> get requirePhyChoices => _band == WifiBand.band6
      ? const <RsRequiredPhy>[RsRequiredPhy.none, RsRequiredPhy.he]
      : RsRequiredPhy.values;

  /// The derived minimum basic rate: the lowest basic rate, or null when the
  /// basic set is empty.
  RsRate? get minimumBasic => rateSet.minimumBasic;

  /// The minimum basic rate when it has a sourced floor (6, 12 to 54 Mbps),
  /// else null: 9 Mbps and the DSSS rates draw no cell-edge ring
  /// (rate_vs_range_math.dart, THE LEGACY RATES ARE MCS-EQUIVALENT).
  RvrBasicRate? get basicRate {
    final RsRate? m = minimumBasic;
    if (m == null) return null;
    for (final RvrBasicRate r in RvrBasicRate.values) {
      if (r.mbps == m.mbps) return r;
    }
    return null;
  }

  /// Where beacons go (the lowest basic rate: vendor behavior), or null when
  /// every rate is off.
  RsBeacon? get beacon => rateSet.beacon;

  /// "6 Mbps", the beacon rate, or "no" when every rate is off.
  String get beaconLabel => beacon?.rate.mbpsLabel ?? 'no';

  /// Whether the client dot can hear beacons, in one sentence.
  /// [associateClause] adds "so it will not associate here" when outside.
  String cellSentence({bool associateClause = false}) {
    final bool? inside = client.insideCell;
    if (beacon == null) return 'No rates are on, so there are no beacons.';
    if (inside == null) {
      return basicRate == null && minimumBasic == null
          ? 'No basic rates: beacons go at $beaconLabel, a mandatory rate. '
                'No cell edge is drawn.'
          : 'No cell edge drawn: $beaconLabel has no sourced sensitivity '
                'here.';
    }
    return inside
        ? 'Inside the cell: it can decode $beaconLabel beacons.'
        : 'Outside the cell: too weak for $beaconLabel beacons'
              '${associateClause ? ', so it will not associate here' : ''}.';
  }

  /// Whether the chosen client can associate.
  RsAssociation get association =>
      canJoin(rateSet, _rsClient, requirePhy: _requirePhy);

  /// The same for every client type, picker order.
  List<RsAssociation> get associations => <RsAssociation>[
    for (final RsClient c in RsClient.values)
      canJoin(rateSet, c, requirePhy: _requirePhy),
  ];

  /// "ACK to a frame sent at X", HE rows when the client is Wi-Fi 6.
  List<RsControlResponse> get ackTable =>
      rateSet.ackTable(withHe: _rsClient == RsClient.wifi6);
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
    if (!requirePhyChoices.contains(_requirePhy)) {
      _requirePhy = RsRequiredPhy.none;
    }
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

  /// Makes [r] the minimum basic rate: slower rates off, [r] basic, faster
  /// rates that were off now supported (RateSet.withMinimumBasic).
  void setBasicRate(RvrBasicRate r) {
    _rates = rateSet.withMinimumBasic(RsRate.ofMbps(r.mbps)!);
    _changed();
  }

  /// One tap on a rate chip: off, supported, basic. Rates the band does not
  /// have (DSSS at 5 and 6 GHz) do nothing.
  void cycleRate(RsRate r) {
    if (!phy.has(r)) return;
    _rates = rateSet.cycle(r);
    _changed();
  }

  /// Presenter B: the next sourced minimum basic rate up (6, 12 ... 54),
  /// wrapping to 6. From 9 Mbps, a DSSS rate or no basic rate it goes to 6.
  void raiseMinimumBasic() {
    final RvrBasicRate? now = basicRate;
    const List<RvrBasicRate> all = RvrBasicRate.values;
    setBasicRate(
      now == null ? all.first : all[(all.indexOf(now) + 1) % all.length],
    );
  }

  void setRsClient(RsClient c) {
    _rsClient = c;
    _changed();
  }

  /// Presenter C: the next client type.
  void cycleRsClient() => setRsClient(
    RsClient.values[(_rsClient.index + 1) % RsClient.values.length],
  );

  void setRequirePhy(RsRequiredPhy p) {
    if (!requirePhyChoices.contains(p)) return;
    _requirePhy = p;
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
  /// B raises the minimum basic rate and C changes the client type (the
  /// Rate set card, spec 44).
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () => setClientDistance(_clientDistanceM / _keyStep),
    sliderUp: () => setClientDistance(_clientDistanceM * _keyStep),
    sliderLabel: 'Client distance',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        description: 'Raise the minimum basic rate (wraps to 6 Mbps)',
        onPressed: raiseMinimumBasic,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Next client type',
        onPressed: cycleRsClient,
      ),
    ],
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

  /// The cell-edge threshold, or null when the minimum basic rate has no
  /// sourced floor.
  double? get cellEdgeDbm {
    final RvrBasicRate? r = basicRate;
    return r == null
        ? null
        : RateVsRangeMath.basicRateSensitivityDbm(r) + _marginDb;
  }

  /// Where beacons at the minimum basic rate stop being decodable, m; null
  /// when there is no sourced floor to draw.
  double? get cellEdgeM {
    final double? dbm = cellEdgeDbm;
    return dbm == null ? null : _radius(dbm);
  }

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
    return NiceTicks.viewRange(far, _units, viewRanges);
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
      insideCell: cellEdgeDbm == null ? null : rx >= cellEdgeDbm!,
    );
  }

  /// Beacon airtime at the beacon rate, percent; 0 when every rate is off.
  double get beaconPercent {
    final RsBeacon? b = beacon;
    return b == null
        ? 0
        : RateVsRangeMath.beaconAirtimePercentAtMbps(b.rate.mbps, _ssids);
  }

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
      ..writeln(
        'MCS\tSensitivity dBm\tRadius ${LengthFormat(_units).distUnit}\t'
        'Rate Mbps',
      );
    for (final RvrRing r in rings) {
      b.writeln(
        '${r.mcs}\t${n(r.sensitivityDbm, 0)}\t'
        '${n(LengthFormat(_units).distValue(r.radiusM))}\t'
        '${r.rateMbps == null ? '-' : n(r.rateMbps!)}',
      );
    }
    final RvrBasicRate? mbr = basicRate;
    final RateSet rs = rateSet;
    final RsBeacon? bc = beacon;
    b
      ..writeln(
        'Rate set (${_band.label}): basic ${rsRateList(rs.basic)}; '
        'supported ${rsRateList(<RsRate>[for (final RsRate r in rs.operational)
          if (!rs.basic.contains(r)) r])}',
      )
      ..writeln(
        mbr != null
            ? 'Minimum basic rate ${mbr.label} '
                  '(${mbr.isSourcedDirectly ? 'same floor as MCS 0' : 'MCS-equivalent: MCS ${mbr.equivalentMcs}'}): cell edge '
                  '${n(cellEdgeDbm!, 0)} dBm at '
                  '${n(LengthFormat(_units).distValue(cellEdgeM!))} '
                  '${LengthFormat(_units).distUnit}'
            : minimumBasic != null
            ? 'Minimum basic rate ${minimumBasic!.mbpsLabel}: no sourced '
                  'floor, no cell-edge ring'
            : 'No basic rates',
      )
      ..writeln(
        bc == null
            ? 'Every rate is off: no beacons'
            : 'Beacons at ${bc.rate.mbpsLabel} '
                  '(${bc.fromBasic ? 'the lowest basic rate, a common vendor choice' : 'no basic rates, so a mandatory rate'}), '
                  '$_ssids SSIDs: ${RvrFormat.pct(beaconPercent)} of airtime '
                  '(${RvrFormat.pct(beaconPercentAt6)} at 6 Mbps)',
      );
    for (final RsAssociation a in associations) {
      b.writeln('${a.client.label}: ${rsVerdictLine(a)}');
    }
    b.writeln('ACK to a frame sent at\tACK rate');
    for (final RsControlResponse r in ackTable) {
      b.writeln(
        '${r.eliciting.label}\t${r.rate.mbpsLabel}'
        '${r.fromBasic ? '' : ' (mandatory fallback)'}'
        '${r.classFilterDecided ? ' (the model\'s reading)' : ''}',
      );
    }
    b.writeln(
      'Client at ${dist(c.distanceM)}: ${n(c.receivedDbm)} dBm, '
      'SNR ${n(c.snrDb)} dB, '
      '${c.mcs == null ? 'below MCS 0' : 'MCS ${c.mcs} ${RvrFormat.rate(c.rateMbps)}'}',
    );
    return b.toString().trimRight();
  }
}
