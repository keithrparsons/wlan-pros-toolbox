// State for Airtime Anatomy (Wi-Fi Classroom): the two scenarios, which one the
// controls edit, whether B is shown, and the selected segment.
//
// A ChangeNotifier so the stage (AirtimeAnatomyStage) and the controls
// (AirtimeAnatomyControls) stay separate widgets that share one model. The
// phone screen stacks them; a presenter layout can place them side by side
// without either widget owning the other's state.

import 'package:flutter/foundation.dart';

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

  bool get compare => _compare;

  /// Index of the scenario the controls edit (0 = A, 1 = B).
  int get editing => _editing;

  AirtimeSelection? get selection => _selection;
  bool get moreOpen => _moreOpen;

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

  PresenterActions get presenterActions => PresenterActions(
    step: stepSegment,
    sliderDown: () => nudgeRate(-1),
    sliderUp: () => nudgeRate(1),
    sliderLabel: 'Rate (MCS or legacy rate)',
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
