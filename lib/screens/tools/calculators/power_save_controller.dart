// State for the Wi-Fi Lab Power Save simulator (power-save).
//
// One ChangeNotifier holds every input and the computed runs, so the two
// halves of the screen stay independent widgets: PowerSaveStage (the
// timeline) and PowerSaveControls (inputs and readouts) each listen to this
// one object. The phone layout stacks them; a presenter layout can place
// them side by side (spec 00).
//
// All rules and the run itself live in lib/services/wifi_lab/
// power_save_model.dart. A run is computed whole whenever an input changes;
// the timeline is a window the student slides along it. There is no clock
// and no animation (GL-003 §8.8): the picture changes only when an input
// does.

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/power_save_model.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kPowerSaveToolId = 'power-save';

/// How much of the run the timeline shows.
enum PsView {
  ms300('0.3 s', 300000),
  s1('1 s', 1000000),
  s10('10 s', 10000000),
  s60('60 s', 60000000);

  const PsView(this.label, this.spanUs);

  final String label;
  final int spanUs;
}

/// Traffic presets. [custom] is what the student gets after changing any
/// traffic value by hand.
enum PsScenario {
  phoneIdle(
    'Phone, mostly idle',
    'A frame now and then each way, and the broadcast chatter of a busy '
        'network.',
    TrafficSettings(),
  ),
  sensor(
    'Sensor',
    'Reports every 10 s and almost never hears from the network.',
    TrafficSettings(dlBurstsPerS: 0.02, ulPerS: 0.1, groupPerS: 0.5),
  ),
  voice(
    'Voice call',
    'A frame every 20 ms each way on AC_VO: the case U-APSD was made for.',
    TrafficSettings(
      dlBurstsPerS: 50,
      ulPerS: 50,
      ac: AccessCategory.vo,
      regular: true,
    ),
  ),
  web(
    'Web page',
    'Now and then a burst of 16 frames arrives at once.',
    TrafficSettings(dlBurstsPerS: 0.1, dlBurstSize: 16, ulPerS: 0.1),
  ),
  custom('Custom', 'Your own values below.', TrafficSettings());

  const PsScenario(this.label, this.description, this.traffic);

  final String label;
  final String description;
  final TrafficSettings traffic;
}

class PowerSaveController extends ChangeNotifier {
  PowerSaveController({PsConfig? initial, PsMode? compare = PsMode.twt})
    : _config = initial ?? const PsConfig() {
    _compare = compare == _config.mode ? null : compare;
    _twtDraft = _config.twt;
    _mantissaText = '${_config.twt.mantissa}';
    _recompute();
  }

  PsConfig _config;
  late PsMode? _compare;
  late PsRun _run;
  PsRun? _compareRun;
  PsView _view = PsView.s1;
  double _startUs = 0;

  /// The TWT values as typed. The config keeps the last valid ones.
  late TwtSettings _twtDraft;
  late String _mantissaText;

  // ── Read side ─────────────────────────────────────────────────────────────

  PsConfig get config => _config;
  PsRun get run => _run;
  PsMode? get compare => _compare;
  PsRun? get compareRun => _compareRun;

  /// The runs on screen: the chosen mode first, then the comparison.
  List<PsRun> get runs => <PsRun>[_run, ?_compareRun];

  PsView get view => _view;
  double get startUs => _startUs;
  double get endUs => _startUs + _view.spanUs;

  /// The latest start the window can have.
  double get maxStartUs =>
      (_config.horizonUs - _view.spanUs).clamp(0, double.infinity).toDouble();

  TwtSettings get twtDraft => _twtDraft;
  String get mantissaText => _mantissaText;

  /// Why the typed mantissa cannot be used, or null.
  String? get mantissaError {
    final int? v = int.tryParse(_mantissaText);
    if (_mantissaText.isEmpty) return 'Enter a mantissa, 1 to 65535.';
    if (v == null || v > kTwtMantissaMax) {
      return 'The mantissa is 16 bits: 0 to 65535.';
    }
    if (v == 0) return 'A mantissa of 0 gives no wake interval.';
    return null;
  }

  /// Why the typed TWT values cannot run, or null.
  String? get twtError => mantissaError ?? _twtDraft.error;

  PsScenario get scenario {
    for (final PsScenario s in PsScenario.values) {
      if (s == PsScenario.custom) continue;
      if (s.traffic.copyWith(seed: _config.traffic.seed) == _config.traffic) {
        return s;
      }
    }
    return PsScenario.custom;
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  void _recompute() {
    _run = simulatePowerSave(_config);
    _compareRun = _compare == null
        ? null
        : simulatePowerSave(_config, mode: _compare);
    _startUs = _startUs.clamp(0, maxStartUs).toDouble();
  }

  void _apply(PsConfig next) {
    if (next == _config) return;
    _config = next;
    _recompute();
    notifyListeners();
  }

  set mode(PsMode m) {
    if (_compare == m) _compare = _config.mode;
    _apply(_config.copyWith(mode: m));
  }

  set compare(PsMode? m) {
    final PsMode? next = m == _config.mode ? null : m;
    if (next == _compare) return;
    _compare = next;
    _recompute();
    notifyListeners();
  }

  set view(PsView v) {
    if (v == _view) return;
    _view = v;
    _startUs = _startUs.clamp(0, maxStartUs).toDouble();
    notifyListeners();
  }

  void seek(double startUs) {
    final double s = startUs.clamp(0, maxStartUs).toDouble();
    if (s == _startUs) return;
    _startUs = s;
    notifyListeners();
  }

  set beaconTu(int v) => _apply(_config.copyWith(beaconTu: v));
  set dtimPeriod(int v) => _apply(_config.copyWith(dtimPeriod: v));
  set listenInterval(int v) => _apply(_config.copyWith(listenInterval: v));

  void setUapsdAc(AccessCategory ac, bool on) {
    final Set<AccessCategory> acs = <AccessCategory>{..._config.uapsd.acs};
    if (on) {
      acs.add(ac);
    } else {
      acs.remove(ac);
    }
    _apply(_config.copyWith(uapsd: _config.uapsd.copyWith(acs: acs)));
  }

  set maxSp(MaxSpLength v) =>
      _apply(_config.copyWith(uapsd: _config.uapsd.copyWith(maxSp: v)));

  void _setTwt(TwtSettings draft) {
    _twtDraft = draft;
    if (mantissaError == null && draft.error == null) {
      _apply(_config.copyWith(twt: draft));
    }
    notifyListeners();
  }

  /// The mantissa as typed; invalid text leaves the last valid run on
  /// screen and shows the reason.
  void setMantissaText(String text) {
    _mantissaText = text;
    final int? v = int.tryParse(text);
    if (v != null && v <= kTwtMantissaMax) {
      _setTwt(_twtDraft.copyWith(mantissa: v));
    } else {
      notifyListeners();
    }
  }

  set twtExponent(int v) => _setTwt(_twtDraft.copyWith(exponent: v));
  set twtDuration(int v) => _setTwt(_twtDraft.copyWith(duration: v));
  set twtDurationUnit(TwtDurationUnit u) =>
      _setTwt(_twtDraft.copyWith(durationUnit: u));
  set twtKind(TwtKind k) => _setTwt(_twtDraft.copyWith(kind: k));
  set twtWakeForDtim(bool v) => _setTwt(_twtDraft.copyWith(wakeForDtim: v));

  /// A TWT interval preset: mantissa and exponent together.
  void twtPreset(int mantissa, int exponent) {
    _mantissaText = '$mantissa';
    _setTwt(_twtDraft.copyWith(mantissa: mantissa, exponent: exponent));
  }

  set scenario(PsScenario s) {
    if (s == PsScenario.custom) return;
    _apply(
      _config.copyWith(traffic: s.traffic.copyWith(seed: _config.traffic.seed)),
    );
  }

  void _traffic(TrafficSettings t) => _apply(_config.copyWith(traffic: t));

  set dlBurstsPerS(double v) =>
      _traffic(_config.traffic.copyWith(dlBurstsPerS: v));
  set dlBurstSize(int v) => _traffic(_config.traffic.copyWith(dlBurstSize: v));
  set ulPerS(double v) => _traffic(_config.traffic.copyWith(ulPerS: v));
  set groupPerS(double v) => _traffic(_config.traffic.copyWith(groupPerS: v));
  set trafficAc(AccessCategory v) => _traffic(_config.traffic.copyWith(ac: v));
  set regular(bool v) => _traffic(_config.traffic.copyWith(regular: v));
  void newRandomPattern() =>
      _traffic(_config.traffic.copyWith(seed: _config.traffic.seed + 1));

  set awakeMa(double v) => _apply(_config.copyWith(awakeMa: v));
  set dozeMa(double v) => _apply(_config.copyWith(dozeMa: v));
  set batteryMah(double v) => _apply(_config.copyWith(batteryMah: v));

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final PsConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln('Power Save (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Beacon ${c.beaconTu} TU (${tuToMs(c.beaconTu).toStringAsFixed(1)} '
        'ms), DTIM ${c.dtimPeriod}, listen interval ${c.listenInterval}',
      )
      ..writeln('Traffic: ${scenario.label}')
      ..writeln(
        'Currents: awake ${fmtCurrent(c.awakeMa)}, doze '
        '${fmtCurrent(c.dozeMa)} (parameters, not measurements); battery '
        '${c.batteryMah.toStringAsFixed(0)} mAh',
      )
      ..writeln('Run: ${fmtUs(c.horizonUs.toDouble())}');
    for (final PsRun r in runs) {
      b.writeln('${r.mode.label}${_modeDetail(r.mode)}:');
      b.writeln(
        '  Awake ${fmtPct(r.awakeFraction)}, ${r.wakeCount} wakes, average '
        '${fmtCurrent(r.averageMa)}, battery estimate '
        '${fmtLife(r.batteryLifeHours)}',
      );
      final LatencyStats dl = r.downlink;
      b.writeln(
        dl.count == 0
            ? '  Downlink: no frames'
            : '  Downlink latency: mean ${fmtUs(dl.meanUs!)}, worst '
                  '${fmtUs(dl.worstUs!)}',
      );
      final LatencyStats g = r.group;
      b.writeln(
        '  Group frames: '
        '${g.count == 0 ? 'none heard' : 'worst ${fmtUs(g.worstUs!)}'}'
        '${r.groupMissed > 0 ? ', ${r.groupMissed} missed while dozing' : ''}',
      );
    }
    return b.toString().trimRight();
  }

  String _modeDetail(PsMode m) {
    switch (m) {
      case PsMode.twt:
        final TwtSettings t = _config.twt;
        return ' (${t.kind.label.toLowerCase()}, ${t.mantissa} x '
            '2^${t.exponent} us = ${fmtUs(t.intervalUs!.toDouble())}, wake '
            '${fmtUs(t.durationUs!.toDouble())})';
      case PsMode.uapsd:
        return ' (QoS Info 0x${qosInfoByte(_config.uapsd.acs, _config.uapsd.maxSp).toRadixString(16).padLeft(2, '0').toUpperCase()})';
      case PsMode.awake:
      case PsMode.legacy:
        return '';
    }
  }
}
