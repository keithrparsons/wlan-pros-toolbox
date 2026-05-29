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
import '../screens/tools/network/dns_lookup_screen.dart';
import '../screens/tools/network/http_header_screen.dart';
import '../screens/tools/network/interface_info_screen.dart';
import '../screens/tools/network/ping_screen.dart';
import '../screens/tools/network/port_scan_screen.dart';
import '../screens/tools/network/ssl_inspect_screen.dart';
import '../screens/tools/network/traceroute_screen.dart';
import '../screens/tools/network/wake_on_lan_screen.dart';
import '../screens/tools/network/whois_screen.dart';

class AppRouter {
  AppRouter._();

  static const String home = '/';
  static const String dbmWatt = '/tools/dbm-watt';

  // Networking category — active network tools (native-only; web shows the
  // download-the-app fallback inside each screen, so the routes are always
  // registered and never crash on web).
  static const String interfaceInfo = '/tools/interface-info';
  static const String dnsLookup = '/tools/dns-lookup';
  static const String portScan = '/tools/port-scan';
  static const String ping = '/tools/ping';
  static const String traceroute = '/tools/traceroute';
  static const String sslInspect = '/tools/ssl-inspect';
  static const String httpHeaders = '/tools/http-headers';
  static const String whois = '/tools/whois';
  static const String wakeOnLan = '/tools/wake-on-lan';

  /// Map of static, argument-less routes. Categories use MaterialPageRoute
  /// directly because each category screen takes a typed `ToolCategory`.
  static final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    dbmWatt: (_) => const DbmWattConverterScreen(),
    interfaceInfo: (_) => const InterfaceInfoScreen(),
    dnsLookup: (_) => const DnsLookupScreen(),
    portScan: (_) => const PortScanScreen(),
    ping: (_) => const PingScreen(),
    traceroute: (_) => const TracerouteScreen(),
    sslInspect: (_) => const SslInspectScreen(),
    httpHeaders: (_) => const HttpHeaderScreen(),
    whois: (_) => const WhoisScreen(),
    wakeOnLan: (_) => const WakeOnLanScreen(),
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
