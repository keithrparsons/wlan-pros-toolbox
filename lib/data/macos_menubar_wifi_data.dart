// macOS Menu-Bar Wi-Fi Tools — data for the data-driven reference screen.
//
// Source of truth: Deliverables/2026-06-12-toolbox-tier1-references/
// macos-menubar-wifi/DATA.md. This screen OWNS the per-field RF reference (what
// each value means); the Apple Wi-Fi Tips screen links here for that detail
// (per the SSOT note in the DATA file). Verified live 2026-06-12.
//
// Standing Keith decision: the airport CLI is removed on current macOS and is
// NOT documented as usable. The wdutil sudo-masking callout is carried as a real
// on-screen note.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" / "802.11" casing.

/// One of the four built-in paths a Mac exposes for RF data.
class MenuBarPath {
  const MenuBarPath(this.path, this.what, this.detail, this.needsSudo);

  /// The path name (e.g. "Option-click Wi-Fi menu").
  final String path;

  /// What it is.
  final String what;

  /// The detail level it gives you.
  final String detail;

  /// Whether sudo is needed for full RF.
  final String needsSudo;
}

/// One RF field with its meaning and why a Wi-Fi pro cares. Used by the
/// Option-click menu table (Section A) and the wdutil Wi-Fi block (Section B).
class RfField {
  const RfField(this.field, this.meaning, {this.proNote});

  /// The field name as macOS / wdutil prints it.
  final String field;

  /// What the field means.
  final String meaning;

  /// Optional "why a pro cares" note.
  final String? proNote;
}

/// One Wireless Diagnostics Window-menu utility (Section C).
class WdUtility {
  const WdUtility(this.name, this.what);

  final String name;
  final String what;
}

// ── The four built-in paths ──

const String kMenuBarIntro =
    'A stock Mac already exposes most of the RF data a Wi-Fi pro needs, with no '
    'third-party app installed. These are the four built-in paths and what each '
    'one gives you.';

const List<MenuBarPath> kMenuBarPaths = <MenuBarPath>[
  MenuBarPath('Option-click Wi-Fi menu',
      'Hold Option, click the Wi-Fi menu-bar icon',
      'Live RF of the current association, inline', 'No'),
  MenuBarPath('wdutil info', 'Apple supported Wireless Diagnostics CLI',
      'Full Wi-Fi block plus network / BT / power', 'Yes, for unmasked RF'),
  MenuBarPath('Wireless Diagnostics app',
      'Option-click menu, then Open Wireless Diagnostics',
      'Scan, Performance graphs, Sniffer, Logs', 'Admin for some panes'),
  MenuBarPath('Shortcuts "Get Network Details"',
      'Shortcuts action, also on iOS', 'RF fields apps cannot otherwise read',
      'No'),
];

// ── Section A — Option-click Wi-Fi menu fields ──

const String kMenuBarOptionClickIntro =
    'Hold Option and click the Wi-Fi icon. Under the connected SSID, macOS '
    'prints the live association detail.';

const List<RfField> kMenuBarOptionClickFields = <RfField>[
  RfField('IP Address', 'The Mac IPv4 address on this network',
      proNote: 'Confirms DHCP succeeded; spots APIPA (169.254.x.x)'),
  RfField('Router', 'Default-gateway IP',
      proNote: 'Confirms the gateway the Mac is using'),
  RfField('BSSID', 'MAC address of the AP radio you are joined to',
      proNote: 'Identifies which AP/radio you are on; track roaming'),
  RfField('Channel', 'Operating channel + band',
      proNote: 'Confirms band (2.4 / 5 / 6 GHz) and channel plan'),
  RfField('Channel width', '20 / 40 / 80 / 160 MHz',
      proNote: 'Width vs interference trade-off; spec compliance'),
  RfField('Country Code', 'Regulatory domain the AP advertises',
      proNote: 'Wrong code means wrong channels/power allowed'),
  RfField('RSSI', 'Received signal strength, dBm (closer to 0 is stronger)',
      proNote: 'Primary coverage metric'),
  RfField('Noise', 'Noise floor, dBm',
      proNote: 'RSSI minus noise is SNR, the real link-quality number'),
  RfField('Tx Rate', 'Current transmit data rate, Mbps',
      proNote: 'The negotiated PHY rate, not throughput'),
  RfField('PHY Mode', '802.11 generation in use (a/n/ac/ax/be)',
      proNote: 'Confirms the client negotiated the expected standard'),
];

const String kMenuBarOptionClickNote =
    'The exact field set varies slightly by macOS version and adapter. RSSI, '
    'noise, Tx rate, channel, and BSSID are consistently present. For the '
    'complete machine-readable set, use wdutil info below.';

// ── Section B: wdutil Wi-Fi block ──

const String kMenuBarWdutilIntro =
    'wdutil is Apple supported command-line Wireless Diagnostics utility and the '
    'replacement for the retired airport tool. Plain wdutil info works without '
    'sudo, but RF-sensitive fields are masked unless you run sudo wdutil info.';

/// Load-bearing sudo-masks-RF callout (carried on-screen).
const String kMenuBarSudoCallout =
    'Run sudo wdutil info for the real numbers: without sudo, RSSI, noise, MCS, '
    'and BSSID are masked.';

const List<RfField> kMenuBarWdutilFields = <RfField>[
  RfField('MAC Address', 'The Mac Wi-Fi interface own MAC'),
  RfField('Interface Name', 'e.g. en0'),
  RfField('Power', 'Radio on/off'),
  RfField('Op Mode', 'Operating mode (station, etc.)'),
  RfField('SSID', 'Network name joined'),
  RfField('BSSID', 'AP radio MAC (masked without sudo)'),
  RfField('RSSI', 'Signal strength, dBm (masked without sudo)'),
  RfField('CCA', 'Clear-channel-assessment / channel-busy indicator'),
  RfField('Noise', 'Noise floor, dBm'),
  RfField('Tx Rate', 'Negotiated transmit rate, Mbps'),
  RfField('Security', 'Auth/cipher (e.g. WPA3 Personal)'),
  RfField('PHY Mode', '802.11 generation'),
  RfField('MCS Index', 'Modulation-and-coding-scheme index'),
  RfField('Guard Interval', 'Long / short GI'),
  RfField('NSS', 'Number of spatial streams'),
  RfField('Channel', 'Channel + width + band'),
  RfField('Country Code', 'Regulatory domain'),
  RfField('Scan Cache Count', 'Cached scan-result count'),
  RfField('Supports 6e', 'Whether the adapter supports 6 GHz'),
  RfField('Supported Channels', 'Channel list the adapter supports'),
];

const String kMenuBarWdutilNote =
    'wdutil info also prints NETWORK (IPv4/IPv6, DNS, reachability), BLUETOOTH, '
    'AWDL, and POWER sections; the Wi-Fi block above is the RF-relevant one.';

/// The airport-is-gone note (Keith standing decision; carried on-screen).
const String kMenuBarAirportGone =
    'The airport CLI is gone. Apple deprecated it in macOS Sonoma 14.4 and '
    'points to wdutil and Wireless Diagnostics instead. This reference does not '
    'document airport as a working path because on current macOS it is not one.';

// ── Section C — Wireless Diagnostics app (Window menu) ──

const String kMenuBarDiagIntro =
    'Option-click the Wi-Fi menu, then Open Wireless Diagnostics. The app does '
    'not change network settings. The Window menu exposes the pro tools.';

const List<WdUtility> kMenuBarDiagUtilities = <WdUtility>[
  WdUtility('Scan', 'Nearby BSSIDs with RSSI, noise, channel, width, band, PHY mode'),
  WdUtility('Info', 'Snapshot of the current association'),
  WdUtility('Logs', 'Enable detailed Wi-Fi logging'),
  WdUtility('Performance', 'Live graphs of RSSI, noise, and Tx rate over time'),
  WdUtility('Sniffer', 'Capture a chosen channel/width to a .pcap for Wireshark'),
];

const String kMenuBarDiagNote =
    'The summary analysis saves a WirelessDiagnostics .tar.gz report to /var/tmp.';

// ── Section D — Shortcuts "Get Network Details" ──

const String kMenuBarShortcutsBody =
    'The stock Shortcuts action Get Network Details exposes RF fields (including '
    'RSSI, channel, and PHY/Tx-Rx data) that a normal app sandbox cannot read on '
    'iOS, and it also runs on macOS. This is the bridge the Toolbox already uses '
    'for live Wi-Fi info on iOS. Treat it as a complement to wdutil, not a '
    'replacement; the exact field set depends on OS version.';
