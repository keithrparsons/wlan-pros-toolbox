// AppRouter — minimal named-route table. Avoids the go_router dependency
// since the navigation graph is two screens deep (Home → Category → Tool) and
// the built-in Navigator handles that cleanly.
//
// Live tool routes are registered here; category screens push themselves via
// MaterialPageRoute because they need a strongly-typed argument
// (ToolCategory). Tool routes are static and take no arguments.

import 'package:flutter/material.dart';

import '../screens/about_screen.dart';
import '../screens/help_browse_screen.dart';
import '../screens/home_screen.dart';
import '../screens/tools/educational/educational_resources_screen.dart';
import '../screens/search_screen.dart';
import '../data/tool_catalog.dart' show kEducationalResourcesRoute;
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
import '../screens/tools/calculators/unit_converter_screen.dart';
import '../screens/tools/calculators/qr_generator_screen.dart';
import '../screens/tools/calculators/dtmf_generator_screen.dart';
import '../screens/tools/calculators/lat_long_screen.dart';
import '../screens/tools/calculators/dist_bearing_screen.dart';
import '../screens/tools/calculators/midpoint_screen.dart';
import '../screens/tools/calculators/final_point_screen.dart';
import '../screens/tools/calculators/downtilt_coverage_screen.dart';
import '../screens/tools/calculators/capacity_planner_screen.dart';
import '../screens/tools/calculators/ptp_link_screen.dart';
import '../screens/tools/calculators/ipv6_subnet_screen.dart';
import '../screens/tools/calculators/throughput_calc_screen.dart';
import '../screens/tools/calculators/rf_attenuation_screen.dart';
import '../screens/tools/calculators/noise_floor_screen.dart';
import '../screens/tools/calculators/poe_budget_screen.dart';
import '../screens/tools/reference/wifi_channels_screen.dart';
import '../screens/tools/reference/standards_screen.dart';
import '../screens/tools/reference/mcs_index_screen.dart';
import '../screens/tools/reference/signal_thresholds_screen.dart';
import '../screens/tools/reference/wpa_security_screen.dart';
import '../screens/tools/reference/http_status_codes_screen.dart';
import '../screens/tools/reference/optical_transceivers_screen.dart';
import '../screens/tools/reference/reason_codes_screen.dart';
import '../screens/tools/reference/frame_exchange_screen.dart';
import '../screens/tools/reference/db_reference_screen.dart';
import '../screens/tools/reference/channel_map_screen.dart';
import '../screens/tools/reference/ethernet_pinout_screen.dart';
import '../screens/tools/reference/coax_cable_screen.dart';
import '../screens/tools/reference/ethernet_cable_screen.dart';
import '../screens/tools/reference/antenna_connectors_screen.dart';
import '../screens/tools/reference/antenna_fundamentals_screen.dart';
import '../screens/tools/reference/fiber_optic_screen.dart';
import '../screens/tools/reference/rf_connectors_screen.dart';
import '../screens/tools/reference/roaming_screen.dart';
import '../screens/tools/reference/ap_placement_screen.dart';
import '../screens/tools/reference/non_wifi_channels_screen.dart';
import '../screens/tools/reference/wifi_glossary_screen.dart';
import '../screens/tools/reference/plmn_reference_screen.dart';
import '../screens/tools/reference/poe_reference_screen.dart';
import '../screens/tools/reference/spectrum_screen.dart';
import '../screens/tools/network/arp_ndp_screen.dart';
import '../screens/tools/network/bgp_asn_screen.dart';
import '../screens/tools/network/dns_lookup_screen.dart';
import '../screens/tools/network/http_header_screen.dart';
import '../screens/tools/network/device_info_screen.dart';
import '../screens/tools/network/interface_info_screen.dart';
import '../screens/tools/network/icmp_ping_screen.dart';
import '../screens/tools/network/ip_geo_screen.dart';
import '../screens/tools/network/mac_oui_screen.dart';
import '../screens/tools/network/network_discovery_screen.dart';
import '../screens/tools/network/mobile_traceroute_screen.dart';
import '../screens/tools/network/net_quality_screen.dart';
import '../screens/tools/network/test_my_connection_screen.dart';
import '../screens/tools/network/packet_sender_screen.dart';
import '../screens/tools/network/ping_screen.dart';
import '../screens/tools/network/ping_plotter_screen.dart';
import '../screens/tools/network/ping_sweep_screen.dart';
import '../screens/tools/network/port_reference_screen.dart';
import '../screens/tools/network/port_scan_screen.dart';
import '../screens/tools/network/subnet_calc_screen.dart';
import '../screens/tools/network/ssl_inspect_screen.dart';
import '../screens/tools/network/traceroute_screen.dart';
import '../screens/tools/network/wake_on_lan_screen.dart';
import '../screens/tools/network/whois_screen.dart';
import '../screens/tools/network/wifi_info_screen.dart';
import '../screens/tools/network/cellular_info_screen.dart';
import '../screens/tools/calculators/hex_ascii_screen.dart';
import '../screens/tools/command/cli_commands_screen.dart';
import '../screens/tools/command/linux_wlan_commands_screen.dart';
import '../screens/tools/command/wireshark_filters_screen.dart';
import '../screens/tools/reference/osi_model_screen.dart';
import '../screens/tools/reference/top_level_domains_screen.dart';
import '../screens/tools/reference/rj_connectors_screen.dart';
import '../screens/tools/reference/ascii_reference_screen.dart';
import '../screens/tools/reference/emoji_reference_screen.dart';
import '../screens/tools/reference/pdf_reference_screen.dart';
import '../screens/tools/checklists/checklist_screen.dart';
import '../data/checklists.dart';

class AppRouter {
  AppRouter._();

  /// App-wide navigator key. Lets the one-tap-trigger deep-link router
  /// (TICKET-03) navigate to a tool route from outside the widget tree — the
  /// cold-launch case has no listening screen to route on its own. Reuses the
  /// existing named-route Navigator; introduces no second nav system.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const String home = '/';

  /// App-level "About" surface (SOP-020 copy). Not a tool route — reached from
  /// the HomeScreen AppBar info action, never the tool catalog.
  static const String about = '/about';

  /// App-level "Help & Documentation" browse surface — lists every tool with a
  /// help entry, grouped by catalog category, each opening its help sheet.
  /// Reached from the About screen's "Help and Documentation" section. Not a
  /// tool route.
  static const String helpBrowse = '/help';

  /// Educational Resources directory (the data-driven Wi-Fi learning-resources
  /// list). Reached from the home grid (HomeScreen intercepts the tile to push
  /// the dedicated screen) and registered here so a named-route navigation also
  /// resolves. The constant lives in the catalog (kEducationalResourcesRoute)
  /// so the tile and route share one source of truth.
  static const String educationalResources = kEducationalResourcesRoute;

  /// Global cross-category tool search (IA redesign, mockup 04). Reached from the
  /// home search field; pushes the grouped results screen.
  static const String search = '/search';

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
  static const String downtiltCoverage = '/tools/downtilt-coverage';

  // Planning Tools and Infrastructure calculators (pure math, all platforms).
  static const String capacityPlanner = '/tools/capacity-planner';
  static const String ptpLink = '/tools/ptp-link';
  static const String ipv6Subnet = '/tools/ipv6-subnet';
  static const String throughputCalc = '/tools/throughput-calc';
  static const String rfAttenuation = '/tools/rf-attenuation';
  static const String noiseFloor = '/tools/noise-floor';
  static const String poeBudget = '/tools/poe-budget';

  // Reference tables (read-only lookup data, all platforms incl. web).
  static const String wifiChannels = '/tools/wifi-channels';
  static const String standards = '/tools/standards';
  static const String mcsIndex = '/tools/mcs-index';
  static const String signalThresholds = '/tools/signal-thresholds';
  static const String wpaSecurity = '/tools/wpa-security';
  static const String reasonCodes = '/tools/reason-codes';
  static const String httpStatusCodes = '/tools/http-status-codes';
  static const String frameExchange = '/tools/frame-exchange';
  static const String dbReference = '/tools/db-reference';
  static const String channelMap = '/tools/channel-map';
  static const String ethernetPinout = '/tools/ethernet-pinout';
  static const String coaxCable = '/tools/coax-cable';
  static const String ethernetCable = '/tools/ethernet-cable';
  static const String fiberOptic = '/tools/fiber-optic';
  static const String rfConnectors = '/tools/rf-connectors';
  static const String roaming = '/tools/roaming';
  static const String apPlacement = '/tools/ap-placement';
  static const String poeReference = '/tools/poe-reference';
  static const String spectrum = '/tools/spectrum';
  static const String nonWifiChannels = '/tools/non-wifi-channels';

  // Networking category — active network tools (native-only; web shows the
  // download-the-app fallback inside each screen, so the routes are always
  // registered and never crash on web).
  static const String interfaceInfo = '/tools/interface-info';

  /// Device Info — the device's own system facts (model, total memory, uptime,
  /// cellular IP). Batch 6. The id `device-info` is permanent (backs this route,
  /// the catalog entry, the help entry, the icon/graphic asset slots, and tests).
  static const String deviceInfo = '/tools/device-info';
  static const String dnsLookup = '/tools/dns-lookup';
  static const String portScan = '/tools/port-scan';
  static const String ping = '/tools/ping';
  static const String icmpPing = '/tools/icmp-ping';

  /// Ping Plotter — a sustained TCP-handshake ping charted over time (Wave B,
  /// 2026-06-04). The id `ping-plotter` is permanent (backs this route, the
  /// catalog entry, the help entry, the icon/graphic asset slots, and tests).
  static const String pingPlotter = '/tools/ping-plotter';
  static const String pingSweep = '/tools/ping-sweep';
  static const String netQuality = '/tools/net-quality';

  /// `/tools/wifi-vs-internet` — kept ALIVE as a redirect to the merged Test My
  /// Connection screen (Wave 4, Keith 2026-06-04). The pro `wifi-vs-internet`
  /// tool was absorbed into Test My Connection's expandable technical section,
  /// but this deep link is preserved so saved references keep working; it opens
  /// the merged screen in the EXPANDED (technical) state since a pro hitting the
  /// old route expects the detail view.
  static const String wifiVsInternet = '/tools/wifi-vs-internet';

  /// Test My Connection — the ONE merged connection tool (Wave 4, Keith
  /// 2026-06-04): consumer answer up top, the pro "Wi-Fi vs Internet" depth one
  /// tap away, plus a live Wi-Fi-signal sparkline card. The id
  /// `test-my-connection` is permanent (backs this route, the home hero, and
  /// tests). The tile was removed from the catalog; the home hero is the entry.
  static const String testMyConnection = '/tools/test-my-connection';
  static const String wifiInfo = '/tools/wifi-info';
  static const String cellularInfo = '/tools/cellular-info';
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

  /// Network Discovery — LAN host + service scan (TICKET-HSD-02). The id
  /// `network-discovery` is permanent (backs this route, the catalog entry, the
  /// icon/graphic assets, and tests; never renamed).
  static const String networkDiscovery = '/tools/network-discovery';

  // Quick Reference category — offline lookup tables (bundled assets, all
  // platforms incl. web).
  static const String portReference = '/tools/port-reference';

  /// US PLMN ID Reference — offline MCC/MNC lookup table (376 entries). The id
  /// `plmn-id-reference` is permanent (backs this route, the catalog entry, the
  /// asset, and tests; never renamed).
  static const String plmnReference = '/tools/plmn-id-reference';

  /// Optical Transceivers — offline reference of optical Ethernet variants
  /// (1G–400G) grouped by speed tier, plus the SFP→OSFP form-factor ladder
  /// (bundled JSON). The id `optical-transceivers` is permanent (route, catalog,
  /// asset, help, tests).
  static const String opticalTransceivers = '/tools/optical-transceivers';
  static const String osiModel = '/tools/osi-model';
  static const String topLevelDomains = '/tools/top-level-domains';
  static const String rjConnectors = '/tools/rj-connectors';
  static const String asciiReference = '/tools/ascii-reference';
  static const String emojiReference = '/tools/emoji-reference';

  /// Wi-Fi Glossary — 92 plain-language Wi-Fi term definitions, grouped by
  /// category (offline bundled JSON). The id `wifi-glossary` is permanent
  /// (backs this route, the catalog entry, the asset, and tests).
  static const String wifiGlossary = '/tools/wifi-glossary';

  /// Wi-Fi Authentication Glossary — 58 plain-language Wi-Fi authentication
  /// term definitions, grouped by category (offline bundled JSON). Reuses the
  /// same WifiGlossaryScreen + GlossaryService, pointed at a separate asset.
  /// The id `wifi-auth-glossary` is permanent (route, catalog, asset, tests).
  static const String wifiAuthGlossary = '/tools/wifi-auth-glossary';

  /// Antenna Connectors — an 18-connector practical Wi-Fi antenna-connector
  /// reference, grouped and searchable (offline bundled JSON). The id
  /// `antenna-connectors` is permanent (route, catalog, asset, diagram lookup,
  /// tests).
  static const String antennaConnectors = '/tools/antenna-connectors';

  /// Antenna Fundamentals — a read-along teaching/reference screen (Penn copy +
  /// Charta's seven line diagrams) covering azimuth/elevation, gain vs
  /// beamwidth, polarization, downtilt, reading a polar plot, and antenna
  /// selection. Quick Reference, v1.1. The id `antenna-fundamentals` is
  /// permanent (route, catalog, diagram lookup, help, tests).
  static const String antennaFundamentals = '/tools/antenna-fundamentals';

  // PDF reference cards — Keith's 10 laminated reference cards bundled as PDFs
  // (assets/reference-cards/<id>.pdf), rendered pinch-zoomable by the single
  // PdfReferenceScreen. They interleave alphabetically with the other Quick
  // Reference tools. ids: bubble-diagram is distinct from any existing tool;
  // mcs-index-card is deliberately distinct from the existing mcs-index table.
  static const String bubbleDiagram = '/tools/bubble-diagram';
  static const String troubleshootingCauses = '/tools/troubleshooting-causes';
  static const String top20Checklist = '/tools/top-20-checklist';
  static const String extendedChecklist = '/tools/extended-checklist';
  static const String extendedChecklistNonadvertised =
      '/tools/extended-checklist-nonadvertised';
  static const String connectionChecklist = '/tools/connection-checklist';
  static const String channelAllocations24ghz =
      '/tools/channel-allocations-24ghz';
  static const String channelAllocations5ghz =
      '/tools/channel-allocations-5ghz';
  static const String channelAllocations6ghz =
      '/tools/channel-allocations-6ghz';
  static const String mcsIndexCard = '/tools/mcs-index-card';

  // Calculators — Hex / ASCII converter + printable-ASCII table (pure math +
  // const-derived table, all platforms incl. web).
  static const String hexAscii = '/tools/hex-ascii';

  // Batch 4 standalone utilities.
  //   unit-converter: pure-math general unit converter (all platforms incl.web).
  //   qr-generator:   local QR render + share (all platforms; share via share_plus).
  //   dtmf-generator: local audio synthesis + playback via just_audio.
  static const String unitConverter = '/tools/unit-converter';
  static const String qrGenerator = '/tools/qr-generator';
  static const String dtmfGenerator = '/tools/dtmf-generator';

  // Command & Capture category — offline command / filter references (const
  // datasets, all platforms incl. web; reference text, never executed).
  static const String cliCommands = '/tools/cli-commands';
  static const String linuxWlanCommands = '/tools/linux-wlan-commands';
  static const String wiresharkFilters = '/tools/wireshark-80211-filters';

  // Checklists category — interactive session-state checklists (in-memory,
  // all platforms incl. web).
  static const String checklistApInstall = '/tools/checklist-ap-install';
  static const String checklistClientTest = '/tools/checklist-client-test';

  /// Map of static, argument-less routes. Categories use MaterialPageRoute
  /// directly because each category screen takes a typed `ToolCategory`.
  static final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
    home: (_) => const HomeScreen(),
    about: (_) => const AboutScreen(),
    helpBrowse: (_) => const HelpBrowseScreen(),
    educationalResources: (_) => const EducationalResourcesScreen(),
    search: (_) => const SearchScreen(),
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
    downtiltCoverage: (_) => const DowntiltCoverageScreen(),
    capacityPlanner: (_) => const CapacityPlannerScreen(),
    ptpLink: (_) => const PtpLinkScreen(),
    ipv6Subnet: (_) => const Ipv6SubnetScreen(),
    throughputCalc: (_) => const ThroughputCalcScreen(),
    rfAttenuation: (_) => const RfAttenuationScreen(),
    noiseFloor: (_) => const NoiseFloorScreen(),
    poeBudget: (_) => const PoeBudgetScreen(),
    wifiChannels: (_) => const WifiChannelsScreen(),
    standards: (_) => const StandardsScreen(),
    mcsIndex: (_) => const McsIndexScreen(),
    signalThresholds: (_) => const SignalThresholdsScreen(),
    wpaSecurity: (_) => const WpaSecurityScreen(),
    reasonCodes: (_) => const ReasonCodesScreen(),
    httpStatusCodes: (_) => const HttpStatusCodesScreen(),
    frameExchange: (_) => const FrameExchangeScreen(),
    dbReference: (_) => const DbReferenceScreen(),
    channelMap: (_) => const ChannelMapScreen(),
    ethernetPinout: (_) => const EthernetPinoutScreen(),
    coaxCable: (_) => const CoaxCableScreen(),
    ethernetCable: (_) => const EthernetCableScreen(),
    fiberOptic: (_) => const FiberOpticScreen(),
    rfConnectors: (_) => const RfConnectorsScreen(),
    roaming: (_) => const RoamingScreen(),
    apPlacement: (_) => const ApPlacementScreen(),
    poeReference: (_) => const PoeReferenceScreen(),
    spectrum: (_) => const SpectrumScreen(),
    nonWifiChannels: (_) => const NonWifiChannelsScreen(),
    interfaceInfo: (_) => const InterfaceInfoScreen(),
    deviceInfo: (_) => const DeviceInfoScreen(),
    dnsLookup: (_) => const DnsLookupScreen(),
    portScan: (_) => const PortScanScreen(),
    ping: (_) => const PingScreen(),
    icmpPing: (_) => const IcmpPingScreen(),
    pingPlotter: (_) => const PingPlotterScreen(),
    pingSweep: (_) => const PingSweepScreen(),
    // The bespoke 'net-quality' tool icon now ships at
    // assets/tool-icons/net-quality.svg (ascending signal bars with a live
    // pulse beat cresting over them — GL-003 §8.6 / §8.6.1). The _ToolRow icon
    // resolver (category_screen.dart) renders it via ToolAssets.hasIcon, so the
    // Icons.bolt fallback no longer triggers for this row.
    netQuality: (_) => const NetQualityScreen(),
    // Deep-link redirect: the absorbed pro `wifi-vs-internet` route now resolves
    // to the merged Test My Connection screen, opened in the EXPANDED technical
    // state (a pro hitting the old route expects the detail view). It does NOT
    // auto-run — the user taps Check to populate the verdict + technical data.
    wifiVsInternet: (_) =>
        const TestMyConnectionScreen(startExpanded: true),
    // `arguments: true` (passed by the home consumer hero) auto-runs the check
    // on arrival; a plain push without arguments stays tap-to-run.
    testMyConnection: (ctx) => TestMyConnectionScreen(
      autoStart: ModalRoute.of(ctx)?.settings.arguments == true,
    ),
    // TICKET-04: the consolidated cross-platform Wi-Fi Information tool
    // (macOS CoreWLAN + iOS companion-Shortcut behind one screen + normalized
    // model). The bespoke 'wifi-info' tool icon now ships at
    // assets/tool-icons/wifi-info.svg (gauge + Wi-Fi fan). No concept graphic
    // yet: the in-screen ConceptGraphicBand collapses to an empty SizedBox when
    // assets/tool-graphics/wifi-info.svg is absent, so the screen still renders.
    wifiInfo: (_) => const WifiInfoScreen(),
    // TICKET-02 cellular: the iOS-only Cellular Information tool (companion
    // Shortcut -> normalized CellularInfo). The bespoke 'cellular-info' tool
    // icon ships at assets/tool-icons/cellular-info.svg (ascending signal bars,
    // single-color silhouette per GL-003 §8.6.1). No concept graphic yet: the
    // in-screen ConceptGraphicBand collapses to an empty SizedBox when
    // assets/tool-graphics/cellular-info.svg is absent. macOS / web / Android /
    // Windows render the honest unavailable state.
    cellularInfo: (_) => const CellularInfoScreen(),
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
    networkDiscovery: (_) => const NetworkDiscoveryScreen(),
    portReference: (_) => const PortReferenceScreen(),
    plmnReference: (_) => const PlmnReferenceScreen(),
    opticalTransceivers: (_) => const OpticalTransceiversScreen(),
    osiModel: (_) => const OsiModelScreen(),
    topLevelDomains: (_) => const TopLevelDomainsScreen(),
    rjConnectors: (_) => const RjConnectorsScreen(),
    asciiReference: (_) => const AsciiReferenceScreen(),
    emojiReference: (_) => const EmojiReferenceScreen(),
    wifiGlossary: (_) => const WifiGlossaryScreen(),
    wifiAuthGlossary: (_) => const WifiGlossaryScreen(
          assetPath: kWifiAuthGlossaryAsset,
          title: 'Wi-Fi Authentication Glossary',
        ),
    antennaConnectors: (_) => const AntennaConnectorsScreen(),
    antennaFundamentals: (_) => const AntennaFundamentalsScreen(),
    // PDF reference cards — one PdfReferenceScreen per bundled card. Title +
    // asset path are the only per-card inputs; the screen is otherwise shared.
    bubbleDiagram: (_) => const PdfReferenceScreen(
          title: 'WLAN Pros Bubble Diagram',
          assetPath: 'assets/reference-cards/bubble-diagram.pdf',
          toolId: 'bubble-diagram',
        ),
    troubleshootingCauses: (_) => const PdfReferenceScreen(
          title: 'Wireless LAN Troubleshooting Causes',
          assetPath: 'assets/reference-cards/troubleshooting-causes.pdf',
          toolId: 'troubleshooting-causes',
        ),
    top20Checklist: (_) => const PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
        ),
    extendedChecklist: (_) => const PdfReferenceScreen(
          title: 'Extended Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/extended-checklist.pdf',
          toolId: 'extended-checklist',
        ),
    extendedChecklistNonadvertised: (_) => const PdfReferenceScreen(
          title: 'Extended Checklist (Non-Advertised Items)',
          assetPath:
              'assets/reference-cards/extended-checklist-nonadvertised.pdf',
          toolId: 'extended-checklist-nonadvertised',
        ),
    connectionChecklist: (_) => const PdfReferenceScreen(
          title: 'Wi-Fi Connection Checklist',
          assetPath: 'assets/reference-cards/connection-checklist.pdf',
          toolId: 'connection-checklist',
        ),
    channelAllocations24ghz: (_) => const PdfReferenceScreen(
          title: '2.4 GHz Channel Allocations',
          assetPath: 'assets/reference-cards/channel-allocations-24ghz.pdf',
          toolId: 'channel-allocations-24ghz',
        ),
    channelAllocations5ghz: (_) => const PdfReferenceScreen(
          title: '5 GHz Channel Allocations',
          assetPath: 'assets/reference-cards/channel-allocations-5ghz.pdf',
          toolId: 'channel-allocations-5ghz',
        ),
    channelAllocations6ghz: (_) => const PdfReferenceScreen(
          title: '6 GHz Channel Allocations',
          assetPath: 'assets/reference-cards/channel-allocations-6ghz.pdf',
          toolId: 'channel-allocations-6ghz',
        ),
    mcsIndexCard: (_) => const PdfReferenceScreen(
          title: 'Modulation and Coding Schemes (MCS Index)',
          assetPath: 'assets/reference-cards/mcs-index-card.pdf',
          toolId: 'mcs-index-card',
        ),
    hexAscii: (_) => const HexAsciiScreen(),
    unitConverter: (_) => const UnitConverterScreen(),
    qrGenerator: (_) => const QrGeneratorScreen(),
    dtmfGenerator: (_) => const DtmfGeneratorScreen(),
    cliCommands: (_) => const CliCommandsScreen(),
    linuxWlanCommands: (_) => const LinuxWlanCommandsScreen(),
    wiresharkFilters: (_) => const WiresharkFiltersScreen(),
    checklistApInstall: (_) => const ChecklistScreen(
          checklist: kApInstallChecklist,
          toolId: 'checklist-ap-install',
        ),
    checklistClientTest: (_) => const ChecklistScreen(
          checklist: kClientTestChecklist,
          toolId: 'checklist-client-test',
        ),
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
