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
import '../screens/tools/educational/spectrum_analysis_screen.dart';
import '../screens/tools/educational/ham_study_resources_screen.dart';
import '../screens/search_screen.dart';
import '../data/tool_catalog.dart' show kEducationalResourcesRoute;
import '../screens/tools/dbm_watt_converter.dart';
import '../screens/tools/calculators/architectural_scale_screen.dart';
import '../screens/tools/calculators/cable_loss_screen.dart';
import '../screens/tools/calculators/channel_frequency_converter_screen.dart';
import '../screens/tools/calculators/downtilt_screen.dart';
import '../screens/tools/calculators/earth_curvature_screen.dart';
import '../screens/tools/calculators/eirp_screen.dart';
import '../screens/tools/calculators/fresnel_screen.dart';
import '../screens/tools/calculators/fspl_screen.dart';
import '../screens/tools/calculators/link_budget_screen.dart';
import '../screens/tools/calculators/rain_fade_screen.dart';
import '../screens/tools/calculators/wavelength_screen.dart';
import '../screens/tools/calculators/antenna_length_screen.dart';
import '../screens/tools/calculators/hear_frequency_screen.dart';
import '../screens/tools/calculators/maidenhead_screen.dart';
import '../screens/tools/calculators/metric_conversion_screen.dart';
import '../screens/tools/calculators/unit_converter_screen.dart';
import '../screens/tools/calculators/qr_generator_screen.dart';
import '../screens/tools/calculators/dtmf_generator_screen.dart';
import '../screens/tools/calculators/morse_code_screen.dart';
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
import '../screens/tools/reference/standards_screen.dart';
import '../screens/tools/reference/mcs_index_screen.dart';
import '../screens/tools/reference/modulation_screen.dart';
import '../screens/tools/reference/signal_thresholds_screen.dart';
import '../screens/tools/reference/wpa_security_screen.dart';
import '../screens/tools/reference/http_status_codes_screen.dart';
import '../screens/tools/reference/optical_transceivers_screen.dart';
import '../screens/tools/reference/cable_bend_radius_screen.dart';
import '../screens/tools/reference/rack_units_screen.dart';
import '../screens/tools/reference/screw_drives_screen.dart';
import '../screens/tools/reference/markdown_cheatsheet_screen.dart';
import '../screens/tools/reference/wifi_standards_bodies_screen.dart';
import '../screens/tools/reference/wifi_exposure_perspective_screen.dart';
import '../screens/tools/reference/wifi_tools_comparison_screen.dart';
import '../screens/tools/reference/speedtest_services_screen.dart';
import '../screens/tools/reference/apple_wifi_tips_screen.dart';
import '../screens/tools/reference/macos_menubar_wifi_screen.dart';
// Tier-1 references (Pass 2b, 2026-06-12).
import '../screens/tools/reference/keyboard_shortcuts_screen.dart';
import '../screens/tools/reference/time_zones_screen.dart';
import '../screens/tools/reference/phonetic_alphabet_screen.dart';
import '../screens/tools/reference/diffie_hellman_screen.dart';
import '../screens/tools/reference/rf_bands_screen.dart';
import '../screens/tools/reference/wifi_halow_screen.dart';
import '../screens/tools/reference/reason_codes_screen.dart';
import '../screens/tools/reference/frame_exchange_screen.dart';
import '../screens/tools/reference/db_reference_screen.dart';
import '../screens/tools/reference/channel_map_screen.dart';
import '../screens/tools/reference/coax_cable_screen.dart';
import '../screens/tools/reference/ethernet_cable_screen.dart';
import '../screens/tools/reference/antenna_connectors_screen.dart';
import '../screens/tools/reference/antenna_fundamentals_screen.dart';
import '../screens/tools/reference/fiber_optic_screen.dart';
import '../screens/tools/reference/roaming_screen.dart';
import '../screens/tools/reference/non_wifi_channels_screen.dart';
import '../screens/tools/reference/emergency_phrases_screen.dart';
import '../screens/tools/reference/wifi_glossary_screen.dart';
import '../screens/tools/reference/plmn_reference_screen.dart';
import '../screens/tools/reference/poe_reference_screen.dart';
import '../screens/tools/reference/power_phasing_screen.dart';
import '../screens/tools/reference/ohms_law_screen.dart';
import '../screens/tools/reference/cooling_thermal_screen.dart';
import '../screens/tools/reference/iec_connectors_screen.dart';
import '../screens/tools/reference/nema_connectors_screen.dart';
import '../screens/tools/reference/international_plugs_screen.dart';
import '../screens/tools/reference/spectrum_screen.dart';
// Ham Radio band references (2026-06-28): band plan, band/wavelength bridge,
// ITU band designations, and Part 15 vs Part 97. Read-only, all platforms.
import '../screens/tools/reference/ham_band_plan_screen.dart';
import '../screens/tools/reference/ham_band_wavelengths_screen.dart';
import '../screens/tools/reference/band_designations_screen.dart';
import '../screens/tools/reference/part15_vs_part97_screen.dart';
// Reference batch (2026-06-08): 14 new read-only reference screens.
import '../screens/tools/reference/ip_address_reference_screen.dart';
import '../screens/tools/reference/cidr_table_screen.dart';
import '../screens/tools/reference/naming_conventions_screen.dart';
import '../screens/tools/reference/dns_record_types_screen.dart';
import '../screens/tools/reference/dhcp_options_screen.dart';
import '../screens/tools/reference/http_methods_screen.dart';
import '../screens/tools/reference/dscp_qos_screen.dart';
import '../screens/tools/reference/eap_types_screen.dart';
import '../screens/tools/reference/enclosure_ratings_screen.dart';
import '../screens/tools/reference/hazardous_locations_screen.dart';
import '../screens/tools/reference/nec_gotchas_screen.dart';
import '../screens/tools/reference/plan_set_literacy_screen.dart';
import '../screens/tools/reference/safety_basics_screen.dart';
import '../screens/tools/reference/site_access_screen.dart';
import '../screens/tools/reference/cad_bim_formats_screen.dart';
import '../screens/tools/reference/structured_cabling_screen.dart';
import '../screens/tools/reference/aec_process_glossary_screen.dart';
import '../screens/tools/reference/cloud_tool_trust_screen.dart';
import '../screens/tools/reference/network_in_scope_screen.dart';
import '../screens/tools/reference/adjacent_radio_systems_screen.dart';
import '../screens/tools/reference/credentials_licenses_screen.dart';
import '../screens/tools/reference/by_vertical_index_screen.dart';
import '../screens/tools/reference/healthcare_vertical_screen.dart';
import '../screens/tools/reference/data_centers_wifi_screen.dart';
import '../screens/tools/reference/facility_spaces_screen.dart';
import '../screens/tools/reference/led_decoder_screen.dart';
import '../screens/tools/reference/vendor_model_decode_screen.dart';
import '../screens/tools/reference/wifi_feature_matrix_screen.dart';
import '../screens/tools/reference/regulatory_domains_screen.dart';
import '../screens/tools/reference/datetime_standards_screen.dart';
import '../screens/tools/reference/data_units_screen.dart';
import '../screens/tools/reference/hash_lengths_screen.dart';
import '../screens/tools/reference/regex_cheatsheet_screen.dart';
import '../screens/tools/network/arp_ndp_screen.dart';
import '../screens/tools/network/bgp_asn_screen.dart';
import '../screens/tools/network/dns_lookup_screen.dart';
import '../screens/tools/network/http_header_screen.dart';
import '../screens/tools/network/device_info_screen.dart';
import '../screens/tools/network/interface_info_screen.dart';
import '../screens/tools/network/icmp_ping_screen.dart';
import '../screens/tools/network/ip_geo_screen.dart';
import '../screens/tools/network/my_current_location_screen.dart';
import '../screens/tools/network/mac_oui_screen.dart';
import '../screens/tools/network/network_discovery_screen.dart';
import '../screens/tools/network/ap_scan_screen.dart';
import '../screens/tools/network/mobile_traceroute_screen.dart';
import '../screens/tools/network/net_quality_screen.dart';
import '../screens/tools/network/ntp_screen.dart';
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
import '../screens/tools/network/roaming_log_screen.dart';
import '../screens/tools/calculators/hex_ascii_screen.dart';
import '../screens/tools/command/cli_commands_screen.dart';
import '../screens/tools/command/linux_wlan_commands_screen.dart';
import '../screens/tools/command/lldp_cdp_reference_screen.dart';
import '../screens/tools/command/wireshark_filters_screen.dart';
import '../screens/tools/reference/osi_model_screen.dart';
import '../screens/tools/reference/freeradius_wlanpi_screen.dart';
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

  static const String channelFrequency = '/tools/channel-frequency';

  // RF Calculators category — pure-math tools (no network, all platforms incl.
  // web). Formulas mirror the RF Tools PWA (www/app.js) to the decimal.
  static const String fspl = '/tools/fspl';
  static const String eirp = '/tools/eirp';
  static const String fresnel = '/tools/fresnel';
  static const String cableLoss = '/tools/cable-loss';
  static const String linkBudget = '/tools/link-budget';
  // AEC & Documentation field-reference set (pilot, 2026-07-05). Pure math,
  // offline, all platforms incl. web.
  static const String architecturalScale = '/tools/architectural-scale';
  static const String wavelength = '/tools/wavelength';
  // Ham Radio pure-math tools (no network, all platforms incl. web).
  static const String antennaLength = '/tools/antenna-length';
  static const String maidenhead = '/tools/maidenhead-grid';
  // Learn / RF intuition (2026-06-28). Real-time audio synthesis (flutter_soloud
  // behind the ToneEngine seam); on-device DSP only, all platforms incl. web.
  static const String hearFrequency = '/tools/hear-frequency';
  // Ham Radio band references (2026-06-28). Read-only, all platforms incl. web.
  static const String hamBandPlan = '/tools/ham-band-plan';
  static const String hamBandWavelengths = '/tools/ham-band-wavelengths';
  static const String bandDesignations = '/tools/band-designations';
  static const String part15Part97 = '/tools/part15-part97';
  static const String hamStudyResources = '/tools/ham-study-resources';
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
  // NOTE: `/tools/wifi-channels` (the plainer channels table) was REMOVED
  // 2026-06-06 (BF6-13) as a duplicate of Channel Map; its HaLow data folded
  // into Channel Map.
  static const String standards = '/tools/standards';
  static const String mcsIndex = '/tools/mcs-index';
  static const String modulation = '/tools/modulation';
  static const String signalThresholds = '/tools/signal-thresholds';
  static const String wpaSecurity = '/tools/wpa-security';
  static const String reasonCodes = '/tools/reason-codes';
  static const String httpStatusCodes = '/tools/http-status-codes';
  static const String frameExchange = '/tools/frame-exchange';
  static const String dbReference = '/tools/db-reference';
  static const String channelMap = '/tools/channel-map';
  static const String coaxCable = '/tools/coax-cable';
  static const String ethernetCable = '/tools/ethernet-cable';
  static const String fiberOptic = '/tools/fiber-optic';
  static const String cableBendRadius = '/tools/cable-bend-radius';
  static const String rackUnits = '/tools/rack-units';
  static const String screwDrives = '/tools/screw-drives';
  // `/tools/rf-connectors` was REMOVED 2026-06-06 (BF6-18): RF Connectors merged
  // into the single Antenna Connectors tool.
  static const String roaming = '/tools/roaming';
  static const String poeReference = '/tools/poe-reference';
  // Field & Trade Reference set (pilot, 2026-07-05). Read-only IP/NEMA ingress
  // reference; static content, offline, all platforms incl. web.
  static const String enclosureRatings = '/tools/enclosure-ratings';
  // Field Reference #3/#4 (2026-07-05). Read-only recognize-and-defer code
  // references; static content, offline, all platforms incl. web.
  static const String hazardousLocations = '/tools/hazardous-locations';
  static const String necGotchas = '/tools/nec-gotchas';
  // Field Reference #5/#6/#7 (2026-07-05). Read-only PPE/ESD, plan-set literacy,
  // and site-access references; static content, offline, all platforms incl. web.
  static const String safetyBasics = '/tools/safety-basics';
  static const String planSetLiteracy = '/tools/plan-set-literacy';
  static const String siteAccess = '/tools/site-access';
  // Field Reference #8/#9/#10 (2026-07-05). Read-only text-reference screens (no
  // decoder plate): CAD/BIM formats, TIA/BICSI structured cabling, and the AEC
  // process + glossary; static content, offline, all platforms incl. web.
  static const String cadBimFormats = '/tools/cad-bim-formats';
  static const String structuredCabling = '/tools/structured-cabling';
  static const String aecProcessGlossary = '/tools/aec-process-glossary';
  // Field & Trade Reference set, second wave (2026-07-05). Read-only references
  // in three new Quick Reference subgroups; static content, offline, all
  // platforms incl. web. Six carry a Charta decoder plate; two
  // (by-vertical-index, data-centers-wifi) are text-reference.
  static const String cloudToolTrust = '/tools/cloud-tool-trust';
  static const String networkInScope = '/tools/network-in-scope';
  static const String adjacentRadioSystems = '/tools/adjacent-radio-systems';
  static const String credentialsLicenses = '/tools/credentials-licenses';
  static const String byVerticalIndex = '/tools/by-vertical-index';
  static const String healthcareVertical = '/tools/healthcare-vertical';
  static const String dataCentersWifi = '/tools/data-centers-wifi';
  static const String facilitySpaces = '/tools/facility-spaces';
  // Vendor & Hardware (2026-07-05): two INTERACTIVE drill-down references
  // (selection state, not static screens). Local const data, offline, all
  // platforms incl. web.
  static const String ledDecoder = '/tools/led-decoder';
  static const String vendorModelDecode = '/tools/vendor-model-decode';

  /// Power Phasing — the pilot reference for the Power & Cooling category. The
  /// id `power-phasing` is permanent (backs this route, the catalog entry, the
  /// help entry, the waveform asset slots, and tests).
  static const String powerPhasing = '/tools/power-phasing';

  // Power & Cooling — pages 2-6 of the reference category (Keith, 2026-06-08).
  // Each id is permanent (backs its route, catalog entry, help entry, and tests).
  static const String ohmsLaw = '/tools/ohms-law';
  static const String coolingThermal = '/tools/cooling-thermal';
  static const String iecConnectors = '/tools/iec-connectors';
  static const String nemaConnectors = '/tools/nema-connectors';
  static const String internationalPlugs = '/tools/international-plugs';
  static const String spectrum = '/tools/spectrum';
  static const String nonWifiChannels = '/tools/non-wifi-channels';

  // Reference batch (2026-06-08): 14 new Quick Reference screens across the new
  // Addressing & Subnetting / Models & Standards / Time & Formats sub-categories
  // and additions to Protocols, Wi-Fi & RF, and Encoding.
  static const String ipAddressReference = '/tools/ip-address-reference';
  static const String cidrTable = '/tools/cidr-table';
  static const String namingConventions = '/tools/naming-conventions';
  static const String dnsRecordTypes = '/tools/dns-record-types';
  static const String dhcpOptions = '/tools/dhcp-options';
  static const String httpMethods = '/tools/http-methods';
  static const String dscpQos = '/tools/dscp-qos';
  static const String eapTypes = '/tools/eap-types';
  static const String wifiFeatureMatrix = '/tools/wifi-feature-matrix';
  static const String regulatoryDomains = '/tools/regulatory-domains';
  static const String wifiStandardsBodies = '/tools/wifi-standards-bodies';
  static const String datetimeStandards = '/tools/datetime-standards';
  static const String dataUnits = '/tools/data-units';
  static const String hashLengths = '/tools/hash-lengths';
  static const String regexCheatsheet = '/tools/regex-cheatsheet';
  static const String markdownCheatsheet = '/tools/markdown-cheatsheet';

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
  static const String roamingLog = '/tools/roaming-log';
  static const String traceroute = '/tools/traceroute';
  static const String mobileTraceroute = '/tools/mobile-traceroute';
  static const String sslInspect = '/tools/ssl-inspect';
  static const String httpHeaders = '/tools/http-headers';
  static const String whois = '/tools/whois';
  static const String wakeOnLan = '/tools/wake-on-lan';
  static const String arpNdp = '/tools/arp-ndp';
  static const String bgpAsn = '/tools/bgp-asn';
  static const String ipGeo = '/tools/ip-geo';

  /// My Current Location (BF5-16) — auto-runs the GPS fix on open and shows
  /// latitude / longitude / altitude / accuracy directly. Reuses the
  /// DeviceLocationService backend behind the Lat / Long calculator.
  static const String myCurrentLocation = '/tools/my-current-location';
  static const String macOui = '/tools/mac-oui';
  static const String packetSender = '/tools/packet-sender';
  static const String ntpTime = '/tools/ntp-time';
  static const String ipv4Subnet = '/tools/ipv4-subnet';

  /// Network Discovery — LAN host + service scan (TICKET-HSD-02). The id
  /// `network-discovery` is permanent (backs this route, the catalog entry, the
  /// icon/graphic assets, and tests; never renamed).
  static const String networkDiscovery = '/tools/network-discovery';

  /// Nearby AP Scan — wired for Android today. Lists nearby Wi-Fi access points
  /// via the Android scan API; gated out of the catalog on every other platform.
  /// Per-platform reality: iOS and macOS block nearby-AP scanning at the OS
  /// level; Windows IS capable via its Native Wifi API but the Windows scan path
  /// isn't wired into this tool yet (not Apple-blocked). The id `nearby-ap-scan`
  /// is permanent (backs this route, the catalog entry, the help entry, tests).
  static const String nearbyApScan = '/tools/nearby-ap-scan';

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

  /// How Strong Is Wi-Fi, Really? — a read-along Quick Reference screen putting
  /// Wi-Fi RF exposure in perspective against everyday sunlight (verified, stated
  /// numbers; no inputs). The id `wifi-exposure-perspective` is permanent (route,
  /// catalog, concept graphic, help, tests) even if the display title is renamed.
  static const String wifiExposurePerspective =
      '/tools/wifi-exposure-perspective';

  /// Wi-Fi Tools Comparison — v1.1 beta. Offline, vendor-neutral capability-and-
  /// cost reference of professional Wi-Fi survey/design/spectrum/troubleshooting
  /// toolkits, grouped by activity (bundled JSON). TCO figures are modeled
  /// estimates carried with a date-stamp + beta-review disclaimer. The id
  /// `wifi-tools-comparison` is permanent (route, catalog, asset, help, tests).
  static const String wifiToolsComparison = '/tools/wifi-tools-comparison';

  /// Speed Test Services — offline curated reference of the popular internet
  /// speed tests and what each measures. The id `speedtest-services` is
  /// permanent (backs this route, the catalog entry, the bundled logo assets,
  /// the help entry, and tests).
  static const String speedtestServices = '/tools/speedtest-services';

  // Apple Wi-Fi references (2026-06-12, Tier-1). Apple-Wi-Fi-Tips distills
  // Apple's support docs (settings, Wireless Diagnostics, iOS steps) and links
  // to macOS-Menubar-Wifi for the per-field RF meanings. All platforms (const
  // reference text + url_launcher; nothing fetched, nothing shelled out).
  static const String appleWifiTips = '/tools/apple-wifi-tips';
  static const String macosMenubarWifi = '/tools/macos-menubar-wifi';

  // Tier-1 references (Pass 2b, 2026-06-12). Each id is permanent (backs its
  // route, catalog entry, help entry, keyword set, embedded-PNG asset slot where
  // applicable, and tests).
  static const String keyboardShortcuts = '/tools/keyboard-shortcuts';
  static const String timeZoneMaps = '/tools/time-zone-maps';
  static const String phoneticAlphabet = '/tools/phonetic-alphabet';
  static const String diffieHellman = '/tools/diffie-hellman';

  // Tier-1 references (integration batch, 2026-06-12): RF Bands frequency map
  // and Wi-Fi HaLow (802.11ah) sub-GHz reference.
  static const String rfBands = '/tools/rf-bands';
  static const String wifiHalow = '/tools/wifi-halow';

  static const String osiModel = '/tools/osi-model';

  /// FreeRADIUS on WLAN Pi — a how-to / guide screen (v1.1). Bundles Ferney
  /// Munoz's install script (assets/downloads/install_freeradius.sh), shows it
  /// inline + offers it as a download, with a prominent lab caveat. The id
  /// `freeradius-wlanpi` is permanent (route, catalog, concept graphic, help,
  /// tests).
  static const String freeradiusWlanpi = '/tools/freeradius-wlanpi';

  static const String topLevelDomains = '/tools/top-level-domains';
  static const String rjConnectors = '/tools/rj-connectors';
  static const String asciiReference = '/tools/ascii-reference';
  static const String emojiReference = '/tools/emoji-reference';

  /// Emergency Phrases — ~124 travel/emergency phrases in English with Spanish,
  /// French, Italian, and German, grouped by situation and searchable (offline
  /// bundled JSON). For a Wi-Fi pro working on-site internationally. The id
  /// `emergency-phrases` is permanent (route, catalog, asset, help, tests).
  static const String emergencyPhrases = '/tools/emergency-phrases';

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

  /// Spectrum Analysis — a read-along teaching MODULE (hub + eight topic
  /// screens) on what a spectrum analyzer is, how to read it, how to fingerprint
  /// interference (a nine-card signature gallery), and how to mitigate it. An
  /// in-app reference in Educational Resources, alongside Antenna Fundamentals.
  /// The id `spectrum-analysis` is permanent (route, catalog, help, tests). The
  /// eight topic screens are pushed from the hub via MaterialPageRoute, so only
  /// this hub route is registered.
  static const String spectrumAnalysis = '/tools/spectrum-analysis';

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

  // Ham Radio PDF reference cards (2026-06-28) — two of Keith's corrected
  // amateur-radio references bundled as PDFs and rendered by the same shared
  // PdfReferenceScreen. They live in the Quick Reference "Ham Radio" subgroup
  // beside the in-app band references.
  static const String generalLicenseFrequencyChart =
      '/tools/general-license-frequency-chart';
  static const String hamRadioGeneralExamStudyNotes =
      '/tools/ham-radio-general-exam-study-notes';

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
  static const String morseCode = '/tools/morse-code';

  // Command & Capture category — offline command / filter references (const
  // datasets, all platforms incl. web; reference text, never executed).
  static const String cliCommands = '/tools/cli-commands';
  static const String linuxWlanCommands = '/tools/linux-wlan-commands';
  static const String lldpCdpReference = '/tools/lldp-cdp-reference';
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
    channelFrequency: (_) => const ChannelFrequencyConverterScreen(),
    fspl: (_) => const FsplScreen(),
    eirp: (_) => const EirpScreen(),
    fresnel: (_) => const FresnelScreen(),
    cableLoss: (_) => const CableLossScreen(),
    architecturalScale: (_) => const ArchitecturalScaleScreen(),
    linkBudget: (_) => const LinkBudgetScreen(),
    wavelength: (_) => const WavelengthScreen(),
    antennaLength: (_) => const AntennaLengthScreen(),
    hearFrequency: (_) => const HearFrequencyScreen(),
    maidenhead: (_) => const MaidenheadScreen(),
    hamBandPlan: (_) => const HamBandPlanScreen(),
    hamBandWavelengths: (_) => const HamBandWavelengthsScreen(),
    bandDesignations: (_) => const BandDesignationsScreen(),
    part15Part97: (_) => const Part15VsPart97Screen(),
    hamStudyResources: (_) => const HamStudyResourcesScreen(),
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
    standards: (_) => const StandardsScreen(),
    mcsIndex: (_) => const McsIndexScreen(),
    modulation: (_) => const ModulationScreen(),
    signalThresholds: (_) => const SignalThresholdsScreen(),
    wpaSecurity: (_) => const WpaSecurityScreen(),
    reasonCodes: (_) => const ReasonCodesScreen(),
    httpStatusCodes: (_) => const HttpStatusCodesScreen(),
    frameExchange: (_) => const FrameExchangeScreen(),
    dbReference: (_) => const DbReferenceScreen(),
    channelMap: (_) => const ChannelMapScreen(),
    coaxCable: (_) => const CoaxCableScreen(),
    ethernetCable: (_) => const EthernetCableScreen(),
    fiberOptic: (_) => const FiberOpticScreen(),
    cableBendRadius: (_) => const CableBendRadiusScreen(),
    rackUnits: (_) => const RackUnitsScreen(),
    screwDrives: (_) => const ScrewDrivesScreen(),
    roaming: (_) => const RoamingScreen(),
    poeReference: (_) => const PoeReferenceScreen(),
    enclosureRatings: (_) => const EnclosureRatingsScreen(),
    hazardousLocations: (_) => const HazardousLocationsScreen(),
    necGotchas: (_) => const NecGotchasScreen(),
    safetyBasics: (_) => const SafetyBasicsScreen(),
    planSetLiteracy: (_) => const PlanSetLiteracyScreen(),
    siteAccess: (_) => const SiteAccessScreen(),
    cadBimFormats: (_) => const CadBimFormatsScreen(),
    structuredCabling: (_) => const StructuredCablingScreen(),
    aecProcessGlossary: (_) => const AecProcessGlossaryScreen(),
    cloudToolTrust: (_) => const CloudToolTrustScreen(),
    networkInScope: (_) => const NetworkInScopeScreen(),
    adjacentRadioSystems: (_) => const AdjacentRadioSystemsScreen(),
    credentialsLicenses: (_) => const CredentialsLicensesScreen(),
    byVerticalIndex: (_) => const ByVerticalIndexScreen(),
    healthcareVertical: (_) => const HealthcareVerticalScreen(),
    dataCentersWifi: (_) => const DataCentersWifiScreen(),
    facilitySpaces: (_) => const FacilitySpacesScreen(),
    ledDecoder: (_) => const LedDecoderScreen(),
    vendorModelDecode: (_) => const VendorModelDecodeScreen(),
    powerPhasing: (_) => const PowerPhasingScreen(),
    ohmsLaw: (_) => const OhmsLawScreen(),
    coolingThermal: (_) => const CoolingThermalScreen(),
    iecConnectors: (_) => const IecConnectorsScreen(),
    nemaConnectors: (_) => const NemaConnectorsScreen(),
    internationalPlugs: (_) => const InternationalPlugsScreen(),
    spectrum: (_) => const SpectrumScreen(),
    nonWifiChannels: (_) => const NonWifiChannelsScreen(),
    // Reference batch (2026-06-08).
    ipAddressReference: (_) => const IpAddressReferenceScreen(),
    cidrTable: (_) => const CidrTableScreen(),
    namingConventions: (_) => const NamingConventionsScreen(),
    dnsRecordTypes: (_) => const DnsRecordTypesScreen(),
    dhcpOptions: (_) => const DhcpOptionsScreen(),
    httpMethods: (_) => const HttpMethodsScreen(),
    dscpQos: (_) => const DscpQosScreen(),
    eapTypes: (_) => const EapTypesScreen(),
    wifiFeatureMatrix: (_) => const WifiFeatureMatrixScreen(),
    regulatoryDomains: (_) => const RegulatoryDomainsScreen(),
    wifiStandardsBodies: (context) => WifiStandardsBodiesScreen(
      onOpenRegulatoryDomains: () =>
          Navigator.of(context).pushNamed(regulatoryDomains),
    ),
    datetimeStandards: (_) => const DatetimeStandardsScreen(),
    dataUnits: (_) => const DataUnitsScreen(),
    hashLengths: (_) => const HashLengthsScreen(),
    regexCheatsheet: (_) => const RegexCheatsheetScreen(),
    markdownCheatsheet: (_) => const MarkdownCheatsheetScreen(),
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
    wifiVsInternet: (_) => const TestMyConnectionScreen(startExpanded: true),
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
    // Feature 2 (Felix 2026-06-13): the foreground Roaming Log — records BSSID
    // transitions within the same SSID during an open session, built on the
    // shared WifiSignalSampler. macOS auto-polls; iOS records while foregrounded
    // behind a Start tap (no background Wi-Fi monitoring exists on iOS).
    roamingLog: (_) => const RoamingLogScreen(),
    traceroute: (_) => const TracerouteScreen(),
    mobileTraceroute: (_) => const MobileTracerouteScreen(),
    sslInspect: (_) => const SslInspectScreen(),
    httpHeaders: (_) => const HttpHeaderScreen(),
    whois: (_) => const WhoisScreen(),
    wakeOnLan: (_) => const WakeOnLanScreen(),
    arpNdp: (_) => const ArpNdpScreen(),
    bgpAsn: (_) => const BgpAsnScreen(),
    ipGeo: (_) => const IpGeoScreen(),
    myCurrentLocation: (_) => const MyCurrentLocationScreen(),
    macOui: (_) => const MacOuiScreen(),
    packetSender: (_) => const PacketSenderScreen(),
    ntpTime: (_) => const NtpScreen(),
    ipv4Subnet: (_) => const SubnetCalcScreen(),
    networkDiscovery: (_) => const NetworkDiscoveryScreen(),
    nearbyApScan: (_) => const ApScanScreen(),
    portReference: (_) => const PortReferenceScreen(),
    plmnReference: (_) => const PlmnReferenceScreen(),
    opticalTransceivers: (_) => const OpticalTransceiversScreen(),
    wifiExposurePerspective: (_) => const WifiExposurePerspectiveScreen(),
    wifiToolsComparison: (_) => const WifiToolsComparisonScreen(),
    speedtestServices: (_) => const SpeedtestServicesScreen(),
    appleWifiTips: (_) => const AppleWifiTipsScreen(),
    macosMenubarWifi: (_) => const MacosMenubarWifiScreen(),
    // Tier-1 references (Pass 2b, 2026-06-12).
    keyboardShortcuts: (_) => const KeyboardShortcutsScreen(),
    timeZoneMaps: (_) => const TimeZonesScreen(),
    rfBands: (_) => const RfBandsScreen(),
    wifiHalow: (_) => const WifiHalowScreen(),
    phoneticAlphabet: (_) => const PhoneticAlphabetScreen(),
    diffieHellman: (_) => const DiffieHellmanScreen(),
    osiModel: (_) => const OsiModelScreen(),
    topLevelDomains: (_) => const TopLevelDomainsScreen(),
    rjConnectors: (_) => const RjConnectorsScreen(),
    asciiReference: (_) => const AsciiReferenceScreen(),
    emojiReference: (_) => const EmojiReferenceScreen(),
    freeradiusWlanpi: (_) => const FreeradiusWlanpiScreen(),
    emergencyPhrases: (_) => const EmergencyPhrasesScreen(),
    wifiGlossary: (_) => const WifiGlossaryScreen(),
    wifiAuthGlossary: (_) => const WifiGlossaryScreen(
      assetPath: kWifiAuthGlossaryAsset,
      title: 'Wi-Fi Authentication Glossary',
    ),
    antennaConnectors: (_) => const AntennaConnectorsScreen(),
    antennaFundamentals: (_) => const AntennaFundamentalsScreen(),
    spectrumAnalysis: (_) => const SpectrumAnalysisScreen(),
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
      assetPath: 'assets/reference-cards/extended-checklist-nonadvertised.pdf',
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
    generalLicenseFrequencyChart: (_) => const PdfReferenceScreen(
      title: 'General License Frequency Chart',
      assetPath: 'assets/reference-cards/general-license-frequency-chart.pdf',
      toolId: 'general-license-frequency-chart',
    ),
    hamRadioGeneralExamStudyNotes: (_) => const PdfReferenceScreen(
      title: 'Ham Radio General Exam Study Notes',
      assetPath:
          'assets/reference-cards/ham-radio-general-exam-study-notes.pdf',
      toolId: 'ham-radio-general-exam-study-notes',
    ),
    hexAscii: (_) => const HexAsciiScreen(),
    unitConverter: (_) => const UnitConverterScreen(),
    qrGenerator: (_) => const QrGeneratorScreen(),
    dtmfGenerator: (_) => const DtmfGeneratorScreen(),
    morseCode: (_) => const MorseCodeScreen(),
    cliCommands: (_) => const CliCommandsScreen(),
    linuxWlanCommands: (_) => const LinuxWlanCommandsScreen(),
    lldpCdpReference: (_) => const LldpCdpReferenceScreen(),
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
