// State for Airtime Anatomy (Wi-Fi Classroom): the two scenarios, which one the
// controls edit, whether B is shown, the selected segment, and (1.11.0) the
// frame-structure view: which view is on the stage, how the MSDUs are packed,
// and which MSDU is corrupted.
//
// A ChangeNotifier so the stage (AirtimeAnatomyStage) and the controls
// (AirtimeAnatomyControls) stay separate widgets that share one model. The
// phone screen stacks them; a presenter layout can place them side by side
// without either widget owning the other's state.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../services/wifi_lab/aggregation_structure.dart';
import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// The two scenario slots.
const List<String> kScenarioLetters = <String>['A', 'B'];

/// A selected segment on the stage: which scenario, which segment.
typedef AirtimeSelection = ({int scenario, TxopSegmentKind kind});

/// Guard intervals the controls offer for [phy]. The sheet itself accepts any
/// of the four for any PHY and its Check does not police them, so the screen
/// limits the choice to what the PHY allows: HT/VHT 0.4 or 0.8, HE 0.8, 1.6
/// or 3.2. Legacy ignores GI.
List<GuardInterval> guardIntervalsFor(AirtimePhy phy) => phy == AirtimePhy.he
    ? const <GuardInterval>[
        GuardInterval.gi08,
        GuardInterval.gi16,
        GuardInterval.gi32,
      ]
    : const <GuardInterval>[GuardInterval.gi04, GuardInterval.gi08];

/// What the stage shows: the TXOP to scale in time, or the PSDU's structure
/// in bytes. Both describe the scenario under edit.
enum AirtimeView {
  time('Time'),
  structure('Structure');

  const AirtimeView(this.label);

  final String label;
}

class AirtimeAnatomyModel extends ChangeNotifier {
  AirtimeAnatomyModel({
    AirtimePreset a = AirtimePreset.legacy6,
    AirtimePreset b = AirtimePreset.he32,
  }) : _scenarios = <AirtimeScenario>[a.scenario, b.scenario],
       _presets = <AirtimePreset?>[a, b] {
    _recompute();
  }

  final List<AirtimeScenario> _scenarios;
  final List<AirtimePreset?> _presets;
  late List<AirtimeResult> _results;
  bool _compare = true;
  int _editing = 0;
  AirtimeSelection? _selection;
  bool _moreOpen = false;

  AirtimeView _view = AirtimeView.time;
  AggregationKind _arrangement = AggregationKind.ampdu;
  int _msdusPerAmsdu = AggregationConstants.defaultMsdusPerAmsdu;

  /// The corrupted MSDU, 0-based, or null when nothing is corrupted.
  int? _corrupted;

  bool get compare => _compare;

  /// Index of the scenario the controls edit (0 = A, 1 = B).
  int get editing => _editing;

  AirtimeSelection? get selection => _selection;
  bool get moreOpen => _moreOpen;

  AirtimeView get view => _view;

  /// The arrangement the user picked. Legacy cannot aggregate, so what is
  /// drawn is [effectiveArrangement].
  AggregationKind get arrangement => _arrangement;

  AggregationKind get effectiveArrangement =>
      aggregationSupported(scenario(_editing).phy, _arrangement)
      ? _arrangement
      : AggregationKind.singleMpdu;

  int get msdusPerAmsdu => _msdusPerAmsdu;

  /// The PSDU of the scenario under edit, in the chosen arrangement. Its
  /// A-MPDU arrangement is the aggregate the time view draws.
  AggregateStructure get structure => structureFor(effectiveArrangement);

  AggregateStructure structureFor(AggregationKind kind) =>
      buildAggregateStructure(
        scenario(_editing),
        kind,
        msdusPerAmsdu: _msdusPerAmsdu,
      );

  /// The pinned per-PHY limits for [structure]. The PPDU duration is
  /// checked whenever the scenario has an airtime (the time view's Check
  /// passes, or refuses only for a duration or size limit).
  List<AggregationLimitCheck> get limits {
    final AirtimeResult r = result(_editing);
    final bool timed = r.check.hasAirtime;
    final AggregateStructure st = structure;
    return checkAggregationLimits(
      st,
      ppduTenths: timed ? ppduTenthsForPsdu(r, st.psduBytes) : null,
    );
  }

  /// The corrupted MSDU, clamped to the current structure, or null.
  int? get corruptedMsdu {
    final int? c = _corrupted;
    if (c == null) return null;
    return c.clamp(0, structure.msduCount - 1);
  }

  CorruptionOutcome? get corruption {
    final int? c = corruptedMsdu;
    return c == null ? null : structure.corrupt(c);
  }

  /// Scenario indices on screen.
  List<int> get visible => _compare ? const <int>[0, 1] : const <int>[0];

  AirtimeScenario scenario(int i) => _scenarios[i];
  AirtimeResult result(int i) => _results[i];

  /// The preset a scenario still matches, or null once it has been edited.
  AirtimePreset? preset(int i) => _presets[i];

  /// "Legacy 6 Mbps", or "Custom" once edited.
  String name(int i) => _presets[i]?.label ?? 'Custom';

  /// Microseconds the full bar width represents: the longest drawable
  /// scenario on screen. Zero when nothing is drawable.
  double get scaleUs {
    double m = 0;
    for (final int i in visible) {
      final AirtimeResult r = _results[i];
      if (r.check.isOk && r.totalUs > m) m = r.totalUs;
    }
    return m;
  }

  void _recompute() {
    _results = <AirtimeResult>[
      for (final AirtimeScenario s in _scenarios) computeAirtime(s),
    ];
  }

  void setCompare(bool on) {
    if (on == _compare) return;
    _compare = on;
    if (!on) {
      _editing = 0;
      if (_selection?.scenario == 1) _selection = null;
    }
    notifyListeners();
  }

  void setEditing(int i) {
    assert(i == 0 || i == 1);
    if (i == _editing) return;
    _editing = i;
    notifyListeners();
  }

  void toggleMore() {
    _moreOpen = !_moreOpen;
    notifyListeners();
  }

  /// Selects a segment; selecting the same one again clears it.
  void select(int scenario, TxopSegmentKind kind) {
    final AirtimeSelection next = (scenario: scenario, kind: kind);
    _selection = _selection == next ? null : next;
    notifyListeners();
  }

  /// Selects a segment without toggling (hover).
  void hover(int scenario, TxopSegmentKind kind) {
    final AirtimeSelection next = (scenario: scenario, kind: kind);
    if (_selection == next) return;
    _selection = next;
    notifyListeners();
  }

  void applyPreset(AirtimePreset p) {
    _scenarios[_editing] = p.scenario;
    _presets[_editing] = p;
    _afterEdit();
  }

  /// Edits the scenario under the controls. PHY changes keep the other
  /// inputs valid: Legacy snaps to 20 MHz, and the guard interval snaps to
  /// 0.8 us when the new PHY does not offer the current one.
  void edit(AirtimeScenario Function(AirtimeScenario s) change) {
    AirtimeScenario next = change(_scenarios[_editing]);
    if (next.phy == AirtimePhy.legacy && next.widthMhz != 20) {
      next = next.copyWith(widthMhz: 20);
    }
    if (next.phy != AirtimePhy.legacy &&
        !guardIntervalsFor(next.phy).contains(next.guardInterval)) {
      next = next.copyWith(guardInterval: GuardInterval.gi08);
    }
    if (next == _scenarios[_editing]) return;
    _scenarios[_editing] = next;
    _presets[_editing] = _matchingPreset(next);
    _afterEdit();
  }

  // ── Frame structure ───────────────────────────────────────────────────────

  void setView(AirtimeView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  void toggleView() => setView(
    _view == AirtimeView.time ? AirtimeView.structure : AirtimeView.time,
  );

  void setArrangement(AggregationKind k) {
    if (k == _arrangement) return;
    _arrangement = k;
    notifyListeners();
  }

  /// Next arrangement the edited scenario's PHY can send, wrapping.
  void nextArrangement() {
    const List<AggregationKind> all = AggregationKind.values;
    final AirtimePhy phy = scenario(_editing).phy;
    int at = all.indexOf(effectiveArrangement);
    for (int i = 0; i < all.length; i++) {
      at = (at + 1) % all.length;
      if (aggregationSupported(phy, all[at])) break;
    }
    setArrangement(all[at]);
  }

  void setMsdusPerAmsdu(int n) {
    assert(n >= 1);
    if (n == _msdusPerAmsdu) return;
    _msdusPerAmsdu = n;
    notifyListeners();
  }

  /// Corrupts MSDU [m] (0-based), or clears the corruption with null.
  void corruptMsdu(int? m) {
    if (m == _corrupted) return;
    _corrupted = m?.clamp(0, structure.msduCount - 1);
    notifyListeners();
  }

  /// On: corrupt the middle MSDU (so a Block Ack bitmap shows good bits on
  /// both sides of the bad one). Off: clear it.
  void setCorrupt(bool on) =>
      corruptMsdu(on ? (corruptedMsdu ?? structure.msduCount ~/ 2) : null);

  void toggleCorrupt() => setCorrupt(_corrupted == null);

  /// Moves the corruption [delta] MSDUs, wrapping; starts it if off.
  void stepCorrupt(int delta) {
    final int n = structure.msduCount;
    final int? c = corruptedMsdu;
    corruptMsdu(c == null ? 0 : (c + delta) % n);
  }

  // ── Presenter keys ─────────────────────────────────────────────────────────

  /// Right arrow: select the next segment of the TXOP, left to right, so an
  /// instructor can walk one transmit opportunity frame by frame. Walks the
  /// scenario that holds the selection, else the one the inputs edit; after
  /// the last segment the selection clears.
  void stepSegment() {
    final int i = _selection?.scenario ?? _editing;
    final AirtimeResult r = _results[i];
    if (!r.check.isOk) return;
    final List<TxopSegmentKind> kinds = <TxopSegmentKind>[
      for (final TxopSegment s in r.segments)
        if (s.tenths > 0) s.kind,
    ];
    if (kinds.isEmpty) return;
    final AirtimeSelection? sel = _selection;
    final int at = sel == null || sel.scenario != i
        ? -1
        : kinds.indexOf(sel.kind);
    _selection = at + 1 < kinds.length
        ? (scenario: i, kind: kinds[at + 1])
        : null;
    notifyListeners();
  }

  /// Up and Down arrows: the edited scenario's rate one step, the MCS for
  /// HT and newer, the data rate for Legacy.
  void nudgeRate(int delta) {
    edit((AirtimeScenario s) {
      if (s.phy == AirtimePhy.legacy) {
        const List<int> rates = AirtimeConstants.legacyRatesMbps;
        final int at = rates.indexOf(s.legacyRateMbps);
        final int next = (at + delta).clamp(0, rates.length - 1);
        return s.copyWith(legacyRateMbps: rates[next]);
      }
      final int last = AirtimeConstants.mcs.last.mcs;
      return s.copyWith(mcs: (s.mcs + delta).clamp(0, last));
    });
  }

  /// Right arrow: in the time view, the next TXOP segment; in the
  /// structure view, move the corruption to the next MSDU.
  void step() => _view == AirtimeView.time ? stepSegment() : stepCorrupt(1);

  PresenterActions get presenterActions => PresenterActions(
    step: step,
    stepLabel:
        'Next segment (time view) or next corrupted MSDU '
        '(structure view)',
    sliderDown: () => nudgeRate(-1),
    sliderUp: () => nudgeRate(1),
    sliderLabel: 'Rate (MCS or legacy rate)',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyV,
        keyLabel: 'V',
        description: 'Time view or structure view',
        onPressed: toggleView,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyA,
        keyLabel: 'A',
        description:
            'Next arrangement: MPDU, A-MSDU, A-MPDU, A-MPDU of '
            'A-MSDUs',
        onPressed: () {
          setView(AirtimeView.structure);
          nextArrangement();
        },
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Corrupt one subframe, or repair it',
        onPressed: () {
          setView(AirtimeView.structure);
          toggleCorrupt();
        },
      ),
    ],
  );

  AirtimePreset? _matchingPreset(AirtimeScenario s) {
    for (final AirtimePreset p in AirtimePreset.values) {
      if (p.scenario == s) return p;
    }
    return null;
  }

  void _afterEdit() {
    _recompute();
    // A selected segment that no longer exists (RTS/CTS turned off, or the
    // scenario became invalid and is not drawn) is dropped.
    final AirtimeSelection? sel = _selection;
    if (sel != null) {
      final AirtimeResult r = _results[sel.scenario];
      if (!r.check.isOk || r.segment(sel.kind).tenths == 0) _selection = null;
    }
    notifyListeners();
  }
}
