// My Tools tip — the one-time hint that tools can be pressed and held.
//
// Keith, 2026-10-04 (SPEC 6, after Vera's gate F2): after a user has opened 3
// tools and My Tools is still empty, show one short message once: "Press and
// hold any tool to add it to My Tools." Never again on that device. The home
// screen is unchanged.
//
// Wording by platform (Keith, 2026-10-04, SPEC 7): phones and tablets (iOS,
// Android) get the press-and-hold line; Mac, Windows, Linux and the web get
// "Right-click any tool to add it to My Tools." The trigger stays any 3 opens,
// re-opening the same tool counts (SPEC 8).
//
// Tool opens are counted by [MyToolsTipObserver] on the app Navigator: a push
// of any catalog tool route counts, whichever surface opened it. The count and
// the shown flag live in shared_preferences on this device only, like the My
// Tools list itself. A read or write failure never blocks the app.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tool_catalog.dart';
import 'my_tools_controller.dart';

/// Counts tool opens and decides when the one-time tip shows.
class MyToolsTipController {
  /// [myTools] is read at each open: the tip never shows while it holds a
  /// tool. [isToolRoute] decides which route names are tools; it defaults to
  /// the catalog's route names.
  MyToolsTipController({
    required this.myTools,
    bool Function(String? routeName)? isToolRoute,
  }) : isToolRoute = isToolRoute ?? _catalogHasRoute;

  /// Opens before the tip can show (Keith, 2026-10-04: "opened 3 tools").
  static const int opensBeforeTip = 3;

  /// The tip on phones and tablets (iOS, Android), exactly as Keith ruled it.
  static const String touchMessage =
      'Press and hold any tool to add it to My Tools.';

  /// The tip on Mac, Windows, Linux and the web, exactly as Keith ruled it.
  static const String desktopMessage =
      'Right-click any tool to add it to My Tools.';

  /// The tip text for [platform]. On the web it is always [desktopMessage].
  /// Reads `defaultTargetPlatform` and `kIsWeb` (web-safe, no `dart:io`), the
  /// same platform test the rest of the app uses.
  static String messageFor(TargetPlatform platform, {bool web = kIsWeb}) {
    if (web) return desktopMessage;
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.android => touchMessage,
      _ => desktopMessage,
    };
  }

  /// The tip text for the platform the app is running on.
  static String get message => messageFor(defaultTargetPlatform);

  /// shared_preferences key for the tool-open count.
  static const String opensKey = 'my_tools_tip_opens';

  /// shared_preferences key set once the tip has shown.
  static const String shownKey = 'my_tools_tip_shown';

  final MyToolsController myTools;
  final bool Function(String? routeName) isToolRoute;

  int _opens = 0;
  bool _shown = false;

  int get opens => _opens;
  bool get shown => _shown;

  /// Watches the app Navigator for tool opens. Add it to
  /// `MaterialApp.navigatorObservers`.
  late final MyToolsTipObserver observer = MyToolsTipObserver(this);

  /// Loads the persisted count and flag. Safe before `runApp`; never throws.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _opens = prefs.getInt(opensKey) ?? 0;
      _shown = prefs.getBool(shownKey) ?? false;
    } catch (_) {
      // Storage unavailable: start from zero for this session.
    }
  }

  /// Records one tool open. Returns true when the tip should show now, and
  /// marks it shown, so it is true at most once per device.
  Future<bool> recordToolOpen() async {
    if (_shown) return false;
    // The count stops at the threshold; it only gates the tip.
    if (_opens < opensBeforeTip) _opens++;
    final bool showNow = _opens >= opensBeforeTip && myTools.isEmpty;
    if (showNow) _shown = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(opensKey, _opens);
      if (showNow) await prefs.setBool(shownKey, true);
    } catch (_) {
      // Persist failed: the in-memory state still applies this session.
    }
    return showNow;
  }

  static Set<String>? _toolRoutes;

  static bool _catalogHasRoute(String? name) {
    if (name == null) return false;
    _toolRoutes ??= <String>{
      for (final ToolCategory c in kToolCategories)
        for (final ToolEntry t in c.tools) t.routeName,
    };
    return _toolRoutes!.contains(name);
  }
}

/// Counts each push of a tool route and shows the tip in the app's
/// [ScaffoldMessenger] when [MyToolsTipController.recordToolOpen] says so.
class MyToolsTipObserver extends NavigatorObserver {
  MyToolsTipObserver(this.controller);

  final MyToolsTipController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!controller.isToolRoute(route.settings.name)) return;
    _record();
  }

  Future<void> _record() async {
    if (!await controller.recordToolOpen()) return;
    final NavigatorState? nav = navigator;
    if (nav == null || !nav.mounted) return;
    // After the frame, so the tool screen's Scaffold has registered and the
    // tip shows on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!nav.mounted) return;
      ScaffoldMessenger.maybeOf(
        nav.context,
      )?.showSnackBar(SnackBar(content: Text(MyToolsTipController.message)));
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}
