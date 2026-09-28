// UnitSystem — the app-wide metric / imperial preference for lengths.
//
// Keith, 2026-09-27: one switch, shown in every Wi-Fi Classroom tool that
// shows a length, sets ONE app-wide preference that is remembered between
// launches. Metric is the default and is listed first ("We do try to LEAD with
// it all the time").
//
// Persistence mirrors ThemeController: one shared_preferences string key, and
// a read or write failure never blocks the app (it stays on metric).
//
// Models keep SI internally. Nothing here converts; see length_format.dart.

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which length units the Classroom tools display and accept.
enum UnitSystem {
  metric,
  imperial;

  bool get isMetric => this == UnitSystem.metric;
}

/// A [ChangeNotifier] holding the selected [UnitSystem]. Provided app-wide by
/// [UnitSystemScope], wrapped around `MaterialApp` in main.dart.
class UnitSystemController extends ChangeNotifier {
  UnitSystemController({UnitSystem initial = UnitSystem.metric})
    : _system = initial;

  /// The shared_preferences key for the persisted pick.
  static const String prefsKey = 'app_unit_system';

  UnitSystem _system;

  /// The active system.
  UnitSystem get system => _system;

  /// Loads the persisted pick (if any). Safe before `runApp`; on any error it
  /// keeps the constructed default (metric) and does not throw.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final UnitSystem? parsed = _parse(prefs.getString(prefsKey));
      if (parsed != null && parsed != _system) {
        _system = parsed;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable: stay on metric.
    }
  }

  /// Sets and persists the pick. Listeners fire before the write, so every
  /// open tool follows at once even if storage is slow or fails.
  Future<void> setSystem(UnitSystem system) async {
    if (system == _system) return;
    _system = system;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, system.name);
    } catch (_) {
      // Persist failed: the in-memory pick still applies this session.
    }
  }

  static UnitSystem? _parse(String? raw) {
    for (final UnitSystem s in UnitSystem.values) {
      if (s.name == raw) return s;
    }
    return null;
  }
}

/// Exposes the app's [UnitSystemController] down the tree.
class UnitSystemScope extends InheritedNotifier<UnitSystemController> {
  const UnitSystemScope({
    super.key,
    required UnitSystemController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The nearest controller, or null when none is in scope (a widget test that
  /// pumps a bare screen). Registers a dependency.
  static UnitSystemController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnitSystemScope>()?.notifier;

  /// The active system, metric when no scope is present. Registers a
  /// dependency, so the caller rebuilds when the system flips.
  static UnitSystem systemOf(BuildContext context) =>
      maybeOf(context)?.system ?? UnitSystem.metric;
}

/// Keeps a tool's model in step with the app-wide [UnitSystem].
///
/// Tool models format their own strings (copy text, slider labels, validation
/// messages) and parse typed input, so they hold the active system. A model's
/// ListenableBuilders can live in two routes at once (the tool screen and its
/// presenter view), so the model is told through a controller LISTENER, which
/// runs outside the build phase, and notifies its own listeners from there.
///
/// Use on the State that owns the model and implement [applyUnitSystem].
mixin UnitSystemFollower<T extends StatefulWidget> on State<T> {
  UnitSystemController? _unitsController;

  /// Push [system] into the model. Must be a no-op when unchanged.
  void applyUnitSystem(UnitSystem system);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final UnitSystemController? next = UnitSystemScope.maybeOf(context);
    if (!identical(next, _unitsController)) {
      _unitsController?.removeListener(_onUnits);
      _unitsController = next;
      next?.addListener(_onUnits);
    }
    // First sync. The model's listeners are this State's descendants, so a
    // notify here is legal; later flips arrive through _onUnits.
    applyUnitSystem(next?.system ?? UnitSystem.metric);
  }

  void _onUnits() {
    final UnitSystemController? c = _unitsController;
    if (c != null && mounted) applyUnitSystem(c.system);
  }

  @override
  void dispose() {
    _unitsController?.removeListener(_onUnits);
    super.dispose();
  }
}
