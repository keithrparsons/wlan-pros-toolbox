// State for the Wi-Fi Classroom FSPL Simulator (fspl-simulator).
//
// One ChangeNotifier holds every input and derives every number the stage and
// the controls show, so the two can be laid out independently (stacked on a
// phone, side by side on desktop, and later a full-screen presenter layout)
// without either owning the other. Math comes from FsplMath; this file only
// wires inputs to it.
//
// DESIGN TARGETS: the -67 and -70 dBm reference lines are read from the
// Signal Thresholds tool's per-application table (the VoIP and HD video rows),
// so the two tools cannot drift apart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../reference/signal_thresholds_screen.dart';
import 'fspl_simulator_chart.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kFsplSimulatorToolId = 'fspl-simulator';

/// What the y axis shows.
enum FsplView { received, pathLoss }

/// How far the distance axis runs.
enum FsplRange {
  m100(100, '100 m'),
  km1(1000, '1 km');

  const FsplRange(this.maxM, this.label);
  final double maxM;
  final String label;
}

/// Default 20 MHz channel per band (spec 03): 2.4 GHz ch 6 (2437 MHz),
/// 5 GHz ch 100 (5500 MHz), 6 GHz ch 37 (6135 MHz, UNII-5).
const Map<WifiBand, int> kFsplDefaultChannels = <WifiBand, int>{
  WifiBand.band24: 6,
  WifiBand.band5: 100,
  WifiBand.band6: 37,
};

/// Stroke and marker per band: the only thing that tells bands apart
/// (GL-003 §8.15 has no categorical palette).
const Map<WifiBand, (CurveStroke, CurveMarker)> kFsplBandLook =
    <WifiBand, (CurveStroke, CurveMarker)>{
      WifiBand.band24: (CurveStroke.solid, CurveMarker.circle),
      WifiBand.band5: (CurveStroke.dashed, CurveMarker.square),
      WifiBand.band6: (CurveStroke.dotted, CurveMarker.triangle),
    };

/// A horizontal design-target line.
@immutable
class FsplDesignTarget {
  const FsplDesignTarget(this.dbm, this.label);
  final double dbm;
  final String label;
}

/// The -67 and -70 dBm design targets, read from the Signal Thresholds tool
/// (VoIP / Real-time and Video streaming (HD) rows) rather than hard-coded.
List<FsplDesignTarget> fsplDesignTargets() {
  final List<FsplDesignTarget> out = <FsplDesignTarget>[];
  for (final (String prefix, String name) in <(String, String)>[
    ('VoIP', 'voice'),
    ('Video streaming', 'HD video'),
  ]) {
    for (final AppThreshold a in SignalThresholdsScreen.kAppThresholds) {
      if (!a.application.startsWith(prefix)) continue;
      final Match? m = RegExp(r'-?\d+(\.\d+)?').firstMatch(a.minRssi);
      final double? v = m == null ? null : double.tryParse(m.group(0)!);
      if (v != null) out.add(FsplDesignTarget(v, name));
      break;
    }
  }
  return out;
}

/// Parses a user-typed number: accepts a comma decimal separator and the
/// Unicode minus sign. Null when it is not a number.
double? fsplParseNumber(String raw) {
  final String s = raw.trim().replaceAll(',', '.').replaceAll('−', '-');
  if (s.isEmpty) return null;
  final double? v = double.tryParse(s);
  return (v == null || !v.isFinite) ? null : v;
}

/// Parsed measured-point entry. Null values mean empty or invalid; the error
/// strings say which.
typedef FsplMeasuredInput = ({
  double? rssi,
  double? dist,
  String? rssiError,
  String? distError,
});

/// Number formatting shared by stage and controls.
abstract final class FsplFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String signed(double v, [int decimals = 1]) {
    final String s = n(v, decimals);
    return (v >= 0 && !s.startsWith('-')) ? '+$s' : s;
  }

  static String dist(double d) {
    if (d >= 999.5) return '1 km';
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    return '${d.round()} m';
  }
}

class FsplSimModel extends ChangeNotifier {
  FsplSimModel();

  static const double rssiMin = -120;
  static const double rssiMax = 0;
  static const int sampleCount = 160;

  final Set<WifiBand> _enabled = <WifiBand>{...WifiBand.values};
  final Map<WifiBand, int> _channel = <WifiBand, int>{...kFsplDefaultChannels};

  FsplView _view = FsplView.received;
  FsplRange _range = FsplRange.m100;
  double _cursorM = 10;

  double _txPowerDbm = 20;
  double _txGainDbi = 0;
  double _rxGainDbi = 0;
  double _otherLossDb = 0;

  bool _indoor = false;
  double _exponent = 3.0;

  String _rssiText = '';
  String _distText = '';
  WifiBand _measuredBand = WifiBand.band5;

  int _revision = 0;

  final List<FsplDesignTarget> targets = fsplDesignTargets();

  // ── Getters ─────────────────────────────────────────────────────────────

  FsplView get view => _view;
  FsplRange get range => _range;
  double get cursorM => _cursorM;
  double get txPowerDbm => _txPowerDbm;
  double get txGainDbi => _txGainDbi;
  double get rxGainDbi => _rxGainDbi;
  double get otherLossDb => _otherLossDb;
  bool get indoor => _indoor;
  double get exponent => _exponent;
  String get rssiText => _rssiText;
  String get distText => _distText;
  WifiBand get measuredBand => _measuredBand;

  /// Bumped on every change that alters what the chart draws.
  int get revision => _revision;

  bool isEnabled(WifiBand b) => _enabled.contains(b);
  int channel(WifiBand b) => _channel[b]!;

  /// Enabled bands in ascending frequency order.
  List<WifiBand> get bands => <WifiBand>[
    for (final WifiBand b in WifiBand.values)
      if (_enabled.contains(b)) b,
  ];

  // ── Setters ─────────────────────────────────────────────────────────────

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void setBand(WifiBand b, bool on) {
    on ? _enabled.add(b) : _enabled.remove(b);
    _changed();
  }

  void setChannel(WifiBand b, int ch) {
    _channel[b] = ch;
    _changed();
  }

  void setView(FsplView v) {
    _view = v;
    _changed();
  }

  void setRange(FsplRange r) {
    _range = r;
    _cursorM = math.min(_cursorM, r.maxM);
    _changed();
  }

  void setCursor(double d) {
    _cursorM = d.clamp(1.0, _range.maxM);
    _changed();
  }

  void setTxPower(double v) {
    _txPowerDbm = v;
    _changed();
  }

  void setTxGain(double v) {
    _txGainDbi = v;
    _changed();
  }

  void setRxGain(double v) {
    _rxGainDbi = v;
    _changed();
  }

  void setOtherLoss(double v) {
    _otherLossDb = v;
    _changed();
  }

  void setIndoor(bool v) {
    _indoor = v;
    _changed();
  }

  void setExponent(double v) {
    _exponent = v;
    _changed();
  }

  void setMeasuredText({String? rssi, String? dist}) {
    if (rssi != null) _rssiText = rssi;
    if (dist != null) _distText = dist;
    _changed();
  }

  void setMeasuredBand(WifiBand b) {
    _measuredBand = b;
    _changed();
  }

  /// Presenter keyboard. Nothing animates, so there is no play, step or
  /// reset: Up and Down double and halve the cursor distance, which is the
  /// lesson's own step (every doubling costs 6 dB). Disabled with no band
  /// on, like the cursor slider.
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () {
      if (bands.isNotEmpty) setCursor(_cursorM / 2);
    },
    sliderUp: () {
      if (bands.isNotEmpty) setCursor(_cursorM * 2);
    },
    sliderLabel: 'Cursor distance (halve or double)',
  );

  // ── Derived ─────────────────────────────────────────────────────────────

  double freq(WifiBand b) =>
      (channelToFrequency(b, _channel[b]!) ?? 0).toDouble();

  String chanText(WifiBand b) => 'ch ${_channel[b]}, ${freq(b).round()} MHz';

  double pathLoss(WifiBand b, double d) => FsplMath.fsplDb(d, freq(b));

  double pathLossIndoor(WifiBand b, double d) =>
      FsplMath.logDistanceDb(d, freq(b), _exponent);

  double rx(double pathLoss) => FsplMath.receivedPowerDbm(
    txPowerDbm: _txPowerDbm,
    txGainDbi: _txGainDbi,
    rxGainDbi: _rxGainDbi,
    pathLossDb: pathLoss,
    otherLossesDb: _otherLossDb,
  );

  /// y value on the current view for a path loss.
  double y(double pathLoss) =>
      _view == FsplView.received ? rx(pathLoss) : pathLoss;

  String get unit => _view == FsplView.received ? 'dBm' : 'dB';

  FsplMeasuredInput get measuredInput {
    final double? r = fsplParseNumber(_rssiText);
    final double? d = fsplParseNumber(_distText);
    String? rErr;
    String? dErr;
    if (_rssiText.trim().isNotEmpty &&
        (r == null || r < rssiMin || r > rssiMax)) {
      rErr = 'Enter -120 to 0 dBm';
    }
    if (_distText.trim().isNotEmpty && (d == null || d < 1 || d > 1000)) {
      dErr = 'Enter 1 to 1000 m';
    }
    return (
      rssi: rErr == null ? r : null,
      dist: dErr == null ? d : null,
      rssiError: rErr,
      distError: dErr,
    );
  }

  /// A valid, complete measurement, or null.
  ({double rssi, double dist})? get measured {
    final FsplMeasuredInput m = measuredInput;
    final double? r = m.rssi;
    final double? d = m.dist;
    if (r == null || d == null) return null;
    return (rssi: r, dist: d);
  }

  /// Measured minus free space, dB. Negative = more loss than free space.
  double gap(double rssi, double dist) =>
      rssi - rx(pathLoss(_measuredBand, dist));

  /// The path loss a measured RSSI implies with the current link budget.
  double measuredPathLoss(double rssi) => FsplMath.pathLossForRssi(
    rssiDbm: rssi,
    txPowerDbm: _txPowerDbm,
    txGainDbi: _txGainDbi,
    rxGainDbi: _rxGainDbi,
    otherLossesDb: _otherLossDb,
  );

  /// Log-distance exponent that would pass through the measured point, or
  /// null too close in to say (under 2 m).
  double? fitExponent(double rssi, double dist) {
    if (dist < 2) return null;
    final double n =
        (measuredPathLoss(rssi) - FsplMath.fsplDb(1, freq(_measuredBand))) /
        (10 * FsplMath.log10(dist));
    return n.isFinite ? n : null;
  }

  // ── Chart data ──────────────────────────────────────────────────────────

  List<FsplSeries> series() {
    final double maxD = _range.maxM;
    final List<double> ds = <double>[
      for (int i = 0; i <= sampleCount; i++)
        math.pow(10, i / sampleCount * FsplMath.log10(maxD)).toDouble(),
    ];
    final List<FsplSeries> out = <FsplSeries>[];
    for (final WifiBand b in bands) {
      final (CurveStroke stroke, CurveMarker marker) = kFsplBandLook[b]!;
      out.add(
        FsplSeries(
          points: <(double, double)>[
            for (final double d in ds) (d, y(pathLoss(b, d))),
          ],
          stroke: stroke,
          marker: marker,
          isModel: false,
          cursorValue: y(pathLoss(b, _cursorM)),
        ),
      );
      if (_indoor) {
        out.add(
          FsplSeries(
            points: <(double, double)>[
              for (final double d in ds) (d, y(pathLossIndoor(b, d))),
            ],
            stroke: stroke,
            marker: marker,
            isModel: true,
            cursorValue: y(pathLossIndoor(b, _cursorM)),
          ),
        );
      }
    }
    return out;
  }

  List<FsplRefLine> refLines() => _view == FsplView.received
      ? <FsplRefLine>[
          for (int i = 0; i < targets.length; i++)
            FsplRefLine(
              y: targets[i].dbm,
              label:
                  '${FsplFormat.n(targets[i].dbm, 0)} dBm ${targets[i].label}',
              labelBelow: i > 0,
            ),
        ]
      : const <FsplRefLine>[];

  FsplMeasuredMark? measuredMark() {
    final ({double rssi, double dist})? m = measured;
    if (m == null || !_enabled.contains(_measuredBand)) return null;
    return FsplMeasuredMark(
      distanceM: m.dist,
      y: _view == FsplView.received ? m.rssi : measuredPathLoss(m.rssi),
      curveY: y(pathLoss(_measuredBand, m.dist)),
      label: '${FsplFormat.signed(gap(m.rssi, m.dist))} dB',
    );
  }

  /// y axis bounds and grid step covering every curve, the design targets
  /// (received view) and the measured point, rounded out to the grid.
  ({double min, double max, double step}) yRange(List<FsplSeries> s) {
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final FsplSeries one in s) {
      for (final (double _, double v) in one.points) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (!lo.isFinite || !hi.isFinite) {
      return _view == FsplView.received
          ? (min: -80.0, max: -20.0, step: 10.0)
          : (min: 40.0, max: 100.0, step: 10.0);
    }
    for (final FsplRefLine r in refLines()) {
      lo = math.min(lo, r.y);
      hi = math.max(hi, r.y);
    }
    final FsplMeasuredMark? m = measuredMark();
    if (m != null && m.distanceM <= _range.maxM) {
      lo = math.min(lo, m.y);
      hi = math.max(hi, m.y);
    }
    double min = ((lo - 2) / 10).floor() * 10.0;
    double max = ((hi + 2) / 10).ceil() * 10.0;
    if (max - min < 40) max = min + 40;
    final double step = (max - min) > 100 ? 20 : 10;
    if (step == 20) {
      min = (min / 20).floor() * 20.0;
      max = (max / 20).ceil() * 20.0;
    }
    return (min: min, max: max, step: step);
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String? copyText() {
    if (bands.isEmpty) return null;
    final String Function(double, [int]) n = FsplFormat.n;
    final StringBuffer b = StringBuffer()
      ..writeln('FSPL Simulator')
      ..writeln(
        'Tx ${n(_txPowerDbm)} dBm, Tx gain ${n(_txGainDbi)} dBi, '
        'Rx gain ${n(_rxGainDbi)} dBi, other losses ${n(_otherLossDb)} dB',
      )
      ..writeln('At ${FsplFormat.dist(_cursorM)}:');
    for (final WifiBand band in bands) {
      final double pl = pathLoss(band, _cursorM);
      b.writeln(
        '${band.label} (${chanText(band)}): free-space loss ${n(pl)} dB = '
        'spreading ${n(FsplMath.spreadingLossDb(_cursorM))} + aperture '
        '${n(FsplMath.apertureTermDb(freq(band)))}; received ${n(rx(pl))} dBm',
      );
      if (_indoor) {
        final double pi = pathLossIndoor(band, _cursorM);
        b.writeln(
          '  indoor model n = ${n(_exponent)}: ${n(pi)} dB, ${n(rx(pi))} dBm',
        );
      }
    }
    final ({double rssi, double dist})? m = measured;
    if (m != null) {
      b.writeln(
        'Measured ${n(m.rssi)} dBm at ${FsplFormat.dist(m.dist)} on '
        '${_measuredBand.label}: ${FsplFormat.signed(gap(m.rssi, m.dist))} dB '
        'vs free space',
      );
    }
    return b.toString().trimRight();
  }
}
