// State for the Wi-Fi Classroom 6 GHz Power and PSD tool (six-ghz-psd).
//
// One ChangeNotifier holds every input and derives every number the stage and
// the controls show, so the two can be laid out independently (stacked on a
// phone, side by side on desktop, and later a full-screen presenter layout)
// without either owning the other. All regulatory math is in
// lib/services/wifi_lab/six_ghz_psd_math.dart; this file only wires inputs
// to it and words the results.
//
// MCS: the Signal Thresholds tool already carries an SNR-to-MCS table (typical
// minimum SNR per HE MCS). Spec 17 says to use it if it exists, so the
// highest MCS is read from that table, never hand-copied here.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/fspl_math.dart';
import '../../../services/wifi_lab/six_ghz_psd_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../reference/signal_thresholds_screen.dart';
import 'fspl_simulator_chart.dart' show CurveMarker, CurveStroke;

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kSixGhzPsdToolId = 'six-ghz-psd';

/// What the stage draws.
enum PsdView {
  eirp('EIRP'),
  snr('SNR'),
  spectrum('Spectrum');

  const PsdView(this.label);
  final String label;
}

/// The four US power classes; the EU LPI and VLP classes join their US
/// namesakes. One hue per family (PsdPalette, GL-003 §8.15.2).
enum PowerFamily { sp, lpi, gvp, vlp }

PowerFamily psdFamilyOf(PowerClass c) => switch (c) {
  PowerClass.usSpAp ||
  PowerClass.usFixedClient ||
  PowerClass.usSpClient => PowerFamily.sp,
  PowerClass.usLpiAp ||
  PowerClass.usSubordinate ||
  PowerClass.usLpiClient ||
  PowerClass.euLpi => PowerFamily.lpi,
  PowerClass.usGvpAp || PowerClass.usGvpClient => PowerFamily.gvp,
  PowerClass.usVlp || PowerClass.euVlp => PowerFamily.vlp,
};

/// Stroke and marker per class, so no class is told apart by color alone.
/// Stroke follows the family (SP solid, LPI dashed, GVP and VLP dotted);
/// marker is the role (AP circle, client triangle, anything else square).
const Map<PowerClass, (CurveStroke, CurveMarker)> kPsdClassLook =
    <PowerClass, (CurveStroke, CurveMarker)>{
      PowerClass.usSpAp: (CurveStroke.solid, CurveMarker.circle),
      PowerClass.usFixedClient: (CurveStroke.solid, CurveMarker.square),
      PowerClass.usSpClient: (CurveStroke.solid, CurveMarker.triangle),
      PowerClass.usLpiAp: (CurveStroke.dashed, CurveMarker.circle),
      PowerClass.usSubordinate: (CurveStroke.dashed, CurveMarker.square),
      PowerClass.usLpiClient: (CurveStroke.dashed, CurveMarker.triangle),
      PowerClass.usGvpAp: (CurveStroke.dotted, CurveMarker.circle),
      PowerClass.usGvpClient: (CurveStroke.dotted, CurveMarker.triangle),
      PowerClass.usVlp: (CurveStroke.dotted, CurveMarker.square),
      PowerClass.euLpi: (CurveStroke.dashed, CurveMarker.circle),
      PowerClass.euVlp: (CurveStroke.dotted, CurveMarker.square),
    };

/// One SNR-to-MCS row read from Signal Thresholds.
@immutable
class PsdMcsStep {
  const PsdMcsStep(this.minSnrDb, this.label);
  final double minSnrDb;
  final String label;
}

/// Reads the Signal Thresholds SNR-to-MCS table, ascending by minimum SNR.
List<PsdMcsStep> psdMcsSteps() {
  final List<PsdMcsStep> out = <PsdMcsStep>[];
  for (final SnrMcsRow r in SignalThresholdsScreen.kSnrMcsRows) {
    final Match? m = RegExp(r'-?\d+(\.\d+)?').firstMatch(r.minSnr);
    final double? v = m == null ? null : double.tryParse(m.group(0)!);
    if (v != null) out.add(PsdMcsStep(v, r.mcs));
  }
  out.sort((PsdMcsStep a, PsdMcsStep b) => a.minSnrDb.compareTo(b.minSnrDb));
  return out;
}

/// Everything the readouts show for one class at one width.
@immutable
class PsdClassReading {
  const PsdClassReading({
    required this.powerClass,
    required this.widthMHz,
    required this.eirpDbm,
    required this.limit,
    required this.radiatedPsd,
    required this.noiseFloorDbm,
    required this.receivedDbm,
    required this.snrDb,
    required this.channels,
    required this.mcs,
  });

  final PowerClass powerClass;
  final int widthMHz;
  final double eirpDbm;
  final PsdLimit limit;
  final double radiatedPsd;
  final double noiseFloorDbm;
  final double receivedDbm;
  final double snrDb;
  final int channels;

  /// Highest typical MCS the SNR supports, or null below the lowest row.
  final PsdMcsStep? mcs;
}

/// Number formatting shared by stage and controls.
abstract final class PsdFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String signed(double v, [int decimals = 1]) {
    final String s = n(v, decimals);
    return (v >= 0 && !s.startsWith('-')) ? '+$s' : s;
  }

  static String dist(double d) {
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    return '${d.round()} m';
  }
}

class SixGhzPsdModel extends ChangeNotifier {
  SixGhzPsdModel();

  static const double minDistanceM = 1;
  static const double maxDistanceM = 100;

  PsdRegion _region = PsdRegion.us;
  final Map<PsdRegion, Set<PowerClass>> _shown = <PsdRegion, Set<PowerClass>>{
    PsdRegion.us: <PowerClass>{
      PowerClass.usSpAp,
      PowerClass.usLpiAp,
      PowerClass.usVlp,
    },
    PsdRegion.eu: <PowerClass>{PowerClass.euLpi, PowerClass.euVlp},
  };
  final Map<PsdRegion, PowerClass> _focus = <PsdRegion, PowerClass>{
    PsdRegion.us: PowerClass.usLpiAp,
    PsdRegion.eu: PowerClass.euLpi,
  };

  PsdView _view = PsdView.eirp;
  int _widthMHz = 80;
  double _distanceM = 10;
  double _extraLossDb = 0;
  double _noiseFigureDb = SixGhzPsdMath.defaultNoiseFigureDb;
  double _spAuthorizedDbm = SixGhzPsdMath.defaultSpAuthorizedDbm;
  double _gvpAuthorizedDbm = SixGhzPsdMath.defaultGvpAuthorizedDbm;

  int _revision = 0;

  final List<PsdMcsStep> mcsSteps = psdMcsSteps();

  // ── Getters ─────────────────────────────────────────────────────────────

  PsdRegion get region => _region;
  PsdView get view => _view;
  int get widthMHz => _widthMHz;
  double get distanceM => _distanceM;
  double get extraLossDb => _extraLossDb;
  double get noiseFigureDb => _noiseFigureDb;
  double get spAuthorizedDbm => _spAuthorizedDbm;
  double get gvpAuthorizedDbm => _gvpAuthorizedDbm;

  /// Bumped on every change that alters what the stage draws.
  int get revision => _revision;

  /// Every class of the current region, in rule order.
  List<PowerClass> get regionClasses => PowerClass.forRegion(_region);

  /// Shown classes in rule order.
  List<PowerClass> get classes => <PowerClass>[
    for (final PowerClass c in regionClasses)
      if (_shown[_region]!.contains(c)) c,
  ];

  bool isShown(PowerClass c) => _shown[c.region]!.contains(c);

  /// The class the spectrum view draws: the chosen one if shown, else the
  /// first shown class, else null.
  PowerClass? get focus {
    final List<PowerClass> cs = classes;
    if (cs.isEmpty) return null;
    final PowerClass f = _focus[_region]!;
    return cs.contains(f) ? f : cs.first;
  }

  /// True when an SP class is on screen, so the SP grant slider matters.
  bool get spGrantInPlay =>
      isShown(PowerClass.usSpAp) || isShown(PowerClass.usSpClient);
  bool get gvpGrantInPlay =>
      isShown(PowerClass.usGvpAp) || isShown(PowerClass.usGvpClient);

  // ── Setters ─────────────────────────────────────────────────────────────

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void setRegion(PsdRegion r) {
    _region = r;
    _changed();
  }

  void setShown(PowerClass c, bool on) {
    on ? _shown[c.region]!.add(c) : _shown[c.region]!.remove(c);
    _changed();
  }

  void setFocus(PowerClass c) {
    _focus[c.region] = c;
    _changed();
  }

  void setView(PsdView v) {
    _view = v;
    _changed();
  }

  void setWidth(int w) {
    assert(SixGhzPsdMath.widthsMHz.contains(w));
    _widthMHz = w;
    _changed();
  }

  /// Width by index 0..4 (the slider and the chart columns).
  void setWidthIndex(int i) => setWidth(SixGhzPsdMath.widthsMHz[i.clamp(0, 4)]);

  int get widthIndex => SixGhzPsdMath.widthsMHz.indexOf(_widthMHz);

  /// Presenter keyboard. Nothing animates, so there is no play, step or
  /// reset: Up and Down move the channel width one step (20 to 320 MHz), the
  /// lesson's own control. Disabled with no class on, like the width slider.
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () {
      if (classes.isNotEmpty) setWidthIndex(widthIndex - 1);
    },
    sliderUp: () {
      if (classes.isNotEmpty) setWidthIndex(widthIndex + 1);
    },
    sliderLabel: 'Channel width',
  );

  void setDistance(double d) {
    _distanceM = d.clamp(minDistanceM, maxDistanceM);
    _changed();
  }

  void setExtraLoss(double v) {
    _extraLossDb = v;
    _changed();
  }

  void setNoiseFigure(double v) {
    _noiseFigureDb = v;
    _changed();
  }

  void setSpAuthorized(double v) {
    _spAuthorizedDbm = v;
    _changed();
  }

  void setGvpAuthorized(double v) {
    _gvpAuthorizedDbm = v;
    _changed();
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  PsdEirp eirp(PowerClass c, int w) => SixGhzPsdMath.eirp(
    c,
    w,
    spAuthorizedDbm: _spAuthorizedDbm,
    gvpAuthorizedDbm: _gvpAuthorizedDbm,
  );

  double snr(PowerClass c, int w) => SixGhzPsdMath.snrDb(
    eirpDbm: eirp(c, w).eirpDbm,
    widthMHz: w,
    distanceM: _distanceM,
    extraLossDb: _extraLossDb,
    noiseFigureDb: _noiseFigureDb,
  );

  double get pathLossDb =>
      FsplMath.fsplDb(_distanceM, SixGhzPsdMath.referenceFreqMHz);

  PsdMcsStep? mcsFor(double snrDb) {
    PsdMcsStep? best;
    for (final PsdMcsStep s in mcsSteps) {
      if (snrDb >= s.minSnrDb) best = s;
    }
    return best;
  }

  PsdClassReading reading(PowerClass c, [int? width]) {
    final int w = width ?? _widthMHz;
    final PsdEirp e = eirp(c, w);
    final double snrDb = snr(c, w);
    return PsdClassReading(
      powerClass: c,
      widthMHz: w,
      eirpDbm: e.eirpDbm,
      limit: e.limit,
      radiatedPsd: SixGhzPsdMath.radiatedPsdDbmPerMHz(e.eirpDbm, w),
      noiseFloorDbm: SixGhzPsdMath.noiseFloorDbm(w, _noiseFigureDb),
      receivedDbm: SixGhzPsdMath.receivedDbm(
        e.eirpDbm,
        _distanceM,
        _extraLossDb,
      ),
      snrDb: snrDb,
      channels: SixGhzPsdMath.channelCount(c, w),
      mcs: mcsFor(snrDb),
    );
  }

  /// The plain-language line for a class at the selected width.
  String verdict(PowerClass c, [int? width]) {
    final int w = width ?? _widthMHz;
    final PsdEirp e = eirp(c, w);
    final String Function(double, [int]) n = PsdFormat.n;
    final String prod =
        '${n(c.psdDbmPerMHz, 0)} dBm/MHz x $w MHz = '
        '${n(SixGhzPsdMath.psdEirpDbm(c, w))} dBm';
    switch (e.limit) {
      case PsdLimit.psd:
        return 'PSD-limited at $w MHz: $prod. A wider channel adds 3 dB of '
            'EIRP, which matches the 3 dB higher noise floor, so SNR holds.';
      case PsdLimit.cap:
        return 'Cap-limited at $w MHz: $prod, held to the '
            '${n(c.maxEirpDbm, 0)} dBm maximum. A wider channel spreads the '
            'same power thinner, so SNR falls 3 dB per doubling.';
      case PsdLimit.apRelative:
        final double auth = c.followsAp == PsdAuthorizedBy.gvp
            ? _gvpAuthorizedDbm
            : _spAuthorizedDbm;
        return 'Cap-limited by its AP at $w MHz: 6 dB below the AP\'s '
            'authorized ${n(auth, 0)} dBm, so ${n(e.eirpDbm)} dBm. SNR falls '
            '3 dB per doubling.';
      case PsdLimit.authorized:
        final String by = c.ownGrant == PsdAuthorizedBy.gvp
            ? 'the geofencing system'
            : 'the AFC';
        return 'Cap-limited by its grant at $w MHz: $by authorized '
            '${n(e.eirpDbm)} dBm, below the ${n(c.maxEirpDbm, 0)} dBm '
            'maximum. SNR falls 3 dB per doubling.';
    }
  }

  // ── Chart data ──────────────────────────────────────────────────────────

  /// y value of a class at a width on the current (non-spectrum) view.
  double y(PowerClass c, int w) =>
      _view == PsdView.snr ? snr(c, w) : eirp(c, w).eirpDbm;

  String get unit => _view == PsdView.snr ? 'dB' : 'dBm';

  /// y bounds and grid step covering every shown line, rounded to the grid.
  ({double min, double max, double step}) yRange() {
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final PowerClass c in classes) {
      for (final int w in SixGhzPsdMath.widthsMHz) {
        final double v = y(c, w);
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (!lo.isFinite || !hi.isFinite) {
      return _view == PsdView.snr
          ? (min: 0.0, max: 60.0, step: 10.0)
          : (min: 0.0, max: 40.0, step: 5.0);
    }
    final double step = (hi - lo) > 45 ? 10 : 5;
    double min = ((lo - 1) / step).floor() * step;
    double max = ((hi + 1) / step).ceil() * step;
    if (max - min < 4 * step) {
      final double pad = ((4 * step - (max - min)) / 2 / step).ceil() * step;
      min -= pad;
      max += pad;
    }
    return (min: min, max: max, step: step);
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String? copyText() {
    if (classes.isEmpty) return null;
    final String Function(double, [int]) n = PsdFormat.n;
    final StringBuffer b = StringBuffer()
      ..writeln('6 GHz Power and PSD (${_region.label})')
      ..writeln(
        '$_widthMHz MHz at ${PsdFormat.dist(_distanceM)}, free-space loss '
        '${n(pathLossDb)} dB at ${SixGhzPsdMath.referenceFreqMHz.round()} MHz'
        '${_extraLossDb > 0 ? ' + ${n(_extraLossDb)} dB extra' : ''}, '
        'noise figure ${n(_noiseFigureDb)} dB',
      );
    if (_region == PsdRegion.us && (spGrantInPlay || gvpGrantInPlay)) {
      b.writeln(
        'AP authorized: SP ${n(_spAuthorizedDbm, 0)} dBm, GVP '
        '${n(_gvpAuthorizedDbm, 0)} dBm',
      );
    }
    b.writeln('Class\tEIRP dBm\tNoise dBm\tSNR dB\tChannels\tLimit');
    for (final PowerClass c in classes) {
      final PsdClassReading r = reading(c);
      b.writeln(
        '${c.shortLabel}\t${n(r.eirpDbm)}\t${n(r.noiseFloorDbm)}\t'
        '${n(r.snrDb)}\t${r.channels}\t'
        '${r.limit.isPsd ? 'PSD-limited' : 'cap-limited'}',
      );
    }
    b.writeln('EIRP by width (20/40/80/160/320 MHz):');
    for (final PowerClass c in classes) {
      b.writeln(
        '  ${c.shortLabel}: '
        '${SixGhzPsdMath.widthsMHz.map((int w) => n(eirp(c, w).eirpDbm)).join(' / ')}',
      );
    }
    return b.toString().trimRight();
  }
}
