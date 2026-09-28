// State for the Wi-Fi Classroom tool Decibels in Your Head, the Rules of 3
// and 10 (db-rules).
//
// One ChangeNotifier shared by the stage and the controls, so the two lay out
// independently: stacked on a phone, side by side on a wide window, and in the
// presenter layout, which uses this same object (state is shared, not
// copied). All math is in lib/services/wifi_lab/db_rules_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/db_rules_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/db_rules_model.dart';

class DbRulesController extends ChangeNotifier {
  int _dbm = DbRules.defaultDbm;
  bool _revealed = false;

  /// The signal level, dBm, a whole number from -80 to -60.
  int get dbm => _dbm;

  /// Whether the predict-then-reveal answer is showing.
  bool get revealed => _revealed;

  void setDbm(num v) {
    final int d = v.round().clamp(DbRules.minDbm, DbRules.maxDbm);
    if (d == _dbm) return;
    _dbm = d;
    notifyListeners();
  }

  void nudge(int db) => setDbm(_dbm + db);

  void setRevealed(bool v) {
    if (v == _revealed) return;
    _revealed = v;
    notifyListeners();
  }

  void toggleReveal() => setRevealed(!_revealed);

  /// The prediction's comparison: -67 dBm against the -70 dBm reference.
  void showPrediction() => setDbm(DbRules.predictDbm);

  void reset() {
    _dbm = DbRules.defaultDbm;
    _revealed = false;
    notifyListeners();
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  /// Difference from the reference, dB.
  int get diffDb => _dbm - DbRules.referenceDbm;

  double get ratio => DbRules.ratio(diffDb);
  DbRulePath get path => DbRules.path(diffDb);
  double get pw => DbRules.dbmToPw(_dbm);
  double get referencePw => DbRules.dbmToPw(DbRules.referenceDbm);

  /// The rules path in words: "+10 -3 -3 -3 dB: x10 /2 /2 /2 = 1.25x".
  String get pathWords {
    final DbRulePath p = path;
    if (p.steps.isEmpty) return 'No steps: the same level as the reference.';
    return '${p.steps.map((DbStep s) => s.label).join(' ')} dB: '
        '${p.steps.map((DbStep s) => s.effect).join(' ')} = '
        '${DbFormat.rule(p.ruleRatio)}';
  }

  // ── Presenter keyboard ──────────────────────────────────────────────────

  /// Up and Down move 1 dB; Right adds 3 dB and Left takes 3 away; Page Up
  /// and Page Down move 10 dB (what a presentation clicker sends); P reveals
  /// the answer; R resets. Nothing plays, so Space shows the prediction's
  /// comparison.
  PresenterActions get presenterActions => PresenterActions(
    playPause: showPrediction,
    playPauseLabel: 'Show -67 dBm against -70 dBm',
    step: () => nudge(3),
    stepLabel: 'Add 3 dB',
    reset: reset,
    sliderDown: () => nudge(-1),
    sliderUp: () => nudge(1),
    sliderLabel: 'Signal level',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Take away 3 dB',
        onPressed: () => nudge(-3),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.pageUp,
        keyLabel: 'Page Up',
        description: 'Add 10 dB',
        onPressed: () => nudge(10),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.pageDown,
        keyLabel: 'Page Down',
        description: 'Take away 10 dB',
        onPressed: () => nudge(-10),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Show or hide the prediction answer',
        onPressed: toggleReveal,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() => <String>[
    'Decibels in Your Head: the Rules of 3 and 10',
    'Signal ${DbFormat.dbm(_dbm)} = ${DbFormat.pw(pw)} '
        '(${DbRules.dbmToMw(_dbm).toStringAsExponential(3)} mW)',
    'Reference ${DbFormat.dbm(DbRules.referenceDbm)} = '
        '${DbFormat.pw(referencePw)}',
    'Difference ${DbFormat.dbDiff(diffDb)}: ${DbRules.powerWords(diffDb)}',
    'Rules of 3 and 10: $pathWords (exact ${DbFormat.ratio(ratio)})',
  ].join('\n');
}
