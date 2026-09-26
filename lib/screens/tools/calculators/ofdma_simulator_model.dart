// State for OFDMA Resource Units (Wi-Fi Classroom): the inputs, where each client's
// RU sits in the channel, which client is selected, and the computed result.
//
// A ChangeNotifier so the stage (OfdmaSimulatorStage) and the controls
// (OfdmaSimulatorControls) stay separate widgets over one shared model. The
// phone screen stacks them; a presenter layout can place them side by side.
//
// PLACEMENT RULES. Every client always has a place when the set fits: after
// any change that frees or needs room, unplaced clients go to the first free
// position, and if that fails but a full re-pack would succeed, everything
// is re-packed (and the notice says so). A move only lands on a free valid
// position of the client's RU size, or swaps with one client of the same
// size sitting exactly there. So "fits but unplaced" never persists.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Which OFDMA direction the readouts compare with SU.
enum OfdmaDirection {
  dl('Downlink', 'AP to clients', OfdmaMode.dl),
  ul('Uplink', 'Clients to AP', OfdmaMode.ul);

  const OfdmaDirection(this.label, this.detail, this.mode);

  final String label;
  final String detail;
  final OfdmaMode mode;
}

/// Frame sizes offered, bytes (the MSDU).
const List<int> kOfdmaPayloadChoices = <int>[64, 100, 200, 500, 1000, 1500];

/// The most clients the screen shows, whatever the width: letters A to R.
const int kOfdmaMaxClients = 18;

class OfdmaSimulatorModel extends ChangeNotifier {
  OfdmaSimulatorModel() {
    _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
    _recompute();
  }

  // The research brief's worked example.
  int _width = 20;
  List<RuSize> _sizes = List<RuSize>.filled(4, RuSize.ru52);
  late List<RuSpan?> _placement;
  int _payload = 200;
  int _mcs = 7;
  OfdmaDirection _direction = OfdmaDirection.dl;
  int? _selected;
  String? _notice;
  bool _showWorking = false;
  late OfdmaResult _result;

  int get widthMhz => _width;
  int get clients => _sizes.length;
  List<RuSize> get sizes => List<RuSize>.unmodifiable(_sizes);
  List<RuSpan?> get placement => List<RuSpan?>.unmodifiable(_placement);
  int get payloadBytes => _payload;
  int get mcs => _mcs;
  OfdmaDirection get direction => _direction;
  OfdmaResult get result => _result;
  bool get showWorking => _showWorking;

  /// The client the RU-size control and the move buttons act on; null = all.
  int? get selected => _selected;

  /// The last placement message (a move refused, a re-pack), or null.
  String? get notice => _notice;

  /// Clients the width allows: one per 26-tone RU, capped at [kOfdmaMaxClients].
  int get maxClients => math.min(OfdmaTonePlan.slots(_width), kOfdmaMaxClients);

  List<int> get unplaced => <int>[
    for (int i = 0; i < _placement.length; i++)
      if (_placement[i] == null) i,
  ];

  /// Microseconds the full bar width represents: the longest drawable
  /// timeline.
  double get scaleUs {
    double m = _result.su.totalUs;
    for (final OfdmaTimeline? t in <OfdmaTimeline?>[_result.dl, _result.ul]) {
      if (t != null && !t.ppduTooLong) m = math.max(m, t.totalUs);
    }
    return m;
  }

  /// Free positions the selected client could move to (excluding its own).
  List<RuSpan> targetsFor(int client) {
    final RuSize size = _sizes[client];
    final List<RuSpan> out = <RuSpan>[];
    for (final RuSpan p in OfdmaTonePlan.positions(_width, size)) {
      if (p == _placement[client]) continue;
      if (_blockers(client, p).isEmpty) out.add(p);
    }
    return out;
  }

  // ── Edits ─────────────────────────────────────────────────────────────────

  void setWidth(int w) {
    if (w == _width) return;
    _width = w;
    final List<RuSize> allowed = OfdmaTonePlan.sizesFor(w);
    _sizes = <RuSize>[
      for (final RuSize s in _sizes.take(maxClients))
        allowed.contains(s) ? s : allowed.last,
    ];
    if (_selected != null && _selected! >= _sizes.length) _selected = null;
    _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
    _notice = null;
    _afterEdit();
  }

  void setClientCount(int n) {
    final int next = n.clamp(1, maxClients);
    if (next == _sizes.length) return;
    _notice = null;
    if (next < _sizes.length) {
      _sizes = _sizes.sublist(0, next);
      _placement = _placement.sublist(0, next);
      if (_selected != null && _selected! >= next) _selected = null;
    } else {
      final RuSize add = _sizes.last;
      _sizes = <RuSize>[
        ..._sizes,
        for (int i = _sizes.length; i < next; i++) add,
      ];
      _placement = <RuSpan?>[
        ..._placement,
        for (int i = _placement.length; i < next; i++) null,
      ];
      _fillUnplaced();
    }
    _afterEdit();
  }

  /// Sets the RU size of the selected client, or of every client.
  void setRuSize(RuSize size) {
    if (OfdmaTonePlan.count(size, _width) == null) return;
    _notice = null;
    final int? c = _selected;
    if (c == null) {
      _sizes = List<RuSize>.filled(_sizes.length, size);
      _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
    } else {
      if (_sizes[c] == size) return;
      _sizes = <RuSize>[..._sizes]..[c] = size;
      _placement = <RuSpan?>[..._placement]..[c] = null;
      _fillUnplaced();
    }
    _afterEdit();
  }

  /// Gives every client the largest equal RU that fits, and re-packs.
  void equalRus() {
    _sizes = List<RuSize>.filled(
      _sizes.length,
      OfdmaTonePlan.largestEqualFit(_width, _sizes.length),
    );
    _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
    _notice = null;
    _afterEdit();
  }

  /// Re-packs the current sizes from the low edge of the channel.
  void autoPlace() {
    _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
    _notice = null;
    _afterEdit();
  }

  void setPayload(int bytes) {
    if (bytes == _payload) return;
    _payload = bytes;
    _afterEdit();
  }

  void setMcs(int m) {
    if (m == _mcs) return;
    _mcs = m;
    _afterEdit();
  }

  void setDirection(OfdmaDirection d) {
    if (d == _direction) return;
    _direction = d;
    notifyListeners();
  }

  void toggleWorking() {
    _showWorking = !_showWorking;
    notifyListeners();
  }

  /// Selects [client] (null = all); selecting the same one again clears it.
  void select(int? client) {
    _selected = client == _selected ? null : client;
    _notice = null;
    notifyListeners();
  }

  /// Sets the selection without toggling (the Client dropdown).
  void setSelected(int? client) {
    if (client == _selected) return;
    _selected = client;
    _notice = null;
    notifyListeners();
  }

  /// Moves [client] to the position of its RU size that covers [slot].
  /// Returns true when it moved.
  bool moveTo(int client, int slot) {
    final RuSize size = _sizes[client];
    final RuSpan? target = OfdmaTonePlan.positionAt(_width, size, slot);
    if (target == null) {
      _notice =
          'A ${size.toneLabel} RU cannot sit there: that slot is the center '
          '26-tone RU, which only a 26-tone RU can use.';
      notifyListeners();
      return false;
    }
    if (target == _placement[client]) {
      _notice = null;
      notifyListeners();
      return false;
    }
    final List<int> blockers = _blockers(client, target);
    if (blockers.isEmpty) {
      _placement = <RuSpan?>[..._placement]..[client] = target;
      _notice = null;
      _afterEdit();
      return true;
    }
    if (blockers.length == 1 &&
        _placement[blockers.first] == target &&
        _placement[client] != null) {
      final int other = blockers.first;
      _placement = <RuSpan?>[..._placement]
        ..[other] = _placement[client]
        ..[client] = target;
      _notice = 'Swapped ${clientLetter(client)} and ${clientLetter(other)}.';
      _afterEdit();
      return true;
    }
    _notice =
        'That spot overlaps ${blockers.map(clientLetter).join(', ')}. A '
        '${size.toneLabel} RU can only go where the tone plan has one free.';
    notifyListeners();
    return false;
  }

  /// Moves [client] to the next free position left (-1) or right (+1).
  void nudge(int client, int step) {
    final List<RuSpan> all = OfdmaTonePlan.positions(_width, _sizes[client]);
    final RuSpan? here = _placement[client];
    final int from = here == null
        ? (step > 0 ? -1 : all.length)
        : all.indexOf(here);
    for (int i = from + step; i >= 0 && i < all.length; i += step) {
      if (_blockers(client, all[i]).isEmpty) {
        moveTo(client, all[i].start);
        return;
      }
    }
    _notice =
        'No free ${_sizes[client].toneLabel} RU to the '
        '${step < 0 ? 'left' : 'right'} of ${clientLetter(client)}.';
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  List<int> _blockers(int client, RuSpan p) => <int>[
    for (int i = 0; i < _placement.length; i++)
      if (i != client && _placement[i] != null && _placement[i]!.overlaps(p)) i,
  ];

  // ── Presenter keys ─────────────────────────────────────────────────────────

  /// Right arrow: select the next client (A, B, ... then none), so the
  /// dashed outlines show where each one could go.
  void selectNext() {
    final int? cur = _selected;
    setSelected(cur == null ? 0 : (cur + 1 < clients ? cur + 1 : null));
  }

  /// Up and Down arrows: the number of clients.
  PresenterActions get presenterActions => PresenterActions(
    step: selectNext,
    sliderDown: () => setClientCount(clients - 1),
    sliderUp: () => setClientCount(clients + 1),
    sliderLabel: 'Clients',
  );

  void _fillUnplaced() {
    bool missed = false;
    for (int i = 0; i < _placement.length; i++) {
      if (_placement[i] != null) continue;
      final RuSpan? p = OfdmaTonePlan.firstFree(_width, _sizes[i], <RuSpan>[
        for (final RuSpan? s in _placement) ?s,
      ]);
      _placement = <RuSpan?>[..._placement]..[i] = p;
      if (p == null) missed = true;
    }
    if (missed && OfdmaTonePlan.fits(_width, _sizes)) {
      _placement = OfdmaTonePlan.autoPlace(_width, _sizes);
      _notice = 'Rearranged the RUs to make room.';
    }
  }

  void _recompute() {
    _result = computeOfdma(
      OfdmaScenario(
        widthMhz: _width,
        ruSizes: _sizes,
        payloadBytes: _payload,
        mcs: _mcs,
      ),
    );
  }

  void _afterEdit() {
    _recompute();
    notifyListeners();
  }
}
