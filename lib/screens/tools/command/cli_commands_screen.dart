// Network CLI Commands — cross-platform command-line troubleshooting reference.
//
// Each row is a task: the Windows command on one side, the macOS/Linux
// equivalent on the other, a description, and the field-common flag subset.
// Read-only with a free-text filter (matches by command syntax, description, or
// flag). Data is the Pax research deliverable (pax-research-7-additions.md,
// "Network CLI Commands"), sourced from Linux man-pages, Microsoft Learn, and
// Apple docs. Keith's decision (2026-05-30): macOS shows ONLY `wdutil info`;
// the deprecated `airport` CLI is removed entirely.
//
// States (SOP-007 §5):
//  - success → the filtered command list renders (default; const dataset, no
//    load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card.
// No loading / error / NetworkUnavailableView — fully offline on every platform
// (the commands are reference text, not executed; GL-008 does not apply because
// nothing is fetched and nothing is shelled out to).
//
// Pattern: the reason_codes searchable-reference idiom — StatefulWidget, a
// LabeledField search box, a live match-count SR announcement (WCAG 4.1.3), and
// "no match" empty card. The command syntax is the LIME column. Each command
// renders win/nix as two mono lines plus its flag rows beneath.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" / "802.11" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One command flag: the flag token and what it does. Immutable.
@immutable
class CliOption {
  const CliOption(this.flag, this.meaning);

  /// The flag, e.g. `-t`.
  final String flag;

  /// What the flag does.
  final String meaning;
}

/// One cross-platform command: a Windows syntax, its macOS/Linux equivalent
/// (`null` when there is no native equivalent), a description, and the
/// field-common flag subset.
@immutable
class CliCommand {
  const CliCommand({
    this.winCmd,
    this.nixCmd,
    required this.description,
    this.options = const <CliOption>[],
  });

  /// Windows command syntax, or `null` when there is no native Windows command.
  final String? winCmd;

  /// macOS/Linux equivalent, or `null` when there is no native equivalent.
  final String? nixCmd;

  /// What the command does.
  final String description;

  /// Field-common flags (not exhaustive).
  final List<CliOption> options;
}

class CliCommandsScreen extends StatefulWidget {
  const CliCommandsScreen({super.key});

  static const String intro =
      'Cross-platform command-line network troubleshooting. Windows command on '
      'the left, the macOS/Linux equivalent on the right. Filter by name or '
      'task.';

  static const String caveat =
      'Some commands need administrator/sudo rights. Flags shown are the '
      'field-common subset, not exhaustive.';

  static const String footnote =
      'ifconfig, route, and arp are legacy on Linux; modern distros prefer the '
      'iproute2 suite (ip addr, ip route, ip neigh). On macOS, use wdutil info '
      '(sudo) or the Wireless Diagnostics app for Wi-Fi link details. netsh '
      'wlan is Windows only.';

  /// The command set, verbatim from the Pax research deliverable. Public +
  /// static so tests can assert known rows without pumping the UI.
  static const List<CliCommand> commands = <CliCommand>[
    CliCommand(
      winCmd: 'ping host',
      nixCmd: 'ping host',
      description:
          'Test reachability and round-trip time to a host via ICMP echo',
      options: <CliOption>[
        CliOption('-t', 'Windows: ping continuously until stopped (Ctrl-C)'),
        CliOption('-n count', 'Windows: number of echo requests'),
        CliOption('-l size', 'Windows: payload size in bytes'),
        CliOption('-c count', 'macOS/Linux: number of echo requests'),
        CliOption('-s size', 'macOS/Linux: payload size in bytes'),
        CliOption('-i interval', 'macOS/Linux: seconds between requests'),
      ],
    ),
    CliCommand(
      winCmd: 'tracert host',
      nixCmd: 'traceroute host',
      description: 'Trace the L3 path (per-hop routers) to a host',
      options: <CliOption>[
        CliOption('-d', 'Windows: do not resolve hostnames'),
        CliOption('-h max', 'Windows: max hops (TTL)'),
        CliOption('-n', 'macOS/Linux: do not resolve hostnames'),
        CliOption('-m max', 'macOS/Linux: max hops (TTL)'),
        CliOption('-I', 'macOS/Linux: use ICMP ECHO instead of UDP'),
        CliOption('-T', 'Linux: use TCP SYN probes'),
        CliOption('-P proto', 'macOS: select probe protocol'),
      ],
    ),
    CliCommand(
      winCmd: 'pathping host',
      nixCmd: 'mtr host',
      description:
          'Combine ping + traceroute: per-hop latency and loss over time '
          '(mtr is a common Linux/macOS install)',
      options: <CliOption>[
        CliOption('-n', 'do not resolve hostnames'),
        CliOption('-q num', 'pathping: queries per hop'),
      ],
    ),
    CliCommand(
      winCmd: 'nslookup name',
      nixCmd: 'nslookup name',
      description: 'Query DNS for a name or record (legacy, cross-platform)',
      options: <CliOption>[
        CliOption('-type=MX', 'query a specific record type (A, AAAA, MX, NS, TXT, PTR)'),
        CliOption('server', 'append a server to query a specific resolver'),
      ],
    ),
    CliCommand(
      winCmd: null,
      nixCmd: 'dig name',
      description: 'Query DNS with full detail (preferred on macOS/Linux)',
      options: <CliOption>[
        CliOption('+short', 'concise answer only'),
        CliOption('-x addr', 'reverse lookup (PTR)'),
        CliOption('@server', 'query a specific resolver'),
        CliOption('type', 'append record type, e.g. dig AAAA name'),
      ],
    ),
    CliCommand(
      winCmd: 'ipconfig /all',
      nixCmd: 'ifconfig',
      description:
          'Show interface IP configuration (ifconfig legacy; ip addr '
          'preferred on modern Linux)',
      options: <CliOption>[
        CliOption('/all', 'Windows: full config incl. DNS, MAC, DHCP'),
        CliOption('/release', 'Windows: release DHCP lease'),
        CliOption('/renew', 'Windows: renew DHCP lease'),
        CliOption('/flushdns', 'Windows: clear DNS resolver cache'),
        CliOption('ip addr', 'modern Linux equivalent of ifconfig'),
        CliOption('ipconfig getifaddr en0', 'macOS: print IP of an interface'),
      ],
    ),
    CliCommand(
      winCmd: 'netstat -ano',
      nixCmd: 'netstat -an',
      description:
          'Show active connections, listening ports, and (Windows) owning PID',
      options: <CliOption>[
        CliOption('-a', 'all connections and listening ports'),
        CliOption('-n', 'numeric addresses/ports (no resolution)'),
        CliOption('-o', 'Windows: show owning process ID'),
        CliOption('-r', 'show the routing table'),
        CliOption('-p proto', 'filter by protocol; Linux: -p shows PID/program'),
      ],
    ),
    CliCommand(
      winCmd: 'arp -a',
      nixCmd: 'arp -a',
      description: 'Show the ARP cache (IP-to-MAC mappings on the local segment)',
      options: <CliOption>[
        CliOption('-a', 'display all entries'),
        CliOption('-d addr', 'delete an entry'),
        CliOption('-s addr mac', 'add a static entry'),
      ],
    ),
    CliCommand(
      winCmd: 'hostname',
      nixCmd: 'hostname',
      description: 'Print the device hostname',
      options: <CliOption>[
        CliOption('-f', 'macOS/Linux: fully qualified domain name'),
      ],
    ),
    CliCommand(
      winCmd: 'route print',
      nixCmd: 'netstat -rn',
      description: 'Show the IP routing table',
      options: <CliOption>[
        CliOption('print', 'Windows: display the routing table'),
        CliOption('-rn', 'macOS/Linux: numeric routing table'),
        CliOption('ip route', 'modern Linux equivalent'),
      ],
    ),
    CliCommand(
      winCmd: 'nbtstat -A addr',
      nixCmd: null,
      description: 'Windows: show NetBIOS-over-TCP name table for a host',
      options: <CliOption>[
        CliOption('-A addr', 'names by IP address'),
        CliOption('-n', 'local names'),
      ],
    ),
    CliCommand(
      winCmd: 'netsh wlan show interfaces',
      nixCmd: 'wdutil info',
      description:
          'Show the connected Wi-Fi interface state: SSID, BSSID, channel, '
          'RSSI, PHY rate',
      options: <CliOption>[
        CliOption('show interfaces', 'Windows: current Wi-Fi link details'),
        CliOption('show profiles', 'Windows: stored Wi-Fi profiles'),
        CliOption('show networks mode=bssid', 'Windows: scan visible BSSIDs + signal'),
        CliOption('show wlanreport', 'Windows: generate 3-day Wi-Fi HTML report'),
        CliOption('show drivers', 'Windows: adapter capabilities'),
        CliOption('wdutil info', 'macOS: Wi-Fi diagnostics (sudo)'),
      ],
    ),
  ];

  @override
  State<CliCommandsScreen> createState() => _CliCommandsScreenState();
}

class _CliCommandsScreenState extends State<CliCommandsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  bool _matches(CliCommand c, String q) {
    if (q.isEmpty) return true;
    if ((c.winCmd ?? '').toLowerCase().contains(q)) return true;
    if ((c.nixCmd ?? '').toLowerCase().contains(q)) return true;
    if (c.description.toLowerCase().contains(q)) return true;
    return c.options.any((CliOption o) =>
        o.flag.toLowerCase().contains(q) ||
        o.meaning.toLowerCase().contains(q));
  }

  List<CliCommand> _filtered(String q) {
    if (q.isEmpty) return CliCommandsScreen.commands;
    return CliCommandsScreen.commands
        .where((CliCommand c) => _matches(c, q))
        .toList();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final int n = _filtered(value.trim().toLowerCase()).length;
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
        title: const Text('Network CLI Commands'),
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
                    toolId: 'cli-commands',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('cli-commands'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                  ToolHelpFooter(toolId: 'cli-commands'),
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
            CliCommandsScreen.intro,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CliCommandsScreen.caveat,
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
        hint: 'command or task',
        semanticLabel: 'Filter commands by name or task',
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
            hintText: 'e.g. ping or DNS',
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();
    final List<CliCommand> matches = _filtered(q);

    if (matches.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No command matches "${_query.trim()}".',
        ),
      ];
    }

    final List<Widget> cards = <Widget>[];
    for (final CliCommand c in matches) {
      cards.add(_CommandCard(command: c));
      cards.add(const SizedBox(height: AppSpacing.sm));
    }
    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      CliCommandsScreen.footnote,
      style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One command: a Windows / macOS-Linux pair, a description, and flag rows.
class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.command});

  final CliCommand command;

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
          _PlatformLine(
            label: 'Windows',
            command: command.winCmd,
            isLime: true,
            mono: mono,
            text: text,
          ),
          const SizedBox(height: 2),
          _PlatformLine(
            label: 'macOS / Linux',
            command: command.nixCmd,
            isLime: false,
            mono: mono,
            text: text,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            command.description,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          if (command.options.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            ...command.options.map(
              (CliOption o) => _OptionRow(option: o, mono: mono, text: text),
            ),
          ],
        ],
      ),
    );
  }
}

/// One platform line: a short label gutter plus the mono command. A `null`
/// command renders an honest "(no native command)" rather than a blank line.
class _PlatformLine extends StatelessWidget {
  const _PlatformLine({
    required this.label,
    required this.command,
    required this.isLime,
    required this.mono,
    required this.text,
  });

  final String label;
  final String? command;
  final bool isLime;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final bool present = command != null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: present ? '$label, $command' : '$label, no native command',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: present
                ? SelectableText(
                    command!,
                    style: mono.inlineCode.copyWith(
                      color: isLime
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Text(
                    '(no native command)',
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One flag row: the flag in a mono gutter, the meaning beside it.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.mono,
    required this.text,
  });

  final CliOption option;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${option.flag}, ${option.meaning}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 152,
              child: Text(
                option.flag,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                option.meaning,
                style: text.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card — mirrors the reason_codes / port_reference "no match".
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
