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
import '../screens/tools/calculators/cable_loss_screen.dart';
import '../screens/tools/calculators/downtilt_screen.dart';
import '../screens/tools/calculators/earth_curvature_screen.dart';
import '../screens/tools/calculators/eirp_screen.dart';
import '../screens/tools/calculators/fresnel_screen.dart';
import '../screens/tools/calculators/fspl_screen.dart';
import '../screens/tools/calculators/link_budget_screen.dart';
import '../screens/tools/calculators/rain_fade_screen.dart';
import '../screens/tools/calculators/wavelength_screen.dart';
import '../screens/tools/calculators/metric_conversion_screen.dart';
import '../screens/tools/calculators/lat_long_screen.dart';
import '../screens/tools/calculators/dist_bearing_screen.dart';
import '../screens/tools/calculators/midpoint_screen.dart';
import '../screens/tools/calculators/final_point_screen.dart';
import '../screens/tools/network/arp_ndp_screen.dart';
import '../screens/tools/network/bgp_asn_screen.dart';
import '../screens/tools/network/dns_lookup_screen.dart';
import '../screens/tools/network/http_header_screen.dart';
import '../screens/tools/network/interface_info_screen.dart';
import '../screens/tools/network/icmp_ping_screen.dart';
import '../screens/tools/network/ip_geo_screen.dart';
import '../screens/tools/network/mac_oui_screen.dart';
import '../screens/tools/network/mobile_traceroute_screen.dart';
import '../screens/tools/network/packet_sender_screen.dart';
import '../screens/tools/network/ping_screen.dart';
import '../screens/tools/network/ping_sweep_screen.dart';
import '../screens/tools/network/port_reference_screen.dart';
import '../screens/tools/network/port_scan_screen.dart';
import '../screens/tools/network/subnet_calc_screen.dart';
import '../screens/tools/network/ssl_inspect_screen.dart';
import '../screens/tools/network/traceroute_screen.dart';
import '../screens/tools/network/wake_on_lan_screen.dart';
import '../screens/tools/network/whois_screen.dart';

class AppRouter {
  AppRouter._();

  static const String home = '/';
  static const String dbmWatt = '/tools/dbm-watt';

  // RF Calculators category — pure-math tools (no network, all platforms incl.
  // web). Formulas mirror the RF Tools PWA (www/app.js) to the decimal.
  static const String fspl = '/tools/fspl';
  static const String eirp = '/tools/eirp';
  static const String fresnel = '/tools/fresnel';
  static const String cableLoss = '/tools/cable-loss';
  static const String linkBudget = '/tools/link-budget';
  static const String wavelength = '/tools/wavelength';
  static const String downtilt = '/tools/downtilt';
  static const String earthCurvature = '/tools/earth-curvature';
  static const String rainFade = '/tools/rain-fade';

  // GPS Tools category — pure geo-math (no network, all platforms incl. web).
  static const String metricConversion = '/tools/metric-conversion';
  static const String latLong = '/tools/lat-long';
  static const String distBearing = '/tools/dist-bearing';
  static const String midpoint = '/tools/midpoint';
  static const String finalPoint = '/tools/final-point';

  // Networking category — active network tools (native-only; web shows the
  // download-the-app fallback inside each screen, so the routes are always
  // registered and never crash on web).
  static const String interfaceInfo = '/tools/interface-info';
  static const String dnsLookup = '/tools/dns-lookup';
  static const String portScan = '/tools/port-scan';
  static const String ping = '/tools/ping';
  static const String icmpPing = '/tools/icmp-ping';
  static const String pingSweep = '/tools/ping-sweep';
  static const String traceroute = '/tools/traceroute';
  static const String mobileTraceroute = '/tools/mobile-traceroute';
  static const String sslInspect = '/tools/ssl-inspect';
  static const String httpHeaders = '/tools/http-headers';
  static const String whois = '/tools/whois';
  static const String wakeOnLan = '/tools/wake-on-lan';
  static const String arpNdp = '/tools/arp-ndp';
  static const String bgpAsn = '/tools/bgp-asn';
  static const String ipGeo = '/tools/ip-geo';
  static const String macOui = '/tools/mac-oui';
  static const String packetSender = '/tools/packet-sender';
  static const String ipv4Subnet = '/tools/ipv4-subnet';

  // Quick Reference category — offline lookup tables (bundled assets, all
  // platforms incl. web).
  static const String portReference = '/tools/port-reference';

  /// Map of static, argument-less routes. Categories use MaterialPageRoute
  /// directly because each category screen takes a typed `ToolCategory`.
  static final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    dbmWatt: (_) => const DbmWattConverterScreen(),
    fspl: (_) => const FsplScreen(),
    eirp: (_) => const EirpScreen(),
    fresnel: (_) => const FresnelScreen(),
    cableLoss: (_) => const CableLossScreen(),
    linkBudget: (_) => const LinkBudgetScreen(),
    wavelength: (_) => const WavelengthScreen(),
    downtilt: (_) => const DowntiltScreen(),
    earthCurvature: (_) => const EarthCurvatureScreen(),
    rainFade: (_) => const RainFadeScreen(),
    metricConversion: (_) => const MetricConversionScreen(),
    latLong: (_) => const LatLongScreen(),
    distBearing: (_) => const DistBearingScreen(),
    midpoint: (_) => const MidpointScreen(),
    finalPoint: (_) => const FinalPointScreen(),
    interfaceInfo: (_) => const InterfaceInfoScreen(),
    dnsLookup: (_) => const DnsLookupScreen(),
    portScan: (_) => const PortScanScreen(),
    ping: (_) => const PingScreen(),
    icmpPing: (_) => const IcmpPingScreen(),
    pingSweep: (_) => const PingSweepScreen(),
    traceroute: (_) => const TracerouteScreen(),
    mobileTraceroute: (_) => const MobileTracerouteScreen(),
    sslInspect: (_) => const SslInspectScreen(),
    httpHeaders: (_) => const HttpHeaderScreen(),
    whois: (_) => const WhoisScreen(),
    wakeOnLan: (_) => const WakeOnLanScreen(),
    arpNdp: (_) => const ArpNdpScreen(),
    bgpAsn: (_) => const BgpAsnScreen(),
    ipGeo: (_) => const IpGeoScreen(),
    macOui: (_) => const MacOuiScreen(),
    packetSender: (_) => const PacketSenderScreen(),
    ipv4Subnet: (_) => const SubnetCalcScreen(),
    portReference: (_) => const PortReferenceScreen(),
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
