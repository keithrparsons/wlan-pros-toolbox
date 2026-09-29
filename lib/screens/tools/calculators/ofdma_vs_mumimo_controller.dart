// State for OFDMA vs MU-MIMO (Wi-Fi Classroom): the scenario, where each
// client sits, which client the move buttons act on, and the computed result.
//
// A ChangeNotifier so the stage (OfdmaVsMumimoStage) and the controls
// (OfdmaVsMumimoControls) stay separate widgets over one shared state. The
// phone screen stacks them; the presenter layout places them side by side.
//
// SCENARIOS are Keith's four (2026-09-29). Any edit leaves the preset, and
// the scenario select then reads "Your own layout" until a preset is picked
// again.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart' show formatTenthsUs;
import '../../../services/wifi_lab/mu_mimo_model.dart';
import '../../../services/wifi_lab/ofdma_model.dart' show clientLetter;
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kOfdmaVsMumimoToolId = 'ofdma-vs-mumimo';

/// The room drawing's possible spans, meters.
const List<double> kMuViewRadiiM = <double>[15, 25, MuLimits.maxDistanceM];

/// Angle step of the Turn buttons, degrees.
const double kMuTurnStepDeg = 5;

/// Distance step of the Closer and Farther buttons, meters.
const double kMuDistanceStepM = 2;

class OfdmaVsMumimoController extends ChangeNotifier {
  OfdmaVsMumimoController({MuPreset preset = MuPreset.spreadBig}) {
    _load(preset);
    _recompute();
  }

  MuPreset? _preset;
  late int _antennas;
  late List<MuClient> _clients;
  late int _width;
  late int _payload;
  late int _exchanges;
  bool _reflection = false;
  int _selected = 0;
  bool _showWorking = false;
  UnitSystem _units = UnitSystem.metric;
  late MuResult _result;

  /// The preset on screen, or null once anything was edited.
  MuPreset? get preset => _preset;
  int get antennas => _antennas;
  List<MuClient> get clients => List<MuClient>.unmodifiable(_clients);
  int get clientCount => _clients.length;
  int get widthMhz => _width;
  int get payloadBytes => _payload;
  int get exchanges => _exchanges;
  bool get reflection => _reflection;
  int get selected => _selected;
  bool get showWorking => _showWorking;
  UnitSystem get units => _units;
  MuResult get result => _result;

  double? _frozenView;

  /// Meters the room drawing spans: 15, 25 or 35, the smallest that shows
  /// the farthest client with room to spare. Held still during a drag.
  double get viewRadiusM {
    final double? f = _frozenView;
    if (f != null) return f;
    final double far = _clients
        .map((MuClient c) => c.distanceM)
        .reduce(math.max);
    for (final double v in kMuViewRadiiM) {
      if (far + 3 <= v) return v;
    }
    return kMuViewRadiiM.last;
  }

  /// A drag started: keep the scale until it ends.
  void beginDrag() => _frozenView = viewRadiusM;

  void endDrag() {
    if (_frozenView == null) return;
    _frozenView = null;
    notifyListeners();
  }

  // ── Edits ─────────────────────────────────────────────────────────────────

  void applyPreset(MuPreset p) {
    _load(p);
    _afterEdit(keepPreset: true);
  }

  /// Right arrow in presenter mode: the next scenario (wrapping).
  void nextPreset() {
    final int i = _preset == null ? -1 : _preset!.index;
    applyPreset(MuPreset.values[(i + 1) % MuPreset.values.length]);
  }

  /// R in presenter mode: back to the current scenario as it started (the
  /// first scenario when the layout is your own).
  void resetLayout() => applyPreset(_preset ?? MuPreset.values.first);

  void setAntennas(int m) {
    final int next = m.clamp(MuLimits.minAntennas, MuLimits.maxAntennas);
    if (next == _antennas) return;
    _antennas = next;
    _afterEdit();
  }

  void setClientCount(int k) {
    final int next = k.clamp(MuLimits.minClients, MuLimits.maxClients);
    if (next == _clients.length) return;
    if (next < _clients.length) {
      _clients = _clients.sublist(0, next);
    } else {
      final List<MuClient> out = <MuClient>[..._clients];
      while (out.length < next) {
        out.add(MuClient(angleDeg: _freestAngle(out), distanceM: 10));
      }
      _clients = out;
    }
    _selected = math.min(_selected, _clients.length - 1);
    _afterEdit();
  }

  void setWidth(int w) {
    if (w == _width || !MuLimits.widthsMhz.contains(w)) return;
    _width = w;
    _afterEdit();
  }

  void setPayload(int bytes) {
    if (bytes == _payload) return;
    _payload = bytes;
    _afterEdit();
  }

  void setExchanges(int n) {
    if (n == _exchanges || n < 1) return;
    _exchanges = n;
    _afterEdit();
  }

  void setReflection(bool on) {
    if (on == _reflection) return;
    _reflection = on;
    _afterEdit();
  }

  /// Puts client [i] at [c] (a drag on the stage).
  void moveClient(int i, MuClient c) {
    if (i < 0 || i >= _clients.length) return;
    final MuClient clamped = MuClient(
      angleDeg: c.angleDeg.clamp(-90.0, 90.0),
      distanceM: c.distanceM.clamp(
        MuLimits.minDistanceM,
        MuLimits.maxDistanceM,
      ),
    );
    if (clamped == _clients[i]) return;
    _clients = <MuClient>[..._clients]..[i] = clamped;
    _selected = i;
    _afterEdit();
  }

  /// Turns the selected client by [deg] around the AP (positive = right).
  void turnSelected(double deg) {
    final MuClient c = _clients[_selected];
    moveClient(_selected, c.copyWith(angleDeg: c.angleDeg + deg));
  }

  /// Moves the selected client [m] meters farther (negative = closer).
  void stepSelectedDistance(double m) {
    final MuClient c = _clients[_selected];
    moveClient(_selected, c.copyWith(distanceM: c.distanceM + m));
  }

  bool get canTurnLeft => _clients[_selected].angleDeg > -90;
  bool get canTurnRight => _clients[_selected].angleDeg < 90;
  bool get canCloser => _clients[_selected].distanceM > MuLimits.minDistanceM;
  bool get canFarther => _clients[_selected].distanceM < MuLimits.maxDistanceM;

  void select(int i) {
    if (i == _selected || i < 0 || i >= _clients.length) return;
    _selected = i;
    notifyListeners();
  }

  void toggleWorking() {
    _showWorking = !_showWorking;
    notifyListeners();
  }

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  /// Right: next scenario. Up and Down: the client count. R: reset.
  PresenterActions get presenterActions => PresenterActions(
    step: nextPreset,
    stepLabel: 'Next scenario',
    sliderDown: () => setClientCount(clientCount - 1),
    sliderUp: () => setClientCount(clientCount + 1),
    sliderLabel: 'Clients',
    reset: resetLayout,
  );

  // ── Text shared by the stage, the controls and Copy ───────────────────────

  /// "20 deg right, 8 m" for client [i].
  String placeOf(int i) {
    final MuClient c = _clients[i];
    return '${muAngleText(c.angleDeg)}, ${LengthFormat(_units).dist(c.distanceM)}';
  }

  String copyText() {
    final MuResult r = _result;
    final StringBuffer b = StringBuffer()
      ..writeln('OFDMA vs MU-MIMO (WLAN Pros Toolbox)')
      ..writeln(
        '${_preset?.label ?? 'Your own layout'}: $_antennas AP antennas, '
        '$clientCount clients, $_width MHz, $_payload-byte frames, '
        '$_exchanges ${_exchanges == 1 ? 'exchange' : 'exchanges'} per '
        'sounding, reflection ${_reflection ? 'on' : 'off'}',
      );
    for (int i = 0; i < clientCount; i++) {
      final MuClientLink l = r.links[i];
      b.writeln(
        '  ${clientLetter(i)}: ${placeOf(i)}; zero-forcing loss '
        '${muLossText(l.zfLossDb)}; MCS ${l.ofdmaMcs ?? '--'} in OFDMA, '
        '${l.muMcs ?? '--'} in MU-MIMO',
      );
    }
    for (final MuPair p in r.precoding.pairs) {
      b.writeln(
        '  ${clientLetter(p.a)} and ${clientLetter(p.b)}: '
        '${p.separable ? 'separable' : 'not separable'} '
        '(${muLossText(p.lossDb)} as a pair)',
      );
    }
    b
      ..writeln(
        'OFDMA: ${r.ofdma == null ? '--' : '${formatTenthsUs(r.ofdma!.totalTenths)} µs'}',
      )
      ..writeln(
        'MU-MIMO: ${r.mu == null ? '--' : '${formatTenthsUs(r.mu!.totalTenths)} µs, of which sounding ${formatTenthsUs(r.soundingTenths)} µs'}',
      )
      ..writeln('Which wins here: ${muVerdictHeadline(r)}');
    final String? why = muVerdictWhy(r);
    if (why != null) b.writeln(why);
    b.writeln(
      'Teaching model: zero-forcing on a line-of-sight channel; airtime '
      'estimates as listed in the tool.',
    );
    return b.toString().trimRight();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _load(MuPreset p) {
    final MuScenario s = p.scenario;
    _preset = p;
    _antennas = s.antennas;
    _clients = <MuClient>[...s.clients];
    _width = s.widthMhz;
    _payload = s.payloadBytes;
    _exchanges = s.exchangesPerSounding;
    _reflection = s.reflection;
    _selected = 0;
  }

  /// The candidate angle farthest from every client already placed.
  static double _freestAngle(List<MuClient> taken) {
    const List<double> candidates = <double>[
      -60,
      -40,
      -20,
      0,
      20,
      40,
      60,
      -75,
      75,
    ];
    double best = candidates.first;
    double bestGap = -1;
    for (final double a in candidates) {
      double gap = double.infinity;
      for (final MuClient c in taken) {
        gap = math.min(gap, (c.angleDeg - a).abs());
      }
      if (gap > bestGap) {
        bestGap = gap;
        best = a;
      }
    }
    return best;
  }

  void _recompute() {
    _result = computeMuVsOfdma(
      MuScenario(
        antennas: _antennas,
        clients: _clients,
        widthMhz: _width,
        payloadBytes: _payload,
        exchangesPerSounding: _exchanges,
        reflection: _reflection,
      ),
    );
  }

  void _afterEdit({bool keepPreset = false}) {
    if (!keepPreset) _preset = null;
    _recompute();
    notifyListeners();
  }
}

/// "20 deg right", "straight ahead", "35 deg left".
String muAngleText(double deg) {
  final int d = deg.round();
  if (d == 0) return 'straight ahead';
  return '${d.abs()} deg ${d > 0 ? 'right' : 'left'}';
}

/// "0.3 dB", or "no null possible" for an infinite loss.
String muLossText(double db) =>
    db.isFinite ? '${db.toStringAsFixed(1)} dB' : 'no null possible';

/// Why MU-MIMO could not run, one sentence; empty when it ran.
String muBlockReason(MuResult r) {
  final int k = r.scenario.k;
  switch (r.block) {
    case null:
      return '';
    case MuBlock.outOfRange:
      final int i = r.links.indexWhere((MuClientLink l) => l.ofdmaMcs == null);
      return 'Client ${clientLetter(math.max(0, i))} is out of range even '
          'alone.';
    case MuBlock.tooManyClients:
      return 'Zero-forcing needs at least $k AP antennas for $k clients.';
    case MuBlock.singular:
      return 'Two clients share one direction, so no null can split them.';
    case MuBlock.lossTooHigh:
      int worst = 0;
      for (int i = 1; i < r.links.length; i++) {
        if (r.links[i].zfLossDb > r.links[worst].zfLossDb) worst = i;
      }
      return 'Zero-forcing costs client ${clientLetter(worst)} '
          '${muLossText(r.links[worst].zfLossDb)}, too much to decode.';
  }
}

/// The verdict, one line.
String muVerdictHeadline(MuResult r) {
  String us(int t) => '${formatTenthsUs(t.abs())} µs';
  switch (r.winner) {
    case MuWinner.outOfRange:
      final int i = r.links.indexWhere((MuClientLink l) => l.ofdmaMcs == null);
      return 'Neither: client ${clientLetter(i)} is out of range even alone.';
    case MuWinner.muUnavailable:
      return 'OFDMA. ${muBlockReason(r)}';
    case MuWinner.tie:
      return 'About even: within ${(MuResult.tieShare * 100).round()}% of '
          'each other.';
    case MuWinner.muMimo:
    case MuWinner.ofdma:
      final int saved = r.savedTenths!;
      final int loser = saved > 0 ? r.ofdma!.totalTenths : r.mu!.totalTenths;
      final int pct = (saved.abs() * 100 / loser).round();
      return '${r.winner == MuWinner.muMimo ? 'MU-MIMO' : 'OFDMA'}, by '
          '${us(saved)} ($pct% less airtime).';
  }
}

/// Why, in one sentence built from the numbers; null when MU-MIMO did not
/// run.
String? muVerdictWhy(MuResult r) {
  if (r.mu == null || r.ofdma == null) return null;
  String us(int t) => '${formatTenthsUs(t.abs())} µs';
  final int n = r.exchanges;
  final int data = r.ofdmaDataTenths - r.muDataTenths;
  final int pre = r.muPreambleTenthsEach - r.ofdmaPreambleTenths;
  final String dataPart = data >= 0
      ? 'MU-MIMO sends the data ${us(data)} faster'
      : 'MU-MIMO sends the data ${us(data)} slower';
  final String prePart = pre == 0
      ? ''
      : (pre > 0
            ? ', its preamble is ${us(pre)} longer (a training symbol for each stream)'
            : ', its preamble is ${us(pre)} shorter');
  final int net = n * (data - pre);
  final String over = '$n ${n == 1 ? 'exchange' : 'exchanges'}';
  if (net < 0) {
    return 'Each exchange: $dataPart$prePart. Over $over MU-MIMO is already '
        '${us(net)} behind, before ${us(r.soundingTenths)} of sounding.';
  }
  return 'Each exchange: $dataPart$prePart. Over $over that saves '
      '${us(net)}, against ${us(r.soundingTenths)} of sounding.';
}
