// State for the Wi-Fi Classroom Airtime Fairness tool (airtime-fairness).
//
// One ChangeNotifier holds the client drafts, the sharing rule, the payload
// and the round clock, so the stage and the controls are independent views
// over one object. The phone screen stacks them; the presenter layout puts
// the same views side by side over this same object (spec 00).
//
// THE CLOCK. The round's Ticker is constructed here directly, not from a
// widget's TickerProvider: the route under the presenter route is muted, and
// the round must keep playing while the presenter shows it. The round's
// progress is its own ValueNotifier, so a playing round repaints the lanes
// without rebuilding every card each frame; this object notifies only when
// an input or the play state changes.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'airtime_fairness_common.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kAirtimeFairnessToolId = 'airtime-fairness';

/// How long one full round takes to play.
const Duration kAirtimeRoundDuration = Duration(milliseconds: 2400);

class AirtimeFairnessController extends ChangeNotifier {
  AirtimeFairnessController() {
    _ticker = Ticker(_onTick, debugLabel: 'airtime-fairness-round');
  }

  int _nextId = 0;

  /// Spec defaults: three clients at 867 Mbps sending 32 frames per turn,
  /// plus one legacy client at 6 Mbps with no aggregation.
  late List<AirtimeClientDraft> _clients = _defaultClients();
  FairnessView _view = FairnessView.compare;
  int _payload = AirtimeConstants.defaultPayloadBytes;

  late final Ticker _ticker;
  final ValueNotifier<double> _round = ValueNotifier<double>(0);
  double _playFrom = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  List<AirtimeClientDraft> _defaultClients() => <AirtimeClientDraft>[
    for (int i = 0; i < 3; i++)
      AirtimeClientDraft(
        id: _nextId++,
        preset: RatePreset.vht867,
        aggregation: 32,
      ),
    AirtimeClientDraft(id: _nextId++, preset: RatePreset.legacy6),
  ];

  // ── Read side ─────────────────────────────────────────────────────────────

  /// The drafts, in position order (letter A first).
  List<AirtimeClientDraft> get clients => _clients;
  FairnessView get view => _view;
  int get payloadBytes => _payload;

  /// 0 to 1 progress of the round. 1 draws it complete.
  ValueListenable<double> get round => _round;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;

  /// All client configs, or null while any row is invalid.
  List<ClientConfig>? get configs {
    final List<ClientConfig> out = <ClientConfig>[];
    for (final AirtimeClientDraft c in _clients) {
      final ClientConfig? cfg = c.toConfig();
      if (cfg == null) return null;
      out.add(cfg);
    }
    return out;
  }

  /// Index of the first invalid client, or null.
  int? get invalidClient {
    final int i = _clients.indexWhere(
      (AirtimeClientDraft c) => c.rateError != null,
    );
    return i < 0 ? null : i;
  }

  FairnessResult? result(FairnessMode mode) {
    final List<ClientConfig>? cs = configs;
    if (cs == null) return null;
    return computeFairness(cs, mode, payloadBytes: _payload);
  }

  /// The result sentence for the current view; null while a row is invalid.
  String? get takeaway {
    final FairnessResult? p = result(FairnessMode.packet);
    final FairnessResult? a = result(FairnessMode.airtime);
    if (p == null || a == null) return null;
    return airtimeTakeaway(p, a, _view);
  }

  // ── Round clock ───────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting from
  /// didChangeDependencies. With it on, the round is drawn complete and never
  /// plays by itself. It does not notify: the screen is rebuilding anyway,
  /// and a notification here would mark the presenter route dirty in the
  /// middle of this screen's build.
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) {
      _stop();
      _round.value = 1;
    }
  }

  /// Plays the round from the start, or draws it complete with reduced
  /// motion on.
  void replay() {
    if (_reducedMotion) {
      _stop();
      _round.value = 1;
      _notify();
      return;
    }
    _playFrom = 0;
    _round.value = 0;
    _start();
  }

  /// Space: pause a playing round, resume a paused one, or replay a finished
  /// one. Pressed by the user, so it plays even with reduced motion on.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    if (configs == null) return;
    _playFrom = _round.value >= 1 ? 0 : _round.value;
    _round.value = _playFrom;
    _start();
  }

  /// Right arrow: pause and draw up to the end of the next transmission in
  /// either lane.
  void stepTransmission() {
    final List<ClientConfig>? cs = configs;
    if (cs == null) return;
    _stop();
    final double window = roundWindowUs(cs, payloadBytes: _payload);
    if (window <= 0) return;
    final double shownUs = (_round.value >= 1 ? 0 : _round.value) * window;
    double next = window;
    for (final FairnessMode m in _view.modes) {
      for (final ScheduledTx tx in buildSchedule(
        cs,
        m,
        windowUs: window,
        payloadBytes: _payload,
      )) {
        if (tx.startUs >= window) break;
        final double end = tx.endUs < window ? tx.endUs : window;
        if (end > shownUs + 1e-6 && end < next) next = end;
      }
    }
    _round.value = (next / window).clamp(0.0, 1.0);
    _notify();
  }

  /// R: an empty round, paused, ready to play or step.
  void resetRound() {
    _stop();
    _round.value = 0;
    _notify();
  }

  void _start() {
    _playing = true;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double t =
        _playFrom +
        elapsed.inMicroseconds / kAirtimeRoundDuration.inMicroseconds;
    if (t >= 1) {
      _round.value = 1;
      _stop();
      _notify();
      return;
    }
    _round.value = t;
  }

  // ── Edits (each replays the round) ────────────────────────────────────────

  /// Apply [change] to a draft (or anything else) and replay.
  void edit(VoidCallback change) {
    change();
    _notify();
    replay();
  }

  set view(FairnessView v) {
    if (v == _view) return;
    edit(() => _view = v);
  }

  /// Up and Down arrows: the next or previous sharing rule.
  void shiftView(int delta) {
    const List<FairnessView> all = FairnessView.values;
    final int i = (all.indexOf(_view) + delta).clamp(0, all.length - 1);
    view = all[i];
  }

  set payloadBytes(int b) {
    if (b == _payload) return;
    edit(() => _payload = b);
  }

  void addClient() {
    if (_clients.length >= AirtimeConstants.maxClients) return;
    edit(
      () => _clients = <AirtimeClientDraft>[
        ..._clients,
        AirtimeClientDraft(id: _nextId++, preset: RatePreset.vht867),
      ],
    );
  }

  void removeClient(int id) {
    if (_clients.length <= AirtimeConstants.minClients) return;
    edit(() {
      final AirtimeClientDraft gone = _clients.firstWhere(
        (AirtimeClientDraft d) => d.id == id,
      );
      // Dispose after the row's TextField has detached from the controller.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => gone.controller.dispose(),
      );
      _clients = <AirtimeClientDraft>[
        for (final AirtimeClientDraft d in _clients)
          if (d.id != id) d,
      ];
    });
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: stepTransmission,
    reset: resetRound,
    sliderDown: () => shiftView(-1),
    sliderUp: () => shiftView(1),
    sliderLabel: 'Sharing rule',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String? copyText() {
    final List<ClientConfig>? cs = configs;
    if (cs == null) return null;
    final FairnessResult p = result(FairnessMode.packet)!;
    final FairnessResult a = result(FairnessMode.airtime)!;
    final StringBuffer b = StringBuffer()
      ..writeln('Airtime Fairness (WLAN Pros Toolbox)')
      ..writeln('Payload $_payload bytes per frame; downlink, no collisions')
      ..writeln(airtimeTakeaway(p, a, FairnessView.compare));
    for (int i = 0; i < cs.length; i++) {
      b.writeln(
        'Client ${clientLetter(i)}: ${rateText(cs[i])} per turn, '
        '${fmtUs(p.clients[i].airtimePerTxUs)} per turn; '
        'packet ${fmtMbps(p.clients[i].throughputMbps)} Mbps '
        '(${fmtPct(p.clients[i].airtimeShare)} of air), '
        'airtime ${fmtMbps(a.clients[i].throughputMbps)} Mbps '
        '(${fmtPct(a.clients[i].airtimeShare)} of air)',
      );
    }
    b.writeln(
      'Total: packet ${fmtMbps(p.aggregateMbps)} Mbps, '
      'airtime ${fmtMbps(a.aggregateMbps)} Mbps',
    );
    return b.toString().trimRight();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _round.dispose();
    for (final AirtimeClientDraft c in _clients) {
      c.controller.dispose();
    }
    super.dispose();
  }
}
