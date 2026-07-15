// Find the Switch and Port (LLDP/CDP) - a how-to REFERENCE screen.
//
// Read LLDP (IEEE 802.1AB) or CDP and a switch announces its own name, the exact
// port you are plugged into, its management IP, and often the VLAN. This screen
// teaches how to read that frame on every OS and how to find which switch port an
// access point is on. The app does NOT capture the frames: it runs no shell and
// sniffs nothing (GL-008). It points the user at the tools already on the machine
// in front of them and shows the exact commands to run there.
//
// Content of record: the fact-checked reference content (six sections). Command strings:
// the verified command reference - used verbatim, never any others. Two verification rules are
// honored here:
//  1. Windows pktmon filters use the NUMERIC form `--ethertype 0x88CC`, never the
//     build-specific `-d LLDP` keyword (UNVERIFIED / not in Microsoft's documented
//     value set). The CDP MAC delimiter (hyphen vs colon) is flagged as
//     interchangeable, not asserted as one true form.
//  2. Interface names (`en5`, `eth0`) are PLACEHOLDERS, presented as such, never as
//     literals. The macOS LLDP one-liner is shown as syntax-valid (manpage +
//     multi-source), not as a fresh live run.
//
// States (SOP-007 §5):
//  - success → the full reference renders (default; const content, no load step).
// There is no loading / empty / error / NetworkUnavailableView: nothing is fetched
// and nothing is executed, so the screen is fully offline on every platform and
// GL-008 does not apply (no network or OS-data code at all).
//
// Pattern: the FreeRADIUS-on-WLAN-Pi prose-reference idiom (section headings with
// a lime underbar) plus the Wireshark/CLI command-row idiom (SelectableText mono
// in lime over a muted note) and the §8.16 AppCopyAction. Commands are public +
// static so tests assert the exact verified strings and the copy payload is built
// from the same source (they can never drift).
//
// Glyph note (GL-004): ASCII hyphen-minus only, no em dash. "Wi-Fi" not "WiFi",
// "802.1AB" / "802.1X" exact.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// One reference command: the exact syntax (LIME column) and a one-line note.
/// Immutable so the const dataset can be shared with tests.
@immutable
class LldpCommand {
  const LldpCommand(this.command, this.note);

  /// The exact command syntax, verbatim from the verified command reference.
  final String command;

  /// What it does / when to reach for it.
  final String note;
}

/// A labeled group of commands for one place you can read LLDP or CDP.
@immutable
class LldpCommandGroup {
  const LldpCommandGroup(this.label, this.subtitle, this.commands);

  /// The heading (e.g. "Switch CLI (Cisco)").
  final String label;

  /// A one-line orientation under the heading (where this runs, what you get).
  final String subtitle;

  final List<LldpCommand> commands;
}

/// One "common mistake this reference prevents" - a short, quotable correction.
@immutable
class LldpMistake {
  const LldpMistake(this.wrong, this.right);

  /// The mistaken belief.
  final String wrong;

  /// The correction.
  final String right;
}

/// Find the Switch and Port (LLDP/CDP) reference. Stateless: all content is const
/// and nothing is fetched or executed.
class LldpCdpReferenceScreen extends StatelessWidget {
  const LldpCdpReferenceScreen({super.key});

  /// Stable catalog id - backs the route, the §8.6.2 concept graphic, and the
  /// help entry (assets/help/tool_help.json key "lldp-cdp-reference").
  static const String toolId = 'lldp-cdp-reference';

  static const String screenSummary =
      'Read LLDP or CDP and a switch tells you its own name, the exact port you '
      'are plugged into, its management IP, and often the VLAN. This reference '
      'shows how to read it on every OS and how to find which switch port an '
      'access point is on. The app does not capture the frames for you; it '
      'points you at the tools already on your machine.';

  static const String referenceOnlyBanner =
      'The Toolbox runs no capture and no shell. This is reference text. You run '
      'these commands on the switch, the WLAN Pi, or the laptop yourself.';

  // ── Section 1: what LLDP and CDP are ──
  static const String lldpDefinition =
      'LLDP (Link Layer Discovery Protocol) is the vendor-neutral IEEE standard '
      '802.1AB. Its frames use EtherType 0x88CC and the multicast destination '
      'MAC 01:80:C2:00:00:0E. Each frame carries TLVs (type-length-value); three '
      'are mandatory (Chassis ID, Port ID, Time-to-Live) and the optional TLVs '
      'commonly add the system name, description, port description, management '
      'address, and VLAN ID.';

  static const String cdpDefinition =
      'CDP (Cisco Discovery Protocol) is Cisco proprietary and has no plain '
      'EtherType. It rides an 802.3/SNAP frame to multicast MAC '
      '01:00:0C:CC:CC:CC, so capture filters target it by that MAC or by the '
      'SNAP protocol ID 0x2000, never by an EtherType. It carries the same kind '
      'of data: device name, local and remote port, platform, IP address, and '
      'native VLAN.';

  /// The three facts that decide everything else on the screen.
  static const List<String> threeFacts = <String>[
    'Layer 2, single hop. Switches do not forward LLDP or CDP frames. You only '
        'ever see the device on the other end of your own cable, never anything '
        'past it.',
    'Wired only. These frames do not cross Wi-Fi. A laptop on Wi-Fi sees '
        'nothing; you must be on the wired NIC (on a Mac, usually a USB or '
        'Thunderbolt Ethernet adapter).',
    'The switch has to have it turned on. Cisco IOS runs CDP by default but '
        'ships LLDP off; many non-Cisco switches also ship LLDP off. When '
        'nothing shows up, first check whether the switch is sending, not '
        'whether your tool is broken.',
  ];

  /// The command groups, one per place you can read the frame. Every string is
  /// verbatim from the verified command reference. Public + static so tests assert
  /// the exact verified syntax and _copyText() is built from the same source.
  static const List<LldpCommandGroup> commandGroups = <LldpCommandGroup>[
    LldpCommandGroup(
      'Switch CLI (fastest of all)',
      'Run in privileged EXEC (enable). Where you see the AP and its port '
          'directly, with no host tooling. Cisco syntax shown.',
      <LldpCommand>[
        LldpCommand('show lldp neighbors',
            'Every LLDP neighbor with local and remote port'),
        LldpCommand('show lldp neighbors detail',
            'Adds management IP, system description, capabilities'),
        LldpCommand('show cdp neighbors',
            'Every CDP neighbor (CDP is on by default on Cisco)'),
        LldpCommand('show cdp neighbors detail',
            'Adds neighbor IP, platform, IOS version, native VLAN'),
        LldpCommand('show interfaces status',
            'Link up or down, speed, duplex, VLAN (documented plural form)'),
        LldpCommand('show power inline',
            'Whether the port delivers PoE and how much'),
        LldpCommand('lldp run',
            'Global config: enable LLDP (off by default on Cisco IOS)'),
      ],
    ),
    LldpCommandGroup(
      'Linux (built in, cleanest)',
      'The lldpd daemon prints a parsed neighbor table. No capture needed.',
      <LldpCommand>[
        LldpCommand('lldpcli show neighbors',
            'The parsed neighbor table'),
        LldpCommand('lldpcli show neighbors summary',
            'Remote name and port description (note: summary, not "detail")'),
        LldpCommand('lldpcli show neighbors details',
            'Everything: name, port ID and description, mgmt address, VLAN'),
        LldpCommand('sudo apt install lldpd',
            'Install the daemon (Debian/Ubuntu). Fedora: sudo dnf install lldpd'),
        LldpCommand('sudo systemctl enable --now lldpd',
            'Start it and enable on boot, then query with lldpcli'),
      ],
    ),
    LldpCommandGroup(
      'macOS (built-in tcpdump, needs sudo)',
      'No built-in parser. Capture with tcpdump (ships with macOS) on the WIRED '
          'interface. en5 is a PLACEHOLDER for your USB/Thunderbolt adapter '
          '(often en5 or en7).',
      <LldpCommand>[
        LldpCommand("sudo tcpdump -nn -v -i en5 'ether proto 0x88cc'",
            'LLDP: decode the TLVs (switch name, port, VLAN, mgmt IP). -v '
                'required to decode'),
        LldpCommand('sudo tcpdump -nn -v -i en5 ether host 01:00:0c:cc:cc:cc',
            'CDP: match the CDP MAC (CDP has no EtherType)'),
        LldpCommand(
            'sudo tcpdump -nn -v -i en5 ether proto 0x88cc or ether host '
                '01:00:0c:cc:cc:cc',
            'Both LLDP and CDP in one capture'),
      ],
    ),
    LldpCommandGroup(
      'Windows (built-in pktmon, no driver)',
      'pktmon is in-box on Windows 10 / Server 2019 build 1809 and later, and '
          'Windows 11. Run in an elevated (Administrator) prompt.',
      <LldpCommand>[
        LldpCommand('pktmon filter add LLDP --ethertype 0x88CC',
            'Add the LLDP filter by EtherType (numeric form, Microsoft-documented)'),
        LldpCommand('pktmon filter add CDP -m 01-00-0C-CC-CC-CC',
            'Add the CDP filter by MAC (hyphen or colon delimiter both work)'),
        LldpCommand('pktmon start -c --comp nics --pkt-size 0 -f lldp-cdp.etl',
            'Capture full frames on the NICs to a file (pkt-size 0 avoids '
                'truncating LLDP TLVs)'),
        LldpCommand('pktmon stop',
            'Stop after LLDP/CDP has had time to re-advertise (up to ~60s)'),
        LldpCommand('pktmon etl2txt lldp-cdp.etl -o lldp-cdp.txt -v 3',
            'Convert the log to readable text (verbose is REQUIRED to decode the '
                'TLVs)'),
      ],
    ),
  ];

  /// The AP-port workflow: whose port are you reading?
  static const List<String> apPortWorkflow = <String>[
    'Have switch CLI access? Start there. show lldp neighbors or show cdp '
        'neighbors lists the AP as a neighbor against its switch port. That is '
        'the direct answer, with no host tooling.',
    'Read the low-level state on the switch too. show interfaces status gives '
        'link and speed; show power inline gives PoE. Between them you separate '
        '"no link" from "link but no power" from "powered but not booting."',
    'No switch access? Read LLDP from the AP itself, through its console or '
        'management UI. The AP\'s own neighbor table names the switch and the '
        'port. Your laptop\'s LLDP will not: it only reports the laptop\'s port.',
    'Confirm with a cable swap. Plug a laptop into the exact port and cable the '
        'AP used, read LLDP there, and confirm the switch and port identity '
        'before you re-terminate or re-patch.',
  ];

  /// The Windows correction (Section 3).
  static const String windowsCorrection =
      'If your Windows machine "has LLDP enabled," that almost certainly means '
      'the local LLDP agent is on, which lets the machine send and receive. It '
      'does NOT give you a screen that lists the neighbor. Get-NetLldpAgent reads '
      'local agent settings only (interface alias, index, scope, MAC) and its '
      'module needs the Data Center Bridging feature. To read which switch and '
      'port on Windows, capture with pktmon and read the log as text.';

  static const String windowsServerEnable =
      'On Windows Server the feature install is documented: '
      'Install-WindowsFeature Data-Center-Bridging, then Enable-NetLldpAgent '
      '-NetAdapterName "Ethernet". Enabling the agent still does not print a '
      'neighbor table; use pktmon to read one. Whether the NetLldpAgent module '
      'and Data Center Bridging feature are available on a given Windows 10 or 11 '
      'CLIENT varies by build and NIC driver and is unconfirmed here.';

  static const String vendorEnableCaveat =
      'For any non-Cisco switch (Aruba, Juniper, UniFi, and the rest), the enable '
      'command is not universal. Check your vendor\'s documentation rather than '
      'assuming the Cisco syntax carries over.';

  /// Common mistakes this reference prevents.
  static const List<LldpMistake> mistakes = <LldpMistake>[
    LldpMistake('Get-NetLldpAgent shows the switch and port',
        'It shows local agent config only. Use pktmon to read the neighbor.'),
    LldpMistake('LLDP works over Wi-Fi',
        'It is wired only. A Wi-Fi laptop sees nothing.'),
    LldpMistake("Your laptop's LLDP is the AP's port",
        'It is your port. Read the AP or the switch for the AP\'s port.'),
    LldpMistake('Filter CDP by an EtherType',
        'CDP has none. Match MAC 01:00:0C:CC:CC:CC or SNAP ID 0x2000.'),
    LldpMistake('LLDP is on',
        'Cisco ships it off (CDP on); many vendors ship it off too.'),
    LldpMistake('Wireshark is the only option',
        'Windows (pktmon) and macOS (tcpdump) both have a built-in path.'),
  ];

  static const String footnote =
      'Interface names (en5, eth0) and the tcpdump MAC delimiter are environment '
      'placeholders, not literals. Wireshark is a graphical alternative on both '
      'Windows (needs the Npcap driver) and macOS (a separate install), but is '
      'not required and does not run inside this app. Source: fact-checked '
      'LLDP/CDP how-to brief (2026-07-15), cross-checked against the Wireshark '
      'LLDP wiki, Microsoft Learn (Get-NetLldpAgent, pktmon), lldpd.github.io, '
      'Baeldung (tcpdump), and Study-CCNA/Cisco docs.';

  /// §8.16 plain-text payload - the whole reference as text so nothing on-screen
  /// survives only as layout or color. Built from the same const source as the UI.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Find the Switch and Port (LLDP/CDP)')
      ..writeln()
      ..writeln(screenSummary)
      ..writeln()
      ..writeln('REFERENCE ONLY: $referenceOnlyBanner')
      ..writeln()
      ..writeln('What LLDP and CDP are')
      ..writeln('  $lldpDefinition')
      ..writeln('  $cdpDefinition')
      ..writeln();
    b.writeln('Three facts:');
    for (final String f in threeFacts) {
      b.writeln('  - $f');
    }
    b.writeln();
    for (final LldpCommandGroup g in commandGroups) {
      b
        ..writeln(g.label)
        ..writeln('  ${g.subtitle}');
      for (final LldpCommand c in g.commands) {
        b.writeln('  ${c.command}$tab${c.note}');
      }
      b.writeln();
    }
    b
      ..writeln('The Windows correction')
      ..writeln('  $windowsCorrection')
      ..writeln('  $windowsServerEnable')
      ..writeln();
    b.writeln('Which switch port is the AP on?');
    for (int i = 0; i < apPortWorkflow.length; i++) {
      b.writeln('  ${i + 1}. ${apPortWorkflow[i]}');
    }
    b
      ..writeln()
      ..writeln('Enabling LLDP elsewhere')
      ..writeln('  $vendorEnableCaveat')
      ..writeln();
    b.writeln('Common mistakes this reference prevents:');
    for (final LldpMistake m in mistakes) {
      b.writeln('  - "${m.wrong}" -> ${m.right}');
    }
    b
      ..writeln()
      ..writeln(footnote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('Find the Switch and Port (LLDP/CDP)'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(
            idleLabel: 'Copy reference',
            copiedLabel: 'Reference copied',
            textBuilder: _copyText,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? AppSpacing.screenEdgeDesktop
                    : AppSpacing.screenEdgeMobile,
                vertical: AppSpacing.md,
              ),
              child: CenteredContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ConceptGraphicBand(toolId: toolId, isDesktop: isDesktop),
                    const SizedBox(height: AppSpacing.md),

                    _Summary(),
                    const SizedBox(height: AppSpacing.md),

                    const _ReferenceOnlyBanner(),
                    const SizedBox(height: AppSpacing.lg),

                    // 1. What LLDP and CDP are.
                    const _SectionHeading('What LLDP and CDP are'),
                    const SizedBox(height: AppSpacing.sm),
                    const _Prose(lldpDefinition),
                    const SizedBox(height: AppSpacing.sm),
                    const _Prose(cdpDefinition),
                    const SizedBox(height: AppSpacing.sm),
                    const _NumberedList(threeFacts),
                    const SizedBox(height: AppSpacing.lg),

                    // 2/4/5 commands. Read it: commands by platform.
                    const _SectionHeading('Read it: commands by platform'),
                    const SizedBox(height: AppSpacing.sm),
                    ...commandGroups.expand(
                      (LldpCommandGroup g) => <Widget>[
                        _CommandGroupCard(group: g),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 3. The Windows correction.
                    const _SectionHeading('The Windows correction'),
                    const SizedBox(height: AppSpacing.sm),
                    const _Prose(windowsCorrection),
                    const SizedBox(height: AppSpacing.sm),
                    const _Prose(windowsServerEnable),
                    const SizedBox(height: AppSpacing.lg),

                    // 5. The AP-port workflow.
                    const _SectionHeading(
                        'The AP is dark: which switch port is it on?'),
                    const SizedBox(height: AppSpacing.sm),
                    const _NumberedList(apPortWorkflow),
                    const SizedBox(height: AppSpacing.lg),

                    // 4. Enabling elsewhere.
                    const _SectionHeading('Turning LLDP on where it is off'),
                    const SizedBox(height: AppSpacing.sm),
                    const _Prose(vendorEnableCaveat),
                    const SizedBox(height: AppSpacing.lg),

                    // Common mistakes.
                    const _SectionHeading(
                        'Common mistakes this reference prevents'),
                    const SizedBox(height: AppSpacing.sm),
                    const _MistakesCard(),
                    const SizedBox(height: AppSpacing.lg),

                    _Footnote(),

                    const ToolHelpFooter(toolId: toolId),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ───────────────────────────── Summary ─────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      LldpCdpReferenceScreen.screenSummary,
      style: (text.bodyLarge ?? const TextStyle())
          .copyWith(color: colors.textSecondary),
    );
  }
}

// ─────────────────────── Reference-only banner ───────────────────────

/// The §8.13 info callout stating the app does not capture. Never color-only: a
/// glyph + the "REFERENCE ONLY" eyebrow + the full sentence all carry the meaning
/// (WCAG 1.4.1).
class _ReferenceOnlyBanner extends StatelessWidget {
  const _ReferenceOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color info = colors.statusInfo;
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isLight
              ? colors.statusInfoFill
              : info.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: info),
            right: BorderSide(color: info),
            bottom: BorderSide(color: info),
            left: BorderSide(color: info, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 24, color: info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'REFERENCE ONLY',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: info,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    LldpCdpReferenceScreen.referenceOnlyBanner,
                    style: (text.bodyMedium ?? const TextStyle())
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Section heading ─────────────────────────────

/// A §8.5 H3 heading with a §8.20.2 lime underline accent bar.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: (text.headlineSmall ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: 42,
          height: 3,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Prose ─────────────────────────────

/// A paragraph of body prose in the secondary text color.
class _Prose extends StatelessWidget {
  const _Prose(this.body);

  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      body,
      style: (text.bodyMedium ?? const TextStyle())
          .copyWith(color: colors.textSecondary, height: 1.5),
    );
  }
}

// ───────────────────────────── Numbered list ─────────────────────────────

/// An ordered list rendered as lime mono index pills over body text. Used for the
/// three facts and the AP-port workflow.
class _NumberedList extends StatelessWidget {
  const _NumberedList(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      rows.add(_NumberedRow(number: i + 1, body: items[i]));
      if (i != items.length - 1) {
        rows.add(const SizedBox(height: AppSpacing.sm));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _NumberedRow extends StatelessWidget {
  const _NumberedRow({required this.number, required this.body});

  final int number;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: 'DM Mono',
                fontWeight: FontWeight.w500,
                fontSize: AppTextSize.caption,
                color: colors.onPrimary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              body,
              style: (text.bodyMedium ?? const TextStyle())
                  .copyWith(color: colors.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Command group ─────────────────────────────

/// One place you can read the frame: a heading, a one-line subtitle, then its
/// command rows. The command syntax is selectable + lime (the wireshark/cli
/// idiom).
class _CommandGroupCard extends StatelessWidget {
  const _CommandGroupCard({required this.group});

  final LldpCommandGroup group;

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
        children: <Widget>[
          Text(
            group.label,
            style: (text.labelMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            group.subtitle,
            style: (text.labelSmall ?? const TextStyle())
                .copyWith(color: colors.textTertiary, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...group.commands.map(
            (LldpCommand c) => _CommandRow(command: c, mono: mono, text: text),
          ),
        ],
      ),
    );
  }
}

/// One command row: the selectable lime mono syntax over its muted note.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.mono,
    required this.text,
  });

  final LldpCommand command;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${command.command}, ${command.note}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(
              command.command,
              style: mono.inlineCode.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              command.note,
              style: (text.labelMedium ?? const TextStyle())
                  .copyWith(color: colors.textTertiary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Mistakes ─────────────────────────────

/// The "common mistakes" list: a struck belief and its correction per row.
class _MistakesCard extends StatelessWidget {
  const _MistakesCard();

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < LldpCdpReferenceScreen.mistakes.length; i++) ...<Widget>[
            if (i != 0) const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              excludeSemantics: true,
              label:
                  'Myth: ${LldpCdpReferenceScreen.mistakes[i].wrong}. '
                  'Correction: ${LldpCdpReferenceScreen.mistakes[i].right}',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.close_rounded,
                      size: 18, color: colors.statusWarning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: (text.bodyMedium ?? const TextStyle())
                            .copyWith(color: colors.textSecondary, height: 1.5),
                        children: <InlineSpan>[
                          TextSpan(
                            text: LldpCdpReferenceScreen.mistakes[i].wrong,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(
                              text: LldpCdpReferenceScreen.mistakes[i].right),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── Footnote ─────────────────────────────

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      LldpCdpReferenceScreen.footnote,
      style: (text.labelSmall ?? const TextStyle())
          .copyWith(color: colors.textTertiary, height: 1.4),
    );
  }
}
