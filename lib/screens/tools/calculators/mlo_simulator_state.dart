// State for the Wi-Fi Lab Multi-Link Operation simulator (mlo-simulator).
//
// One ChangeNotifier holds every input and the computed run, so the two
// halves of the screen stay independent widgets: MloSimulatorStage (link
// lanes and latency histograms) and MloSimulatorControls (inputs and
// readouts) each listen to this one object. The phone layout stacks them; a
// presenter layout can place them side by side (spec 00).
//
// The run lives in lib/services/wifi_lab/mlo_model.dart and is recomputed
// whole whenever an input changes (about 10 ms for 2,000 frames). There is
// no clock: the lanes show a window the student slides through.

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/mlo_model.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMloSimulatorToolId = 'mlo-simulator';

/// Lessons: each sets every input to show one point.
enum MloPreset {
  equal(
    'Two equal links: MLO wins',
    MloConfig(
      links: <MloLinkConfig>[
        MloLinkConfig(band: MloBand.ghz5),
        MloLinkConfig(band: MloBand.ghz6),
      ],
    ),
  ),
  oneBusy(
    'One link much busier: the win shrinks',
    MloConfig(
      links: <MloLinkConfig>[
        MloLinkConfig(band: MloBand.ghz5, busyFraction: 0.9),
        MloLinkConfig(band: MloBand.ghz6, busyFraction: 0.3),
      ],
    ),
  ),
  slowLink(
    'A slow 2.4 GHz link: MLO can be worse',
    MloConfig(
      links: <MloLinkConfig>[
        MloLinkConfig(band: MloBand.ghz24, busyFraction: 0.2, meanBusyUs: 500),
        MloLinkConfig(band: MloBand.ghz6, busyFraction: 0.3, meanBusyUs: 300),
      ],
      arrivalsPerSecond: 300,
      airtimeSource: MloAirtimeSource.anatomy,
      aggregation: 8,
    ),
  ),
  switchCost(
    'EMLSR switch cost: one clean link',
    MloConfig(
      links: <MloLinkConfig>[
        MloLinkConfig(band: MloBand.ghz5, busyFraction: 0.05),
        MloLinkConfig(band: MloBand.ghz6, busyFraction: 0.7),
      ],
      arrivalsPerSecond: 700,
      paddingDelayUs: 256,
      transitionDelayUs: 256,
    ),
  );

  const MloPreset(this.label, this.config);

  final String label;
  final MloConfig config;
}

/// How much time the lanes show at once.
enum MloWindow {
  ms2('2 ms', 2000),
  ms5('5 ms', 5000),
  ms20('20 ms', 20000);

  const MloWindow(this.label, this.us);

  final String label;
  final double us;
}

/// Mean busy-period lengths offered, microseconds.
const List<double> kMloBusyLengthsUs = <double>[200, 500, 1000, 2000, 5000];

/// Fixed airtimes offered, microseconds.
const double kMloFixedAirtimeMinUs = 100;
const double kMloFixedAirtimeMaxUs = 2000;

/// Arrival rate slider bounds, frames per second.
const double kMloRateMin = 100;
const double kMloRateMax = 3000;

/// The MLO modes the student can switch on and off. Single link is always
/// shown: it is the baseline every mode is judged against.
const List<MloMode> kMloComparableModes = <MloMode>[
  MloMode.str,
  MloMode.nstr,
  MloMode.emlsr,
];

class MloSimulatorState extends ChangeNotifier {
  MloSimulatorState({MloConfig? initial, MloPreset? preset})
    : _preset = initial == null ? (preset ?? MloPreset.equal) : preset {
    final MloConfig c = initial ?? _preset!.config;
    _bandSettings = <MloBand, MloLinkConfig>{
      for (final MloBand b in MloBand.values) b: MloLinkConfig(band: b),
      for (final MloLinkConfig l in c.links) l.band: l,
    };
    _config = c;
    _run = simulateMlo(c);
  }

  late MloConfig _config;
  late MloRun _run;
  MloPreset? _preset;

  /// Each band's settings, kept while the band is off so switching it back
  /// on restores them.
  late Map<MloBand, MloLinkConfig> _bandSettings;

  final Set<MloMode> _shown = <MloMode>{...kMloComparableModes};
  MloMode _laneMode = MloMode.str;
  MloWindow _window = MloWindow.ms5;
  double _windowStartUs = 0;

  // ── Read side ─────────────────────────────────────────────────────────────

  MloConfig get config => _config;
  MloRun get run => _run;

  /// The lesson the inputs came from, or null once the student changes one.
  MloPreset? get preset => _preset;

  /// MLO modes shown in the readouts and histograms, in mode order.
  List<MloMode> get shownModes => <MloMode>[
    for (final MloMode m in kMloComparableModes)
      if (_shown.contains(m)) m,
  ];

  bool isShown(MloMode m) => m == MloMode.single || _shown.contains(m);

  /// Which mode the lanes draw.
  MloMode get laneMode => _laneMode;

  MloWindow get window => _window;
  double get windowStartUs => _windowStartUs;
  double get windowEndUs => _windowStartUs + _window.us;

  /// Latest useful start for the lane window.
  double get windowStartMaxUs {
    final double last = _run.arrivalsUs.last;
    return last > _window.us ? last - _window.us : 0;
  }

  bool bandEnabled(MloBand b) =>
      _config.links.any((MloLinkConfig l) => l.band == b);

  MloLinkConfig bandSettings(MloBand b) => _bandSettings[b]!;

  /// Index of [b] in the run's links, or null when it is off.
  int? linkIndex(MloBand b) {
    final int i = _config.links.indexWhere((MloLinkConfig l) => l.band == b);
    return i < 0 ? null : i;
  }

  /// The result the lanes draw: for Single link, the best single link.
  MloModeResult get laneResult => _run.result(_laneMode);

  /// Modes whose results the student compares: best single, then the shown
  /// MLO modes.
  List<MloMode> get comparedModes => <MloMode>[MloMode.single, ...shownModes];

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _apply(MloConfig next, {bool keepPreset = false}) {
    if (!keepPreset) _preset = null;
    if (next == _config) {
      notifyListeners();
      return;
    }
    _config = next;
    _run = simulateMlo(next);
    _windowStartUs = _windowStartUs.clamp(0.0, windowStartMaxUs);
    notifyListeners();
  }

  set preset(MloPreset? p) {
    if (p == null) return;
    _preset = p;
    _bandSettings = <MloBand, MloLinkConfig>{
      for (final MloBand b in MloBand.values) b: MloLinkConfig(band: b),
      for (final MloLinkConfig l in p.config.links) l.band: l,
    };
    _apply(p.config.copyWith(seed: _config.seed), keepPreset: true);
  }

  List<MloLinkConfig> _linksFor(Set<MloBand> on) => <MloLinkConfig>[
    for (final MloBand b in MloBand.values)
      if (on.contains(b)) _bandSettings[b]!,
  ];

  /// Switch a band's link on or off. The last link cannot be switched off.
  void setBandEnabled(MloBand b, bool on) {
    final Set<MloBand> bands = <MloBand>{
      for (final MloLinkConfig l in _config.links) l.band,
    };
    if (on) {
      bands.add(b);
    } else {
      if (bands.length <= 1) return;
      bands.remove(b);
    }
    _apply(_config.copyWith(links: _linksFor(bands)));
  }

  void _setBand(MloBand b, MloLinkConfig l) {
    _bandSettings[b] = l;
    _apply(
      _config.copyWith(
        links: <MloLinkConfig>[
          for (final MloLinkConfig x in _config.links) x.band == b ? l : x,
        ],
      ),
    );
  }

  void setBusyFraction(MloBand b, double f) => _setBand(
    b,
    _bandSettings[b]!.copyWith(busyFraction: f.clamp(0, kMloMaxBusyFraction)),
  );

  void setMeanBusyUs(MloBand b, double us) =>
      _setBand(b, _bandSettings[b]!.copyWith(meanBusyUs: us));

  set arrivalsPerSecond(double v) =>
      _apply(_config.copyWith(arrivalsPerSecond: v));

  set airtimeSource(MloAirtimeSource s) =>
      _apply(_config.copyWith(airtimeSource: s));

  set fixedAirtimeUs(double v) => _apply(_config.copyWith(fixedAirtimeUs: v));

  set mcs(int v) => _apply(_config.copyWith(mcs: v));

  set aggregation(int v) => _apply(_config.copyWith(aggregation: v));

  set paddingDelayUs(int v) => _apply(_config.copyWith(paddingDelayUs: v));

  set transitionDelayUs(int v) =>
      _apply(_config.copyWith(transitionDelayUs: v));

  set emlsrDisabledByDriver(bool v) =>
      _apply(_config.copyWith(emlsrDisabledByDriver: v));

  /// New random traffic: the next seed. Keeps the lesson.
  void newTraffic() =>
      _apply(_config.copyWith(seed: _config.seed + 1), keepPreset: true);

  void setModeShown(MloMode m, bool shown) {
    if (m == MloMode.single) return;
    if (shown) {
      _shown.add(m);
    } else {
      _shown.remove(m);
      if (_laneMode == m) _laneMode = MloMode.single;
    }
    notifyListeners();
  }

  set laneMode(MloMode m) {
    if (m == _laneMode) return;
    _laneMode = m;
    if (m != MloMode.single) _shown.add(m);
    notifyListeners();
  }

  set window(MloWindow w) {
    if (w == _window) return;
    _window = w;
    _windowStartUs = _windowStartUs.clamp(0.0, windowStartMaxUs);
    notifyListeners();
  }

  set windowStartUs(double us) {
    _windowStartUs = us.clamp(0.0, windowStartMaxUs);
    notifyListeners();
  }

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final MloConfig c = _config;
    final MloRun r = _run;
    final StringBuffer b = StringBuffer()
      ..writeln('Multi-Link Operation (WLAN Pros Toolbox, teaching model)');
    for (int k = 0; k < c.links.length; k++) {
      final MloLinkConfig l = c.links[k];
      b.writeln(
        'Link ${l.band.label}: busy ${(l.busyFraction * 100).round()}%, '
        'mean busy period ${mloFmtUs(l.meanBusyUs)}, frame airtime '
        '${mloFmtUs(r.airtimeUs[k])}',
      );
    }
    b
      ..writeln(
        'Frames: ${c.frameCount} at ${c.arrivalsPerSecond.round()} per '
        'second, seed ${c.seed}',
      )
      ..writeln(
        'EMLSR: padding ${c.paddingDelayUs} µs, transition '
        '${c.transitionDelayUs} µs'
        '${c.emlsrDisabledByDriver ? ', disabled by driver' : ''}',
      );
    for (final MloModeResult s in r.singles) {
      b.writeln(
        'Single link ${c.links[s.singleLink!].band.label}: '
        '${_stats(s)}',
      );
    }
    for (final MloMode m in shownModes) {
      final String worse = r.worseThanBestSingle(m)
          ? ' (worse than the best single link)'
          : '';
      b.writeln('${m.label}: ${_stats(r.result(m))}$worse');
    }
    b.writeln(
      'A teaching model. The one published MLO latency study is a model '
      'built on real traffic, not a field measurement.',
    );
    return b.toString().trimRight();
  }

  static String _stats(MloModeResult r) => r.overloaded
      ? 'overloaded (latency grows with the run)'
      : 'mean ${mloFmtUs(r.meanUs)}, 99th percentile ${mloFmtUs(r.p99Us)}';
}
