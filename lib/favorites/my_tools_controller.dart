// MyToolsController — the user's personal top-ten ("My Tools") shown on the
// home screen under the Check My Connection card.
//
// Spec: Deliverables/2026-10-03-toolbox-my-tools/SPEC.md in myPKA (Keith,
// 2026-10-03). Three rulings drive this file:
//   * the list holds at most [MyToolsController.maxTools] (10) tool ids, in the
//     user's order, reorderable;
//   * it lives on THIS DEVICE ONLY, in shared_preferences, keyed by the stable
//     catalog `ToolEntry.id`. No account, nothing synced, nothing sent. The
//     store listing says "No data collected" and this file must keep that
//     true: there is no network import here and there must never be one;
//   * an id the catalog no longer carries is dropped silently on load.
//
// Since 2026-10-09 an id can also name an Educational Resources entry
// (`resource:<id>`, or the Field Manual); see my_tools_item.dart. They count
// toward the same ten and reorder, replace and clear exactly like tools.
//
// Persistence mirrors ThemeController and UnitSystemController: one
// shared_preferences key, listeners fire BEFORE the write so the UI follows at
// once, and a read or write failure never blocks the app (the in-memory list
// still applies for the session).

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tool_catalog.dart';
import 'my_tools_item.dart';

/// The outcome of [MyToolsController.add], so the caller can decide what to
/// show (a confirmation, or the list-is-full dialog).
enum MyToolsAddResult {
  /// The id was appended to the end of the list.
  added,

  /// The id was already in the list. Nothing changed.
  alreadyPresent,

  /// The list already holds [MyToolsController.maxTools]. Nothing changed;
  /// the caller offers a replacement via [MyToolsController.replace].
  full,

  /// The id is not a tool this build carries. Nothing changed.
  unknown,
}

/// Holds the ordered My Tools ids. Provided app-wide by [MyToolsScope].
class MyToolsController extends ChangeNotifier {
  /// [isKnownId] decides which ids are real tools or resources. It defaults
  /// to the live catalog ([kToolCategories]) plus the Educational Resources
  /// entries ([myToolsIdIsKnown]); tests inject their own.
  MyToolsController({
    List<String> initial = const <String>[],
    bool Function(String id)? isKnownId,
  }) : _isKnownId = isKnownId ?? myToolsIdIsKnown {
    _ids.addAll(_sanitize(initial));
  }

  /// The most tools My Tools holds (Keith, 2026-10-03: "Limit: ten").
  static const int maxTools = 10;

  /// The shared_preferences key for the persisted, ordered id list.
  static const String prefsKey = 'my_tools_ids';

  final bool Function(String id) _isKnownId;
  final List<String> _ids = <String>[];

  /// The ordered ids, first is shown first. Unmodifiable view.
  List<String> get ids => List<String>.unmodifiable(_ids);

  /// The ordered catalog tools only, resolved against the catalog. Ids that
  /// do not resolve, and resource ids, are skipped. The home section and the
  /// dialogs use [items].
  List<ToolEntry> get tools => <ToolEntry>[
    for (final String id in _ids)
      if (toolEntryById(id) case final ToolEntry t) t,
  ];

  /// The ordered entries, tools and resources, as the home section shows
  /// them. Ids that do not resolve (a resource before its list has loaded, or
  /// an injected [isKnownId]) are skipped.
  List<MyToolsItem> get items => <MyToolsItem>[
    for (final String id in _ids)
      if (myToolsItemById(id) case final MyToolsItem item) item,
  ];

  int get length => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;
  bool get isFull => _ids.length >= maxTools;

  bool contains(String id) => _ids.contains(id);

  /// Loads the persisted list. Unknown ids and duplicates are dropped and the
  /// cap is enforced; if anything was dropped the cleaned list is written back
  /// so the stale ids do not linger in storage. Safe before `runApp`; never
  /// throws.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? stored = prefs.getStringList(prefsKey);
      if (stored == null) return;
      final List<String> clean = _sanitize(stored);
      final bool changed = !_sameList(clean, _ids);
      _ids
        ..clear()
        ..addAll(clean);
      if (changed) notifyListeners();
      if (!_sameList(clean, stored)) {
        await prefs.setStringList(prefsKey, clean);
      }
    } catch (_) {
      // Storage unavailable: keep the in-memory list. No crash.
    }
  }

  /// Appends [id]. See [MyToolsAddResult] for the no-change outcomes.
  Future<MyToolsAddResult> add(String id) async {
    if (!_isKnownId(id)) return MyToolsAddResult.unknown;
    if (_ids.contains(id)) return MyToolsAddResult.alreadyPresent;
    if (isFull) return MyToolsAddResult.full;
    _ids.add(id);
    await _commit();
    return MyToolsAddResult.added;
  }

  /// Removes [id]. Returns false when it was not in the list.
  Future<bool> remove(String id) async {
    if (!_ids.remove(id)) return false;
    await _commit();
    return true;
  }

  /// Puts [newId] in [oldId]'s place, keeping the position. Used by the
  /// list-is-full dialog. Returns false (and changes nothing) when [oldId] is
  /// not in the list, [newId] is unknown, or [newId] is already in the list.
  Future<bool> replace(String oldId, String newId) async {
    final int at = _ids.indexOf(oldId);
    if (at < 0 || !_isKnownId(newId) || _ids.contains(newId)) return false;
    _ids[at] = newId;
    await _commit();
    return true;
  }

  /// Moves the item at [oldIndex] so it ends up at [newIndex] in the
  /// resulting list. This is the index convention of
  /// `ReorderableListView.onReorderItem` (the target is already adjusted for
  /// the removed item). Out-of-range indexes are clamped; a no-op move does not
  /// notify or write.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _ids.length) return;
    final int target = newIndex.clamp(0, _ids.length - 1);
    if (target == oldIndex) return;
    final String id = _ids.removeAt(oldIndex);
    _ids.insert(target, id);
    await _commit();
  }

  /// Moves [id] one place toward the top. The non-drag reorder path.
  Future<bool> moveUp(String id) async {
    final int at = _ids.indexOf(id);
    if (at <= 0) return false;
    await reorder(at, at - 1);
    return true;
  }

  /// Moves [id] one place toward the bottom. The non-drag reorder path.
  Future<bool> moveDown(String id) async {
    final int at = _ids.indexOf(id);
    if (at < 0 || at >= _ids.length - 1) return false;
    await reorder(at, at + 1);
    return true;
  }

  /// Empties the list (Keith, 2026-10-03: "an easy way to clear the list and
  /// start over"). The home section disappears once this lands.
  Future<void> clear() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    await _commit();
  }

  Future<void> _commit() async {
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, List<String>.of(_ids));
    } catch (_) {
      // Persist failed: the in-memory list still applies this session.
    }
  }

  List<String> _sanitize(Iterable<String> raw) {
    final List<String> out = <String>[];
    for (final String id in raw) {
      if (out.length >= maxTools) break;
      if (_isKnownId(id) && !out.contains(id)) out.add(id);
    }
    return out;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The catalog entry for [id] on this platform, or null. A tool the native
/// scan gate drops on this platform resolves to null here, so a favorite of it
/// is pruned like any other unknown id.
ToolEntry? toolEntryById(String id) {
  for (final ToolCategory c in kToolCategories) {
    for (final ToolEntry t in c.tools) {
      if (t.id == id) return t;
    }
  }
  return null;
}

/// Exposes the app's [MyToolsController] down the tree. Wrapped around
/// `MaterialApp` in main.dart.
class MyToolsScope extends InheritedNotifier<MyToolsController> {
  const MyToolsScope({
    super.key,
    required MyToolsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The nearest controller, or null when none is in scope (a widget test that
  /// pumps a bare screen). Registers a dependency, so the caller rebuilds when
  /// the list changes.
  static MyToolsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MyToolsScope>()?.notifier;

  /// As [maybeOf], without registering a dependency. For event handlers.
  static MyToolsController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MyToolsScope>()?.notifier;
}
