// Mode 4 state for the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft): OFDM
// is an inverse FFT. Owned by FourierLabModel (the one shared state object);
// every setter calls back into it.
//
// Two views:
//   - Teaching: N = 16, subcarriers k = -8 .. +7, each toggled on or off.
//   - Real Wi-Fi: one 20 MHz channel. Legacy N = 64 with 52 subcarriers,
//     HE N = 256 with the 242-tone RU. No toggles; all used subcarriers on.
// The numerology switch (legacy / HE) keeps the indices and changes the
// spacing, so the symbol stretches 4x. The channel center never moves.

import 'package:flutter/foundation.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../services/wifi_lab/fourier_ofdm.dart';

enum OfdmView {
  teaching('Teaching (16 subcarriers)'),
  real('Real Wi-Fi (20 MHz)');

  const OfdmView(this.label);
  final String label;
}

/// Modulations offered: the Modulation Simulator's set up to 1024-QAM.
const List<Modulation> kOfdmModulations = <Modulation>[
  Modulation.bpsk,
  Modulation.qpsk,
  Modulation.qam16,
  Modulation.qam64,
  Modulation.qam256,
  Modulation.qam1024,
];

class FourierOfdmState {
  FourierOfdmState(this._onChanged);

  final VoidCallback _onChanged;

  OfdmView _view = OfdmView.teaching;
  OfdmNumerology _numerology = OfdmNumerology.legacy;
  double _guard = OfdmNumerology.legacy.guardOptionsSeconds.first;
  Modulation _modulation = Modulation.qpsk;
  int _seed = 1;
  Set<int> _teachingOn = <int>{1, 2, 3};
  int? _highlight = 1;
  bool _sameTimeScale = true;

  OfdmSymbol? _symbol;
  List<RecoveredPoint>? _recovered;
  Object? _key;

  OfdmView get view => _view;
  OfdmNumerology get numerology => _numerology;
  double get guardSeconds => _guard;
  Modulation get modulation => _modulation;
  int get seed => _seed;
  bool get sameTimeScale => _sameTimeScale;

  /// IFFT size for the current view.
  int get n =>
      _view == OfdmView.teaching ? OfdmMath.teachingN : _numerology.realFftSize;

  /// Active subcarrier indices, lowest first.
  List<int> get activeIndices => _view == OfdmView.teaching
      ? (_teachingOn.toList()..sort())
      : _numerology.realUsedIndices;

  bool isOn(int k) => _teachingOn.contains(k);
  bool get isEmpty => activeIndices.isEmpty;

  /// The subcarrier drawn in lime, or null when none is on.
  int? get highlight {
    final List<int> on = activeIndices;
    if (on.isEmpty) return null;
    final int? h = _highlight;
    if (h != null && on.contains(h)) return h;
    // Fall back to the lowest positive index, else the first.
    return on.firstWhere((int k) => k > 0, orElse: () => on.first);
  }

  OfdmSymbol get symbol {
    _ensure();
    return _symbol!;
  }

  /// The receiver's FFT output on each active subcarrier.
  List<RecoveredPoint> get recovered {
    _ensure();
    return _recovered!;
  }

  /// Largest error between a recovered and a sent point (0 when none on).
  double get maxRecoveryError {
    double m = 0;
    for (final RecoveredPoint p in recovered) {
      if (p.error > m) m = p.error;
    }
    return m;
  }

  void _ensure() {
    final List<int> on = activeIndices;
    final Object key = (
      _view,
      _numerology,
      _guard,
      _modulation,
      _seed,
      on.join(','),
    );
    if (_symbol != null && key == _key) return;
    _symbol = OfdmMath.build(
      numerology: _numerology,
      n: n,
      guardSeconds: _guard,
      points: OfdmMath.randomPoints(
        indices: on,
        modulation: _modulation,
        seed: _seed,
      ),
    );
    _recovered = OfdmMath.receive(_symbol!);
    _key = key;
  }

  void setView(OfdmView v) {
    if (v == _view) return;
    _view = v;
    _onChanged();
  }

  void setNumerology(OfdmNumerology v) {
    if (v == _numerology) return;
    _numerology = v;
    if (!v.guardOptionsSeconds.contains(_guard)) {
      _guard = v.guardOptionsSeconds.first;
    }
    _onChanged();
  }

  void setGuard(double g) {
    if (g == _guard || !_numerology.guardOptionsSeconds.contains(g)) return;
    _guard = g;
    _onChanged();
  }

  void setModulation(Modulation m) {
    if (m == _modulation) return;
    _modulation = m;
    _onChanged();
  }

  void newData() {
    _seed++;
    _onChanged();
  }

  void toggle(int k) {
    if (!OfdmMath.teachingIndices.contains(k)) return;
    final Set<int> next = Set<int>.of(_teachingOn);
    if (!next.remove(k)) {
      next.add(k);
      _highlight = k;
    }
    _teachingOn = next;
    _onChanged();
  }

  void allOn() {
    _teachingOn = Set<int>.of(OfdmMath.teachingIndices);
    _onChanged();
  }

  void allOff() {
    if (_teachingOn.isEmpty) return;
    _teachingOn = <int>{};
    _onChanged();
  }

  void setHighlight(int k) {
    if (!activeIndices.contains(k) || k == highlight) return;
    _highlight = k;
    _onChanged();
  }

  void setSameTimeScale(bool v) {
    if (v == _sameTimeScale) return;
    _sameTimeScale = v;
    _onChanged();
  }
}
