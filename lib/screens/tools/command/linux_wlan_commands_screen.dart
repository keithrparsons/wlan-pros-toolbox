// Linux / WLAN Commands — grouped, filterable Linux CLI reference for WLAN work.
//
// File and process basics, the wireless-specific tools (iw, iwconfig, airmon-ng,
// rfkill), tested monitor-mode sequences, and the macOS non-root capture setup.
// Read-only with a free-text filter. Data is the Pax research deliverable
// (pax-research-7-additions.md, "Linux / WLAN Commands"), cross-checked against
// Linux man-pages, iw/nl80211 docs, and aircrack-ng docs.
//
// States (SOP-007 §5):
//  - success → the filtered, grouped command list renders (default; const
//    dataset, no load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card.
// No loading / error / NetworkUnavailableView — fully offline on every platform
// (commands are reference text, never executed; GL-008 does not apply).
//
// Pattern: the reason_codes grouped-searchable idiom — a group is a heading
// over its command rows; filtering drops empty groups; an all-empty result
// yields one "no match" card; a live match-count SR announcement (WCAG 4.1.3).
// The command syntax is the LIME column.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One command: the syntax and what it does. Immutable.
@immutable
class WlanCommand {
  const WlanCommand(this.command, this.description);

  /// The command syntax, e.g. `iw dev wlan0 scan`. LIME column.
  final String command;

  /// What it does.
  final String description;
}

/// A labeled group of commands (File, Wireless, Monitor-mode, etc.).
@immutable
class WlanCommandGroup {
  const WlanCommandGroup(this.label, this.commands);

  final String label;
  final List<WlanCommand> commands;
}

class LinuxWlanCommandsScreen extends StatefulWidget {
  const LinuxWlanCommandsScreen({super.key});

  static const String intro =
      'Linux command line for WLAN work: file and process basics, the '
      'wireless-specific tools (iw, iwconfig, airmon-ng, rfkill), and tested '
      'monitor-mode sequences for capture. Filter by name or group.';

  static const String caveat =
      'iwconfig/iwlist/ifconfig are legacy "wireless extensions" tools; modern '
      'distros prefer iw and the iproute2 suite. Monitor-mode sequences need '
      'sudo and a capable adapter/driver.';

  static const String footnote =
      'Wireless extensions (iwconfig/iwlist) are deprecated in favor of iw + '
      'nl80211; both are shown because field gear still ships the legacy tools. '
      'HT40+/HT40- selects a 40 MHz channel with the secondary 20 MHz channel '
      'above (+) or below (-) the control channel. The access_bpf group lets a '
      'non-root macOS user capture via libpcap (BPF devices).';

  /// The grouped command set, verbatim from the Pax research deliverable.
  /// Public + static so tests can assert known rows without pumping the UI.
  static const List<WlanCommandGroup> groups = <WlanCommandGroup>[
    WlanCommandGroup('File', <WlanCommand>[
      WlanCommand('ls -la', 'List files in long format including hidden files'),
      WlanCommand('cp src dst', 'Copy src to dst'),
      WlanCommand('mv src dst', 'Move or rename src to dst'),
      WlanCommand('rm file', 'Delete file'),
      WlanCommand('cat file', 'Print file contents'),
      WlanCommand('less file', 'View and paginate a file'),
      WlanCommand('tail -f file', 'Follow a file as it grows (live logs)'),
      WlanCommand('grep -i pattern file', 'Case-insensitive search for pattern in file'),
      WlanCommand('find /dir -name name', 'Find files named name under /dir'),
    ]),
    WlanCommandGroup('Directory', <WlanCommand>[
      WlanCommand('pwd', 'Print the current working directory'),
      WlanCommand('cd /path', 'Change directory to /path'),
      WlanCommand('mkdir dir', 'Create directory dir'),
    ]),
    WlanCommandGroup('Process', <WlanCommand>[
      WlanCommand('ps aux', 'Snapshot of all running processes'),
      WlanCommand('top', 'Live process and resource view'),
      WlanCommand('kill pid', 'Terminate the process with the given PID'),
      WlanCommand('killall name', 'Terminate all processes matching name'),
    ]),
    WlanCommandGroup('Network', <WlanCommand>[
      WlanCommand('ip addr', 'Show interface addresses (modern; replaces ifconfig)'),
      WlanCommand('ip route', 'Show the routing table (modern; replaces route)'),
      WlanCommand('ip neigh', 'Show the ARP/neighbor table (replaces arp)'),
      WlanCommand('ifconfig', 'Show interface configuration (legacy)'),
      WlanCommand('ifconfig wlan0', 'Show configuration for interface wlan0'),
      WlanCommand('ifconfig wlan0 up', 'Bring interface wlan0 up'),
      WlanCommand('ifconfig wlan0 down', 'Bring interface wlan0 down'),
      WlanCommand('dig name', 'Query DNS for name'),
      WlanCommand('ping host', 'Test reachability to host via ICMP echo'),
      WlanCommand('ss -tulpn', 'Show listening TCP/UDP sockets with PID (modern netstat)'),
    ]),
    WlanCommandGroup('Wireless', <WlanCommand>[
      WlanCommand('iw dev', 'List wireless interfaces and their config (modern)'),
      WlanCommand('iw dev wlan0 info', 'Show wlan0 type, channel, and mode'),
      WlanCommand('iw dev wlan0 link', 'Show current association: SSID, signal, rate'),
      WlanCommand('iw dev wlan0 scan', 'Scan for nearby BSSs (needs sudo)'),
      WlanCommand('iw dev wlan0 set channel 6', 'Set wlan0 to channel 6'),
      WlanCommand('iw phy', 'Show adapter PHY capabilities (bands, channels, modes)'),
      WlanCommand('iwconfig', 'Show wireless config for all interfaces (legacy)'),
      WlanCommand('iwconfig wlan0', 'Show wireless config for wlan0 (legacy)'),
      WlanCommand('iwlist wlan0 scan', 'Scan for networks on wlan0 (legacy)'),
      WlanCommand('iwlist wlan0 channel', 'List channels supported on wlan0 (legacy)'),
      WlanCommand('rfkill list', 'Show wireless radio block status (Wi-Fi/Bluetooth)'),
      WlanCommand('rfkill unblock wifi', 'Unblock the Wi-Fi radio'),
    ]),
    WlanCommandGroup('Monitor-mode', <WlanCommand>[
      WlanCommand('sudo airmon-ng start wlan0', 'Put wlan0 into monitor mode (creates wlan0mon)'),
      WlanCommand('sudo airmon-ng start wlan0 36', 'Start monitor mode on wlan0 and set channel 36'),
      WlanCommand('sudo airmon-ng stop wlan0mon', 'Stop monitor mode and restore managed mode'),
      WlanCommand('sudo airmon-ng check kill', 'Stop processes (NetworkManager) that interfere with monitor mode'),
      WlanCommand('sudo ifconfig wlan0 down', 'Step 1: bring the interface down before mode change'),
      WlanCommand('sudo iwconfig wlan0 mode monitor', 'Step 2: set wlan0 to monitor mode'),
      WlanCommand('sudo ifconfig wlan0 up', 'Step 3: bring the interface back up'),
      WlanCommand('sudo iw dev wlan0 set channel 36 HT40+', 'Set channel 36 with 40 MHz, secondary channel above'),
      WlanCommand('sudo iw dev wlan0 set channel 40 HT40-', 'Set channel 40 with 40 MHz, secondary channel below'),
      WlanCommand('sudo iwconfig wlan0 mode managed', 'Return wlan0 to managed (normal client) mode'),
      WlanCommand('sudo iw dev wlan0 info', 'Verify current mode and channel'),
      WlanCommand('lsusb', 'List USB devices (confirm a USB Wi-Fi adapter enumerated)'),
      WlanCommand('sudo dmesg', 'Show kernel messages and loaded drivers (adapter debugging)'),
      WlanCommand('sudo ethtool -i wlan0', 'Show the driver bound to wlan0'),
      WlanCommand('lsmod', 'List loaded kernel modules (driver verification)'),
    ]),
    WlanCommandGroup('macOS capture', <WlanCommand>[
      WlanCommand('sudo dseditgroup -o edit -a USERNAME -t user access_bpf', 'Add a user to the access_bpf group for non-root packet capture'),
      WlanCommand('dscl . read /Groups/access_bpf', 'Verify membership of the access_bpf group'),
      WlanCommand('sudo wdutil info', 'macOS 14+: print Wi-Fi link diagnostics'),
    ]),
  ];

  @override
  State<LinuxWlanCommandsScreen> createState() =>
      _LinuxWlanCommandsScreenState();
}

class _LinuxWlanCommandsScreenState extends State<LinuxWlanCommandsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  bool _matches(WlanCommand c, String q) {
    if (q.isEmpty) return true;
    return c.command.toLowerCase().contains(q) ||
        c.description.toLowerCase().contains(q);
  }

  WlanCommandGroup? _filterGroup(WlanCommandGroup g, String q) {
    if (q.isEmpty) return g;
    final List<WlanCommand> kept =
        g.commands.where((WlanCommand c) => _matches(c, q)).toList();
    if (kept.isEmpty) return null;
    // A group label match keeps the whole group, so "wireless" surfaces every
    // command in the Wireless group even though no command text contains it.
    if (g.label.toLowerCase().contains(q)) return g;
    return WlanCommandGroup(g.label, kept);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final WlanCommandGroup g in LinuxWlanCommandsScreen.groups) {
      final WlanCommandGroup? f = _filterGroup(g, q);
      if (f != null) n += f.commands.length;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching commands' : '$n matching command${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux / WLAN Commands'),
        toolbarHeight: 64,
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(
                    toolId: 'linux-wlan-commands',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('linux-wlan-commands'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LinuxWlanCommandsScreen.intro,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            LinuxWlanCommandsScreen.caveat,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Filter',
        hint: 'command or group',
        semanticLabel: 'Filter commands by name or group',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: AppColors.primary,
          decoration: const InputDecoration(
            hintText: 'e.g. iw or monitor',
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final WlanCommandGroup g in LinuxWlanCommandsScreen.groups) {
      final WlanCommandGroup? f = _filterGroup(g, q);
      if (f != null) {
        cards.add(_GroupCard(group: f));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }

    if (cards.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No command matches "${_query.trim()}".',
        ),
      ];
    }

    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      LinuxWlanCommandsScreen.footnote,
      style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One group: a heading over its command rows in a bordered card.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final WlanCommandGroup group;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...group.commands.map(
            (WlanCommand c) => _CommandRow(command: c, mono: mono, text: text),
          ),
        ],
      ),
    );
  }
}

/// One command row: the mono syntax (lime) over its description.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.mono,
    required this.text,
  });

  final WlanCommand command;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${command.command}, ${command.description}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              command.command,
              style: mono.inlineCode.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              command.description,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card — mirrors the reason_codes "no match" surface.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
