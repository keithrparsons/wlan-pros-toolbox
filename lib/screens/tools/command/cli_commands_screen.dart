// Network CLI Commands — cross-platform command-line troubleshooting reference.
//
// Each row is a task with the equivalent command for Windows, macOS, and Linux
// shown in THREE columns. The 3-column split (2026-06-12, Silas flag): macOS and
// Linux have diverged enough — `ifconfig` vs `ip`, `netstat` vs `ss`, DHCP renew,
// flush DNS — that folding them into one "macOS/Linux" column would ship a wrong
// command on one of the two platforms. Where macOS and Linux are identical the
// same value is repeated in both columns (honest, copy-paste-correct), never
// collapsed. WLAN-relevant tasks lead. A Linux-only "shell essentials" group
// (capture-rig / WLAN Pi context) renders separately at the end.
//
// Read-only with a free-text filter (matches command syntax, description, or
// flag). Data consolidated from Keith's Network CLI sheet + the WLAN Pros Linux
// cheat sheets, reconciled against current Windows/macOS/Linux docs
// (Deliverables/2026-06-12-toolbox-tier1-references/cli-commands-by-os/DATA.md).
// Keith's decision (2026-05-30) holds: macOS Wi-Fi = `wdutil info` only; the
// deprecated `airport` CLI is removed entirely. Legacy Linux forms (`ifconfig`,
// `iwconfig`, `netstat`) are noted alongside the current `ip`/`iw`/`ss` form.
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
// LabeledField search box, a live match-count SR announcement (WCAG 4.1.3), an
// AppBar §8.16 copy action, and a "no match" empty card. The command syntax is
// the LIME column. Each command renders its three OS lines plus its flag rows.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" / "802.11" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
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

/// One cross-platform command: the Windows, macOS, and Linux syntax (any of the
/// three `null` when there is no native command on that platform), a
/// description, and the field-common flag subset. The 3-column model: macOS and
/// Linux are separate fields because they have diverged on several tasks; where
/// they are identical the same string appears in both, never collapsed.
@immutable
class CliCommand {
  const CliCommand({
    this.winCmd,
    this.macCmd,
    this.linCmd,
    required this.description,
    this.options = const <CliOption>[],
  });

  /// Windows command syntax, or `null` when there is no native Windows command.
  final String? winCmd;

  /// macOS command syntax, or `null` when there is no native macOS command.
  final String? macCmd;

  /// Linux command syntax, or `null` when there is no native Linux command.
  final String? linCmd;

  /// What the command does.
  final String description;

  /// Field-common flags (not exhaustive).
  final List<CliOption> options;
}

/// One Linux-only shell command: the syntax and a one-line note. Used by the
/// trailing "Linux shell essentials" group (capture-rig / WLAN Pi context),
/// which has no Windows or macOS column.
@immutable
class LinuxShellCommand {
  const LinuxShellCommand(this.command, this.note);

  /// The Linux command syntax. LIME column.
  final String command;

  /// A short note (flags, variants).
  final String note;
}

class CliCommandsScreen extends StatefulWidget {
  const CliCommandsScreen({super.key});

  static const String intro =
      'Cross-platform command-line network troubleshooting. Each task shows the '
      'Windows, macOS, and Linux command side by side. Filter by name or task.';

  static const String caveat =
      'Some commands need administrator/sudo rights. Flags shown are the '
      'field-common subset, not exhaustive. Replace placeholder hosts, '
      'interfaces (en0/wlan0), and addresses with real values.';

  static const String footnote =
      'On Linux, ifconfig, route, arp, iwconfig, and netstat are legacy '
      '(net-tools); modern distros prefer iproute2 (ip addr, ip route, ip neigh) '
      ', iw, and ss. On macOS, use wdutil info (sudo) or the Wireless '
      'Diagnostics app for Wi-Fi link details. netsh wlan is Windows only.';

  /// The cross-platform command set. Public + static so tests can assert known
  /// rows without pumping the UI. WLAN-relevant tasks lead, then core IP, DNS,
  /// and connectivity/transfer utilities.
  static const List<CliCommand> commands = <CliCommand>[
    // ── A. Wi-Fi / WLAN-relevant (lead) ──
    CliCommand(
      winCmd: 'netsh wlan show interfaces',
      macCmd: 'wdutil info',
      linCmd: 'iw dev wlan0 link',
      description:
          'Show the connected Wi-Fi interface state: SSID, BSSID, channel, '
          'RSSI, PHY rate (macOS wdutil needs sudo for full RF; Linux iw is '
          'current, iwconfig is legacy)',
      options: <CliOption>[
        CliOption('show interfaces', 'Windows: current Wi-Fi link details'),
        CliOption('sudo wdutil info', 'macOS: unmasked RF (RSSI/noise/MCS)'),
        CliOption('iw dev wlan0 link', 'Linux: current association detail'),
      ],
    ),
    CliCommand(
      winCmd: 'netsh wlan show networks mode=bssid',
      macCmd: 'wdutil info',
      linCmd: 'sudo iw dev wlan0 scan',
      description:
          'List visible Wi-Fi networks (scan). macOS removed the airport CLI '
          'scan with no stock replacement; on NetworkManager distros use '
          'nmcli dev wifi list',
      options: <CliOption>[
        CliOption('mode=bssid', 'Windows: list each BSSID + signal'),
        CliOption('nmcli dev wifi list', 'Linux (NetworkManager): scan list'),
      ],
    ),
    CliCommand(
      winCmd: 'netsh wlan show profiles',
      macCmd: null,
      linCmd: 'nmcli connection show',
      description:
          'Show saved Wi-Fi profiles. macOS stores them in Keychain/plist with '
          'no stock per-profile CLI',
    ),
    CliCommand(
      winCmd: 'netsh wlan show profile name="SSID" key=clear',
      macCmd: null,
      linCmd: 'nmcli -s connection show "SSID"',
      description:
          'Show the plaintext key for a saved profile. Sensitive output; use '
          'on your own networks only',
    ),
    CliCommand(
      winCmd: 'netsh wlan show drivers',
      macCmd: 'system_profiler SPAirPortDataType',
      linCmd: 'iw phy',
      description: 'Show adapter driver / radio capabilities',
      options: <CliOption>[
        CliOption('show wirelesscapabilities', 'Windows: detailed capabilities'),
      ],
    ),
    CliCommand(
      winCmd: 'netsh wlan show wlanreport',
      macCmd: 'sysdiagnose',
      linCmd: 'journalctl -u NetworkManager',
      description:
          'Generate a Wi-Fi diagnostics report. Windows report lands in '
          'C:\\ProgramData\\Microsoft\\Windows\\WlanReport. On macOS, the '
          'Wireless Diagnostics app saves a report to /var/tmp',
    ),
    CliCommand(
      winCmd: null,
      macCmd: null,
      linCmd: 'sudo iw dev wlan0 set channel 36 HT40+',
      description:
          'Set / change the Wi-Fi channel on a monitor-mode adapter '
          '(capture-rig task). Legacy form iwconfig wlan0 channel 6',
    ),
    CliCommand(
      winCmd: null,
      macCmd: null,
      linCmd: 'sudo airmon-ng start wlan0',
      description:
          'Put the adapter into monitor mode (Aircrack-ng; capture-rig task). '
          'Modern alt: iw dev wlan0 set type monitor',
    ),
    CliCommand(
      winCmd: 'netsh interface set interface "Wi-Fi" enable',
      macCmd: 'sudo ifconfig en0 up',
      linCmd: 'sudo ip link set wlan0 up',
      description:
          'Bring an interface up or down. macOS keeps BSD ifconfig; on Linux '
          'ifconfig is legacy and ip link is current',
      options: <CliOption>[
        CliOption('down', 'replace up with down to disable the interface'),
      ],
    ),
    // ── B. Core IP networking (cross-OS) ──
    CliCommand(
      winCmd: 'ping host',
      macCmd: 'ping host',
      linCmd: 'ping host',
      description:
          'Test reachability and round-trip time to a host via ICMP echo. '
          'Windows sends 4 by default; macOS/Linux ping continuously (Ctrl-C)',
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
      macCmd: 'traceroute host',
      linCmd: 'traceroute host',
      description:
          'Trace the L3 path (per-hop routers) to a host. Windows uses ICMP by '
          'default; macOS/Linux use UDP by default',
      options: <CliOption>[
        CliOption('-d', 'Windows: do not resolve hostnames'),
        CliOption('-h max', 'Windows: max hops (TTL)'),
        CliOption('-n', 'macOS/Linux: do not resolve hostnames'),
        CliOption('-m max', 'macOS/Linux: max hops (TTL)'),
        CliOption('-I', 'macOS/Linux: use ICMP ECHO instead of UDP'),
        CliOption('-T', 'Linux: use TCP SYN probes'),
      ],
    ),
    CliCommand(
      winCmd: 'pathping host',
      macCmd: 'mtr host',
      linCmd: 'mtr host',
      description:
          'Combine ping + traceroute: per-hop latency and loss over time. mtr '
          'is a common install (brew install mtr / apt install mtr)',
      options: <CliOption>[
        CliOption('-n', 'do not resolve hostnames'),
        CliOption('-q num', 'pathping: queries per hop'),
      ],
    ),
    CliCommand(
      winCmd: 'ipconfig /all',
      macCmd: 'ifconfig',
      linCmd: 'ip addr',
      description:
          'Show interface IP configuration. macOS keeps BSD ifconfig; on Linux '
          'ifconfig is legacy and ip addr is current',
      options: <CliOption>[
        CliOption('/all', 'Windows: full config incl. DNS, MAC, DHCP'),
        CliOption('ipconfig getifaddr en0', 'macOS: print IP of an interface'),
      ],
    ),
    CliCommand(
      winCmd: 'ipconfig /renew',
      macCmd: 'sudo ipconfig set en0 DHCP',
      linCmd: 'sudo dhclient -r && sudo dhclient',
      description:
          'Renew the DHCP lease. NetworkManager alt: nmcli con up <name>',
    ),
    CliCommand(
      winCmd: 'ipconfig /release',
      macCmd: 'sudo ipconfig set en0 NONE',
      linCmd: 'sudo dhclient -r',
      description: 'Release the DHCP lease',
    ),
    CliCommand(
      winCmd: 'ipconfig /flushdns',
      macCmd: 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder',
      linCmd: 'sudo resolvectl flush-caches',
      description:
          'Flush the DNS resolver cache. Linux varies by resolver '
          '(systemd-resolved shown)',
    ),
    CliCommand(
      winCmd: 'ipconfig /displaydns',
      macCmd: null,
      linCmd: null,
      description:
          'Show the DNS resolver cache. Windows-only; macOS/Linux have no '
          'stock equivalent',
    ),
    CliCommand(
      winCmd: 'route print',
      macCmd: 'netstat -rn',
      linCmd: 'ip route',
      description:
          'Show the IP routing table. macOS uses netstat -rn; on Linux the '
          'current form is ip route (netstat -rn still works)',
    ),
    CliCommand(
      winCmd: 'arp -a',
      macCmd: 'arp -a',
      linCmd: 'ip neigh',
      description:
          'Show the ARP cache (IP-to-MAC on the local segment). Linux current '
          'form is ip neigh; arp -a is legacy but works',
      options: <CliOption>[
        CliOption('-a', 'display all entries (Windows/macOS)'),
        CliOption('-d addr', 'delete an entry'),
      ],
    ),
    CliCommand(
      winCmd: 'netstat -ano',
      macCmd: 'netstat -an',
      linCmd: 'ss -tunap',
      description:
          'Show active connections and listening ports. Linux current form is '
          'ss (net-tools netstat is legacy)',
      options: <CliOption>[
        CliOption('-a', 'all connections and listening ports'),
        CliOption('-n', 'numeric addresses/ports (no resolution)'),
        CliOption('-o', 'Windows: show owning process ID'),
        CliOption('-p', 'Linux (ss): show owning PID/process'),
        CliOption('lsof -i', 'macOS: list sockets by process'),
      ],
    ),
    CliCommand(
      winCmd: 'hostname',
      macCmd: 'hostname',
      linCmd: 'hostname',
      description: 'Print the device hostname',
      options: <CliOption>[
        CliOption('-f', 'macOS/Linux: fully qualified domain name'),
      ],
    ),
    CliCommand(
      winCmd: 'nbtstat -A addr',
      macCmd: null,
      linCmd: null,
      description:
          'Show the NetBIOS-over-TCP name table for a host. Windows-only',
      options: <CliOption>[
        CliOption('-A addr', 'names by IP address'),
        CliOption('-n', 'local names'),
      ],
    ),
    // ── C. DNS lookups ──
    CliCommand(
      winCmd: 'nslookup name',
      macCmd: 'nslookup name',
      linCmd: 'nslookup name',
      description:
          'Quick DNS name resolution (cross-platform). Append a server to '
          'query a specific resolver: nslookup name dns_server',
      options: <CliOption>[
        CliOption('-type=MX', 'query a record type (A, AAAA, MX, NS, TXT, PTR)'),
        CliOption('server', 'append a server to query a specific resolver'),
      ],
    ),
    CliCommand(
      winCmd: null,
      macCmd: 'dig name',
      linCmd: 'dig name',
      description:
          'Query DNS with full detail. macOS/Linux ship dig stock; Windows has '
          'no native dig (use nslookup or PowerShell Resolve-DnsName)',
      options: <CliOption>[
        CliOption('-x addr', 'reverse lookup (PTR)'),
        CliOption('-t TYPE name', 'query a record type'),
        CliOption('@server', 'query a specific resolver'),
        CliOption('+trace', 'full delegation walk from the root'),
      ],
    ),
    CliCommand(
      winCmd: 'nslookup addr',
      macCmd: 'dig -x addr',
      linCmd: 'dig -x addr',
      description: 'Reverse DNS (PTR): resolve an IP back to a name',
    ),
    CliCommand(
      winCmd: null,
      macCmd: 'whois domain',
      linCmd: 'whois domain',
      description:
          'WHOIS registration lookup. Windows has no stock whois (use online '
          'or install one)',
    ),
    // ── D. Connectivity / transfer utilities ──
    CliCommand(
      winCmd: 'telnet host port',
      macCmd: 'nc -vz host port',
      linCmd: 'nc -vz host port',
      description:
          'Test a TCP port. The telnet client is off by default on modern '
          'Windows; nc (netcat) is the portable test. Common ports: ssh 22, '
          'dns 53, http 80, https 443',
    ),
    CliCommand(
      winCmd: 'ssh user@host',
      macCmd: 'ssh user@host',
      linCmd: 'ssh user@host',
      description:
          'SSH to a host. ssh -p PORT for a non-default port; ssh-copy-id '
          'user@host installs a key for passwordless login',
      options: <CliOption>[
        CliOption('-p PORT', 'connect to a non-default SSH port'),
      ],
    ),
    CliCommand(
      winCmd: 'scp file user@host:/dir',
      macCmd: 'scp file user@host:/dir',
      linCmd: 'scp file user@host:/dir',
      description: 'Copy a file to a remote host over SSH',
    ),
    CliCommand(
      winCmd: 'curl -O url',
      macCmd: 'curl -O url',
      linCmd: 'wget url',
      description:
          'Download a file. curl -O ships on all three; Linux also has wget. '
          'wget -c url resumes a stopped download',
    ),
    // ── E. Capture, scan & throughput tools (installed, cross-platform) ──
    // Not built into any OS; install via brew / apt / choco (or the Wireshark
    // installer for tshark). The base command is the same on macOS and Linux;
    // Windows availability is per-tool. Each carries 1-2 example invocations.
    CliCommand(
      winCmd: 'nmap host',
      macCmd: 'nmap host',
      linCmd: 'nmap host',
      description:
          'Scan hosts and ports: host discovery, open ports, and service / '
          'version detection. Install: brew / apt / choco install nmap',
      options: <CliOption>[
        CliOption('nmap -sn 192.168.1.0/24',
            'Ping-sweep a subnet to list live hosts (no port scan)'),
        CliOption('nmap -sV -p 1-1000 host',
            'Scan ports 1-1000 and probe each service and version'),
      ],
    ),
    CliCommand(
      winCmd: 'iperf3 -c host',
      macCmd: 'iperf3 -c host',
      linCmd: 'iperf3 -c host',
      description:
          'Measure TCP / UDP throughput between two endpoints: run a server on '
          'one side, a client on the other. Install: brew / apt / choco install '
          'iperf3',
      options: <CliOption>[
        CliOption('iperf3 -s', 'Run as a server, listening for throughput tests'),
        CliOption('iperf3 -c host -u -b 100M',
            'Client: UDP test to host at 100 Mbit/s'),
      ],
    ),
    CliCommand(
      winCmd: null,
      macCmd: 'sudo tcpdump -i en0',
      linCmd: 'sudo tcpdump -i wlan0',
      description:
          'Capture and print packets from an interface (CLI packet capture). '
          'Windows has no native tcpdump; use tshark / dumpcap or WinDump',
      options: <CliOption>[
        CliOption('sudo tcpdump -i en0 -n port 53',
            'Capture DNS traffic on en0 without name resolution'),
        CliOption('sudo tcpdump -i wlan0 -w cap.pcap',
            'Write a capture to a pcap file for later analysis'),
      ],
    ),
    CliCommand(
      winCmd: 'tshark -i 1',
      macCmd: 'tshark -i en0',
      linCmd: 'tshark -i wlan0',
      description:
          'Terminal Wireshark: capture with BPF filters or read a pcap and '
          'apply display filters. Ships with the Wireshark install',
      options: <CliOption>[
        CliOption('tshark -i en0 -f "tcp port 443"',
            'Capture live with a BPF capture filter'),
        CliOption('tshark -r cap.pcap -Y "http.request"',
            'Read a pcap and apply a Wireshark display filter'),
      ],
    ),
  ];

  /// Linux-only shell essentials (capture-rig / WLAN Pi context). Rendered as a
  /// separate group because they have no Windows/macOS column. Public + static
  /// for tests.
  static const List<LinuxShellCommand> linuxShell = <LinuxShellCommand>[
    LinuxShellCommand('ls -lah',
        '-a all, -l long, -h human sizes, -t by mtime, -S by size, -r reverse'),
    LinuxShellCommand('pwd', 'print the current working directory'),
    LinuxShellCommand('cd dir', 'change directory; cd .. up, cd ~ home'),
    LinuxShellCommand('mkdir dir', 'make a directory'),
    LinuxShellCommand('tail -f file', 'follow a log file as it grows'),
    LinuxShellCommand('grep -i pattern file',
        '-i case-insensitive, -r recursive, -v invert match'),
    LinuxShellCommand('command | grep pattern', 'filter command output (pipe)'),
    LinuxShellCommand('find /dir -name "name*"',
        'find files by name; also -user, -mmin'),
    LinuxShellCommand('df -h', 'disk usage, human-readable'),
    LinuxShellCommand('du -sh dir', 'total size of a directory'),
    LinuxShellCommand('uname -a',
        'system + kernel; head -n1 /etc/issue shows the distro'),
    LinuxShellCommand('uptime', 'how long the system has been running'),
    LinuxShellCommand('ps aux', 'snapshot of running processes'),
    LinuxShellCommand('top', 'live process monitor; htop if installed'),
    LinuxShellCommand('kill PID', 'kill a process; pkill name / killall name'),
    LinuxShellCommand('sudo command', 'run a command with root privilege'),
    LinuxShellCommand('screen',
        'persistent session that survives SSH disconnect; screen -r resumes; '
        'tmux is the modern alternative'),
    LinuxShellCommand('chmod 755 file',
        'change permissions; 4=r 2=w 1=x for owner/group/other'),
    LinuxShellCommand('chown user:group file', 'change file owner and group'),
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
    if ((c.macCmd ?? '').toLowerCase().contains(q)) return true;
    if ((c.linCmd ?? '').toLowerCase().contains(q)) return true;
    if (c.description.toLowerCase().contains(q)) return true;
    return c.options.any((CliOption o) =>
        o.flag.toLowerCase().contains(q) ||
        o.meaning.toLowerCase().contains(q));
  }

  bool _matchesLinux(LinuxShellCommand c, String q) {
    if (q.isEmpty) return true;
    return c.command.toLowerCase().contains(q) ||
        c.note.toLowerCase().contains(q);
  }

  List<CliCommand> _filtered(String q) {
    if (q.isEmpty) return CliCommandsScreen.commands;
    return CliCommandsScreen.commands
        .where((CliCommand c) => _matches(c, q))
        .toList();
  }

  List<LinuxShellCommand> _filteredLinux(String q) {
    if (q.isEmpty) return CliCommandsScreen.linuxShell;
    return CliCommandsScreen.linuxShell
        .where((LinuxShellCommand c) => _matchesLinux(c, q))
        .toList();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final String q = value.trim().toLowerCase();
    final int n = _filtered(q).length + _filteredLinux(q).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching commands' : '$n matching command${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload — every task with its three OS commands and flags,
  /// then the Linux-only shell essentials, so nothing on-screen survives only as
  /// layout or color.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Network CLI Commands')
      ..writeln()
      ..writeln(
        <String>['Task', 'Windows', 'macOS', 'Linux'].join(tab),
      );
    for (final CliCommand c in CliCommandsScreen.commands) {
      b.writeln(
        <String>[
          c.description,
          c.winCmd ?? '(no native command)',
          c.macCmd ?? '(no native command)',
          c.linCmd ?? '(no native command)',
        ].join(tab),
      );
      for (final CliOption o in c.options) {
        b.writeln('  ${o.flag}: ${o.meaning}');
      }
    }
    b
      ..writeln()
      ..writeln('Linux shell essentials (capture-rig / WLAN Pi):');
    for (final LinuxShellCommand c in CliCommandsScreen.linuxShell) {
      b.writeln('  ${c.command}: ${c.note}');
    }
    b
      ..writeln()
      ..writeln(CliCommandsScreen.footnote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network CLI Commands'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CliCommandsScreen.intro,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CliCommandsScreen.caveat,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
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
          cursorColor: colors.textAccent,
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
    final List<LinuxShellCommand> linuxMatches = _filteredLinux(q);

    if (matches.isEmpty && linuxMatches.isEmpty) {
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
    if (linuxMatches.isNotEmpty) {
      cards.add(_LinuxShellCard(commands: linuxMatches));
      cards.add(const SizedBox(height: AppSpacing.sm));
    }
    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      CliCommandsScreen.footnote,
      style: text.labelSmall?.copyWith(color: colors.textTertiary),
    );
  }
}

/// One command: the three OS lines, a description, and flag rows.
class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.command});

  final CliCommand command;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            command.description,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PlatformLine(
            label: 'Windows',
            command: command.winCmd,
            isLime: true,
            mono: mono,
            text: text,
          ),
          const SizedBox(height: 2),
          _PlatformLine(
            label: 'macOS',
            command: command.macCmd,
            isLime: false,
            mono: mono,
            text: text,
          ),
          const SizedBox(height: 2),
          _PlatformLine(
            label: 'Linux',
            command: command.linCmd,
            isLime: false,
            mono: mono,
            text: text,
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
    final AppColorScheme colors = context.colors;
    final bool present = command != null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: present ? '$label, $command' : '$label, no native command',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(
                color: colors.textTertiary,
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
                          ? colors.textAccent
                          : colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Text(
                    '(no native command)',
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
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
    final AppColorScheme colors = context.colors;
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
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                option.meaning,
                style: text.labelSmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Linux-only shell-essentials group: a heading over single-command rows.
class _LinuxShellCard extends StatelessWidget {
  const _LinuxShellCard({required this.commands});

  final List<LinuxShellCommand> commands;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Linux shell essentials (capture-rig / WLAN Pi)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...commands.map(
            (LinuxShellCommand c) => Semantics(
              container: true,
              excludeSemantics: true,
              label: '${c.command}, ${c.note}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      c.command,
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.note,
                      style: text.labelSmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
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
