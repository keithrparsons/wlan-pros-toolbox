// State for the PHY Preamble Reference (Wi-Fi Lab): the settings, the mode,
// the selected block, the "which PHY is this?" walk and the L-SIG LENGTH
// calculator's input.
//
// A ChangeNotifier so the stage (PhyPreambleStage) and the controls
// (PhyPreambleControls) stay separate widgets over one shared object. The
// phone screen stacks them; a presenter layout can place them side by side
// without either widget owning the other's state.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kPhyPreambleToolId = 'phy-preamble';

/// Explore the fields, or walk a receiver's decision.
enum PreambleMode {
  explore('Explore'),
  identify('Which PHY?');

  const PreambleMode(this.label);

  final String label;
}

/// Why the TXTIME field cannot be used.
enum TxtimeInputError {
  empty('Enter the PPDU duration in µs.'),
  notANumber('Numbers only, in µs, for example 200 or 104.4.');

  const TxtimeInputError(this.message);

  final String message;
}

class PhyPreambleModel extends ChangeNotifier {
  PhyPreambleModel({
    PreambleSettings initial = const PreambleSettings(),
    this._mode = PreambleMode.explore,
    String? selectedBlock,
    this._txtimeText = '200',
    math.Random? random,
  }) : _settings = initial,
       _random = random ?? math.Random() {
    _recompute();
    if (selectedBlock != null) {
      final int i = _blocks.indexWhere(
        (PreambleBlock b) => b.name == selectedBlock,
      );
      if (i >= 0) _selected = i;
    }
  }

  final math.Random _random;

  PreambleSettings _settings;
  PreambleMode _mode;
  late List<PreambleBlock> _blocks;
  late int _preambleTenths;
  late Classification _classification;
  int? _selected;

  bool _mystery = false;
  int _stepsShown = 0;

  String _txtimeText;
  bool _signalExtension = false;

  // ── Read ──────────────────────────────────────────────────────────────────

  PreambleSettings get settings => _settings;
  PpduType get type => _settings.type;
  PreambleMode get mode => _mode;
  List<PreambleBlock> get blocks => _blocks;

  /// Everything before Data, tenths of a us.
  int get preambleTenths => _preambleTenths;

  /// What this PHY adds after the 20 us legacy preamble, tenths of a us.
  int get addedTenths => _preambleTenths - kLegacyPreambleTenths;

  /// Index into [blocks], or null.
  int? get selected => _selected;
  PreambleBlock? get selectedBlock =>
      _selected == null ? null : _blocks[_selected!];

  ({int count, Evidence evidence}) get ltf => ltfCountFor(_settings);

  // Which PHY is this?
  Classification get classification => _classification;

  /// Steps of the walk revealed so far.
  int get stepsShown => _stepsShown;
  bool get walkDone => _stepsShown >= _classification.steps.length;

  /// A mystery PPDU is on the stage and its name stays hidden until the walk
  /// ends.
  bool get hidden => _mode == PreambleMode.identify && _mystery && !walkDone;

  // L-SIG LENGTH.
  String get txtimeText => _txtimeText;
  bool get signalExtension => _signalExtension;

  TxtimeInputError? get txtimeError {
    final String t = _txtimeText.trim();
    if (t.isEmpty) return TxtimeInputError.empty;
    final double? v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite || v < 0) {
      return TxtimeInputError.notANumber;
    }
    return null;
  }

  /// The calculation, or null while the input is unusable.
  LsigLengthResult? get lsigLength {
    if (txtimeError != null) return null;
    final int tenths = (double.parse(_txtimeText.trim()) * 10).round();
    return spoofLsigLength(
      txtimeTenths: tenths,
      type: type,
      preambleTenthsOfType: _preambleTenths,
      signalExtensionUs: _signalExtension ? kSignalExtensionUs : 0,
    );
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  void _recompute() {
    _blocks = preambleBlocks(_settings);
    _preambleTenths = _blocks
        .where((PreambleBlock b) => b.isToScale)
        .fold<int>(0, (int a, PreambleBlock b) => a + b.tenths);
    _classification = classify(observe(_settings.type));
  }

  void _setSettings(PreambleSettings next) {
    if (next == _settings) return;
    final String? keep = selectedBlock?.name;
    final bool typeChanged = next.type != _settings.type;
    _settings = next;
    _recompute();
    _selected = null;
    if (keep != null) {
      final int i = _blocks.indexWhere((PreambleBlock b) => b.name == keep);
      if (i >= 0) _selected = i;
    }
    if (typeChanged) _stepsShown = 0;
    notifyListeners();
  }

  set type(PpduType t) {
    // Picking a PPDU by name ends any mystery.
    _mystery = false;
    _setSettings(_settings.copyWith(type: t));
  }

  set streams(int n) => _setSettings(_settings.copyWith(streams: n));
  set ltfMode(HeLtfMode m) => _setSettings(_settings.copyWith(ltf: m));
  set widthMhz(int w) => _setSettings(_settings.copyWith(widthMhz: w));
  set sigSymbols(int n) => _setSettings(_settings.copyWith(sigSymbols: n));

  set mode(PreambleMode m) {
    if (m == _mode) return;
    _mode = m;
    _mystery = false;
    _stepsShown = 0;
    if (m == PreambleMode.identify) _selected = null;
    notifyListeners();
  }

  /// Tapping a block opens its table; tapping it again closes it. Hidden
  /// blocks cannot be opened.
  void select(int index) {
    if (index < 0 || index >= _blocks.length) return;
    if (hidden && _blocks[index].role != BlockRole.legacy) return;
    _selected = _selected == index ? null : index;
    notifyListeners();
  }

  void clearSelection() {
    if (_selected == null) return;
    _selected = null;
    notifyListeners();
  }

  /// A random PPDU type other than the current one, with its name hidden.
  void newMystery() {
    final List<PpduType> others = PpduType.values
        .where((PpduType t) => t != _settings.type)
        .toList();
    final PpduType t = others[_random.nextInt(others.length)];
    _mode = PreambleMode.identify;
    _setSettings(_settings.copyWith(type: t));
    _mystery = true;
    _stepsShown = 0;
    _selected = null;
    notifyListeners();
  }

  void stepWalk() {
    if (walkDone) return;
    _stepsShown++;
    notifyListeners();
  }

  void backWalk() {
    if (_stepsShown == 0) return;
    _stepsShown--;
    notifyListeners();
  }

  void resetWalk() {
    if (_stepsShown == 0) return;
    _stepsShown = 0;
    notifyListeners();
  }

  void revealWalk() {
    if (walkDone) return;
    _stepsShown = _classification.steps.length;
    notifyListeners();
  }

  // ── Presenter keys ──────────────────────────────────────────────────────

  /// Opens the next block after the open one (the first when none is open),
  /// wrapping, and skipping blocks hidden in a mystery PPDU.
  void selectNext() {
    final int n = _blocks.length;
    if (n == 0) return;
    final int from = _selected ?? -1;
    for (int k = 1; k <= n; k++) {
      final int i = (from + k) % n;
      if (hidden && _blocks[i].role != BlockRole.legacy) continue;
      if (i == _selected) return;
      _selected = i;
      notifyListeners();
      return;
    }
  }

  /// The next or previous PPDU type, held at the ends of the list.
  void nudgeType(int delta) {
    final List<PpduType> all = PpduType.values;
    final int i = (all.indexOf(type) + delta).clamp(0, all.length - 1);
    if (all[i] != type) type = all[i];
  }

  /// Presenter keys. Right: in Explore, open the next block; in Which PHY?,
  /// ask the next question. R: close the block, or restart the walk. Up and
  /// Down: the PPDU type. Nothing runs on a clock, so there is no play.
  PresenterActions get presenterActions => PresenterActions(
    step: () => _mode == PreambleMode.identify ? stepWalk() : selectNext(),
    reset: () =>
        _mode == PreambleMode.identify ? resetWalk() : clearSelection(),
    sliderDown: () => nudgeType(-1),
    sliderUp: () => nudgeType(1),
    sliderLabel: 'PPDU type',
  );

  set txtimeText(String s) {
    if (s == _txtimeText) return;
    _txtimeText = s;
    notifyListeners();
  }

  set signalExtension(bool on) {
    if (on == _signalExtension) return;
    _signalExtension = on;
    notifyListeners();
  }

  /// Sets TXTIME to this preamble plus [dataUs] of data.
  void useExampleTxtime(int dataUs) {
    final int tenths =
        _preambleTenths +
        dataUs * 10 +
        (_signalExtension ? kSignalExtensionUs * 10 : 0);
    txtimeText = formatPreambleTenths(tenths);
  }

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('PHY Preamble Reference (WLAN Pros Toolbox)')
      ..writeln(type.label);
    if (type != PpduType.nonHt) {
      b.writeln(
        '${_settings.effectiveStreams} stream'
        '${_settings.effectiveStreams == 1 ? '' : 's'}, '
        '${ltf.count} LTF${ltf.count == 1 ? '' : 's'}'
        '${type.hasHeLtf ? ', ${_settings.ltf.label}' : ''}',
      );
    }
    for (final PreambleBlock blk in _blocks) {
      if (!blk.isToScale) continue;
      final String mods = blk.modulations.isEmpty
          ? ''
          : ' (${blk.modulations.map((SymbolModulation m) => m.label).join(', ')})';
      b.writeln('  ${blk.name}: ${formatPreambleTenths(blk.tenths)} µs$mods');
    }
    b.writeln(
      'Preamble: ${formatPreambleTenths(_preambleTenths)} µs '
      '(legacy 20 + ${formatPreambleTenths(addedTenths)} added)',
    );
    final ({String symbol, int start, int end})? bss = bssColorPosition(type);
    if (bss != null) {
      b.writeln('BSS color: ${bss.symbol} B${bss.start}-B${bss.end}');
    }
    final LsigLengthResult? r = lsigLength;
    if (r != null && r.ok) {
      b.writeln(
        'L-SIG LENGTH for a ${_txtimeText.trim()} µs PPDU: ${r.length} '
        '(mod 3 = ${r.lengthMod3}); a legacy radio defers '
        '${formatPreambleTenths(r.legacyDeferTenths)} µs',
      );
    }
    return b.toString().trimRight();
  }
}
