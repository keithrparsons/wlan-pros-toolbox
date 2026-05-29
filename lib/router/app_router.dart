// AppRouter — minimal named-route table. Avoids the go_router dependency
// since the navigation graph is two screens deep (Home → Category → Tool) and
// the built-in Navigator handles that cleanly.
//
// Live tool routes are registered here; category screens push themselves via
// MaterialPageRoute because they need a strongly-typed argument
// (ToolCategory). Tool routes are static and take no arguments.

import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/tools/dbm_watt_converter.dart';

class AppRouter {
  AppRouter._();

  static const String home = '/';
  static const String dbmWatt = '/tools/dbm-watt';

  /// Map of static, argument-less routes. Categories use MaterialPageRoute
  /// directly because each category screen takes a typed `ToolCategory`.
  static final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    dbmWatt: (_) => const DbmWattConverterScreen(),
  };

  /// Fallback for any unregistered route. Sends the user back to home rather
  /// than blowing up — useful while many tools are still "Coming soon".
  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(),
      settings: const RouteSettings(name: home),
    );
  }
}
