// Apple Wi-Fi Support Tips — data for the data-driven reference screen.
//
// Source of truth: Deliverables/2026-06-12-toolbox-tier1-references/
// apple-wifi-tips/DATA.md. Every row is distilled from Apple's own support
// documentation and footnoted to the Apple source URL. Verified live 2026-06-12.
//
// Four sections (A-D):
//   A. Recommended router / Wi-Fi settings for Apple devices.
//   B. Run Wireless Diagnostics on a Mac (ordered steps + the Window menu).
//   C. The Option-click Wi-Fi menu (links out to the macOS menu-bar reference).
//   D. iOS / iPadOS Wi-Fi troubleshooting steps (Apple's ordered checklist).
//
// HONESTY (GL-005): where Apple is silent (transmit power) the silence is
// stated, never filled. The single-source note for the iOS steps is carried as
// a real on-screen caveat, not hidden.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" casing throughout.

/// One Apple support source: a label and its URL. Tappable via url_launcher.
class AppleSource {
  const AppleSource(this.id, this.label, this.url);

  /// Short id used to attach a row to its source (e.g. 'settings').
  final String id;

  /// Human label shown on the link chip (the article title).
  final String label;

  /// The Apple support article URL.
  final String url;
}

/// One recommended-setting row (Section A): the setting and Apple's call.
class AppleSettingRow {
  const AppleSettingRow(this.setting, this.recommendation, {this.sourceId = 'settings'});

  final String setting;
  final String recommendation;
  final String sourceId;
}

/// One ordered step (Sections B and D): a step body and its source.
class AppleStep {
  const AppleStep(this.body, {this.sourceId});

  final String body;
  final String? sourceId;
}

/// One Wireless Diagnostics Window-menu utility (Section B).
class DiagUtility {
  const DiagUtility(this.name, this.what);

  final String name;
  final String what;
}

/// The four Apple sources cited across the screen.
const Map<String, AppleSource> kAppleSources = <String, AppleSource>{
  'settings': AppleSource(
    'settings',
    'Recommended settings for Wi-Fi routers and access points',
    'https://support.apple.com/en-us/102766',
  ),
  'diag': AppleSource(
    'diag',
    'Use Wireless Diagnostics on your Mac',
    'https://support.apple.com/guide/mac-help/use-wireless-diagnostics-mchlf4de377f/mac',
  ),
  'ios': AppleSource(
    'ios',
    "If you can't connect to Wi-Fi on your iPhone or iPad",
    'https://support.apple.com/en-us/111786',
  ),
};

// ── Section A — Recommended router / Wi-Fi settings ──

const String kAppleSettingsIntro =
    'Apple publishes one canonical article of recommended router and '
    'access-point settings. Apply the same settings to any router or AP serving '
    'Apple devices.';

const List<AppleSettingRow> kAppleSettings = <AppleSettingRow>[
  AppleSettingRow('Security',
      'Set to WPA3 Personal for better security, or WPA2/WPA3 Transitional for compatibility with older devices. Avoid WEP, TKIP, and WPA/WPA2 mixed modes.'),
  AppleSettingRow('Network name (SSID)',
      'Set to a single, unique, case-sensitive name for all bands. Use the identical name on 2.4 GHz, 5 GHz, and 6 GHz so devices roam and band-steer reliably.'),
  AppleSettingRow('Hidden network',
      'Set to Disabled. Hiding the SSID provides no security benefit and can expose privacy information.'),
  AppleSettingRow('MAC address filtering',
      'Set to Disabled. It cannot prevent network monitoring, and MAC addresses are easily spoofed.'),
  AppleSettingRow('Automatic firmware updates', 'Set to Enabled.'),
  AppleSettingRow('Radio mode', 'Set to All (preferred), or Wi-Fi 2 through Wi-Fi 6 or later.'),
  AppleSettingRow('Bands', 'Enable all bands supported by your router.'),
  AppleSettingRow('Channel',
      'Set to Auto. If Auto is unavailable, manually select the best-performing channel for the environment.'),
  AppleSettingRow('Channel width',
      'Set to 20 MHz for the 2.4 GHz band. Set to Auto or all widths for the 5 GHz and 6 GHz bands.'),
  AppleSettingRow('DHCP', 'Set to Enabled if your router is the only DHCP server on the network.'),
  AppleSettingRow('DHCP lease time',
      'Set to 8 hours for home or office networks. Set to 1 hour for hotspots or guest networks.'),
  AppleSettingRow('NAT', 'Set to Enabled if your router is the only device providing NAT on the network.'),
  AppleSettingRow('WMM (Wi-Fi Multimedia)', 'Set to Enabled.'),
  AppleSettingRow('DNS server', 'Continue with ISP defaults, or specify an alternative server.'),
];

/// Where Apple is silent. Stated rather than filled (GL-005).
const String kAppleSettingsSilenceNote =
    'Apple does not cover transmit power in the recommended-settings article. '
    'There is no Apple transmit-power recommendation to present.';

/// Keith domain note (clearly attributed to Keith, NOT Apple).
const String kAppleSettingsKeithNote =
    'Domain note (Keith, not Apple): "20 MHz on 2.4 GHz" and "single SSID for '
    'all bands" are the load-bearing items most consumer setups get wrong. '
    'Splitting 2.4 and 5 GHz into separate names defeats the device own band '
    'selection.';

// ── Section B — Wireless Diagnostics on a Mac ──

const String kAppleDiagIntro =
    'Apple ships Wireless Diagnostics in every macOS install. It is the '
    'supported successor to the retired airport CLI. It does not change your '
    'network settings.';

const List<AppleStep> kAppleDiagSteps = <AppleStep>[
  AppleStep('Quit all open apps and join (or stay on) the Wi-Fi network you are troubleshooting.', sourceId: 'diag'),
  AppleStep('Press and hold the Option key, click the Wi-Fi status menu in the menu bar, then choose Open Wireless Diagnostics.', sourceId: 'diag'),
  AppleStep('Follow the onscreen prompts to analyze the connection.', sourceId: 'diag'),
  AppleStep('After the analysis is complete, click the Info buttons in the Summary pane to learn more about each item.', sourceId: 'diag'),
  AppleStep('A compressed report is saved to /var/tmp, with a filename starting WirelessDiagnostics and ending .tar.gz. Find it via Finder, Go, Go to Folder, then /var/tmp.', sourceId: 'diag'),
];

const String kAppleDiagWindowIntro =
    'With Wireless Diagnostics open, the Window menu exposes the tools pros '
    'actually use:';

const List<DiagUtility> kAppleDiagUtilities = <DiagUtility>[
  DiagUtility('Scan', 'Lists nearby BSSIDs with RSSI, noise, and channel.'),
  DiagUtility('Info', 'Snapshot of the current association.'),
  DiagUtility('Logs', 'Enable detailed Wi-Fi logging.'),
  DiagUtility('Performance', 'Graphs RSSI, noise, and rate live.'),
  DiagUtility('Sniffer', 'Captures a channel to a .pcap.'),
];

// ── Section C — Option-click Wi-Fi menu (links out) ──

const String kAppleOptionClickBody =
    'Holding Option while clicking the Wi-Fi menu-bar icon reveals the RF '
    'detail of the current association inline under the connected SSID: IP '
    'address, router, BSSID, channel, width, band, country code, RSSI, noise, '
    'Tx rate, and PHY mode.';

const String kAppleOptionClickLinkNote =
    'For the field-by-field meaning of every value the Option-click menu shows, '
    'open the companion reference: macOS Menu-Bar Wi-Fi. This screen owns the '
    '"how to open / Apple guidance" layer; the menu-bar screen owns the "what '
    'each field means" layer.';

// ── Section D — iOS / iPadOS troubleshooting steps ──

const String kAppleIosIntro =
    "Apple's canonical iPhone and iPad Wi-Fi troubleshooting steps, in order.";

const List<AppleStep> kAppleIosSteps = <AppleStep>[
  AppleStep('Open the Settings app, tap Wi-Fi, and turn on Wi-Fi if necessary.', sourceId: 'ios'),
  AppleStep('Confirm you are connected: look for a blue checkmark next to the network.', sourceId: 'ios'),
  AppleStep('Make sure Airplane Mode is off.', sourceId: 'ios'),
  AppleStep('In Cellular settings, make sure Wi-Fi Assist is off.', sourceId: 'ios'),
  AppleStep('If the Wi-Fi setting is dimmed (grayed out), restart the device.', sourceId: 'ios'),
  AppleStep('Confirm the router is powered on and in range; check whether other devices connect.', sourceId: 'ios'),
  AppleStep('Make sure the router has the latest firmware.', sourceId: 'ios'),
  AppleStep('If the router supports separate frequencies, try joining another frequency, for example 5 GHz instead of 2.4 GHz.', sourceId: 'ios'),
  AppleStep('Restart your router and cable modem by unplugging the devices and then plugging them back in.', sourceId: 'ios'),
  AppleStep('Last resort: Settings, General, Transfer or Reset, Reset Network Settings (clears all saved Wi-Fi networks, passwords, cellular, VPN, and APN settings).', sourceId: 'ios'),
];

/// Single-source honesty flag carried on-screen (GL-005).
const String kAppleIosSingleSourceNote =
    'Every iOS step traces to one Apple article (111786). It is the publisher '
    'primary documentation, not two independent sources agreeing.';
