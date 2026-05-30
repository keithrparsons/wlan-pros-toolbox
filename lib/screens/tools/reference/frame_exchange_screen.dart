// 802.11 Frame Exchange — read-only reference of the frame sequences for
// common association and roaming scenarios. Shows the order of frames
// exchanged between the STA, AP, RADIUS server, and DHCP server.
//
// Data is ported verbatim from the rf-tools-pwa `frames` tool
// (FX_SCENARIOS / FX_COLORS in www/app.js). The PWA presented the four
// scenarios as tabs; App Mode uses the shared AppSelect<String> (GL-003 §8.14)
// since the labels are long and there are 4 options.
//
// States (SOP-007 §5): this is a static, fully-offline reference with no I/O,
// so there is no loading / error / empty state to model. The success state is
// the rendered sequence; the selector is the only interactive state (idle /
// focus / open / disabled — all handled inside AppSelect). Every scenario in
// the dataset is non-empty, so the surface always has frames to show.
//
// Frame-type color: the PWA used four literal hex swatches (mgmt blue, eap
// purple, wired orange, dhcp green). Design-system law forbids literal hex, so
// each categorical type maps to a semantic status token that keeps the four
// colors visually distinct (see _FxType.color). Flagged to Iris as a possible
// §8.13 categorical-palette gap.

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../labeled_field.dart';

/// Categorical frame type. Mirrors the PWA `type` field (mgmt|eap|wired|dhcp).
enum FxType { mgmt, eap, wired, dhcp }

extension _FxTypeView on FxType {
  /// Legend label — verbatim from the PWA `typeKey` map.
  String get legendLabel {
    switch (this) {
      case FxType.mgmt:
        return 'Management frame';
      case FxType.eap:
        return 'EAP / EAPOL key';
      case FxType.wired:
        return 'Wired (RADIUS / DHCP)';
      case FxType.dhcp:
        return 'DHCP';
    }
  }

  /// Semantic token per categorical type. Replaces the PWA literal hex
  /// (mgmt #0071e3, eap #7B1FA2, wired #E65100, dhcp #2E7D32) with the four
  /// distinct §8.13 status tokens so the categories stay distinguishable
  /// without hardcoding color.
  Color get color {
    switch (this) {
      case FxType.mgmt:
        return AppColors.statusInfo; // blue → info
      case FxType.eap:
        return AppColors.primary; // purple → lime key/handshake accent
      case FxType.wired:
        return AppColors.statusWarning; // orange → warning amber
      case FxType.dhcp:
        return AppColors.statusSuccess; // green → success mint
    }
  }
}

/// One frame in a sequence. `n` is the step number, `dir` the direction line
/// (e.g. "STA → AP"), `label` the frame name, `note` the optional explanation.
@immutable
class FxFrame {
  const FxFrame({
    required this.n,
    required this.dir,
    required this.label,
    required this.type,
    this.note = '',
  });

  final int n;
  final String dir;
  final String label;
  final FxType type;
  final String note;
}

/// A named group of frames within a scenario (the PWA `phase`).
@immutable
class FxPhase {
  const FxPhase({required this.name, required this.frames});

  final String name;
  final List<FxFrame> frames;
}

/// A full frame-exchange scenario. `key` is the stable dataset id (matches the
/// PWA tab key), `tabLabel` the selector label (verbatim PWA tab text),
/// `title` the per-scenario heading.
@immutable
class FxScenario {
  const FxScenario({
    required this.key,
    required this.tabLabel,
    required this.title,
    required this.phases,
  });

  final String key;
  final String tabLabel;
  final String title;
  final List<FxPhase> phases;
}

/// 802.11 Frame Exchange reference screen. Route '/tools/frame-exchange'
/// (registered by Larry in app_router.dart / tool_catalog.dart).
class FrameExchangeScreen extends StatefulWidget {
  const FrameExchangeScreen({super.key});

  /// The frame-exchange dataset, ported verbatim from the rf-tools-pwa
  /// FX_SCENARIOS const. Public + static so tests can assert step sequences
  /// against the PWA without pumping the widget.
  static const List<FxScenario> scenarios = _kScenarios;

  @override
  State<FrameExchangeScreen> createState() => _FrameExchangeScreenState();
}

class _FrameExchangeScreenState extends State<FrameExchangeScreen> {
  // Selected scenario key. Defaults to the PWA's initially-active tab ('open').
  String _selectedKey = FrameExchangeScreen.scenarios.first.key;

  FxScenario get _selected => FrameExchangeScreen.scenarios
      .firstWhere((FxScenario s) => s.key == _selectedKey);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Frame Exchange'), toolbarHeight: 64),
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
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _selectorCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _sequenceCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _legendCard(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tool description — verbatim from the PWA `tool-desc`.
  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _card(
      child: Text(
        '802.11 frame sequences for common association and roaming scenarios. '
        'Shows the order of frames exchanged between the STA, AP, RADIUS '
        'server, and DHCP server.',
        style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _selectorCard(BuildContext context) {
    final List<AppSelectItem<String>> items = FrameExchangeScreen.scenarios
        .map((FxScenario s) => (s.key, s.tabLabel))
        .toList();
    return _card(
      child: LabeledField(
        label: 'Scenario',
        field: AppSelect<String>(
          value: _selectedKey,
          items: items,
          semanticLabel: 'Frame-exchange scenario',
          onChanged: (String key) => setState(() => _selectedKey = key),
        ),
      ),
    );
  }

  Widget _sequenceCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FxScenario s = _selected;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: text.headlineSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final FxPhase phase in s.phases) _PhaseBlock(phase: phase),
        ],
      ),
    );
  }

  Widget _legendCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Legend',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final FxType t in FxType.values) _LegendItem(type: t),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

/// One phase: a phase name followed by its frames.
class _PhaseBlock extends StatelessWidget {
  const _PhaseBlock({required this.phase});

  final FxPhase phase;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase.name,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final FxFrame f in phase.frames) _FrameRow(frame: f),
        ],
      ),
    );
  }
}

/// One frame row: a numbered color chip + direction, label, and optional note.
class _FrameRow extends StatelessWidget {
  const _FrameRow({required this.frame});

  final FxFrame frame;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbered type chip. The number reads on the type color; Exclude
          // semantics so AT does not re-announce the index (the label carries
          // meaning, the swatch is decorative).
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: frame.type.color,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              '${frame.n}',
              style: text.labelMedium?.copyWith(
                color: AppColors.surface0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  frame.dir,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  frame.label,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (frame.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      frame.note,
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
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

/// One legend entry: a color dot + the type label.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.type});

  final FxType type;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: type.color,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          type.legendLabel,
          style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Dataset (ported verbatim from rf-tools-pwa FX_SCENARIOS) ────────────────

const List<FxScenario> _kScenarios = <FxScenario>[
  FxScenario(
    key: 'open',
    tabLabel: 'Open / WPA2-PSK',
    title: 'Open Network / WPA2-Personal Association',
    phases: <FxPhase>[
      FxPhase(
        name: '802.11 Probe & Auth',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'STA → AP',
            label: 'Beacon Frame',
            type: FxType.mgmt,
            note: 'AP broadcasts BSS info (SSID, rates, capabilities, RSN IE)',
          ),
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'Probe Request',
            type: FxType.mgmt,
            note: 'STA actively scans for specific SSID (optional — passive '
                'scan skips this)',
          ),
          FxFrame(
            n: 3,
            dir: 'AP → STA',
            label: 'Probe Response',
            type: FxType.mgmt,
            note: 'AP replies with same info as Beacon',
          ),
          FxFrame(
            n: 4,
            dir: 'STA → AP',
            label: 'Auth Request (Open)',
            type: FxType.mgmt,
            note: 'Open System auth — always succeeds; just a formality before '
                'Association',
          ),
          FxFrame(
            n: 5,
            dir: 'AP → STA',
            label: 'Auth Response',
            type: FxType.mgmt,
            note: 'Status = 0 (success). Auth is now complete',
          ),
        ],
      ),
      FxPhase(
        name: 'Association',
        frames: <FxFrame>[
          FxFrame(
            n: 6,
            dir: 'STA → AP',
            label: 'Association Request',
            type: FxType.mgmt,
            note: 'STA requests association, declares its capabilities and RSN '
                'IE (cipher suites, PMF)',
          ),
          FxFrame(
            n: 7,
            dir: 'AP → STA',
            label: 'Association Response',
            type: FxType.mgmt,
            note: 'Status = 0 (success). AID assigned. STA is now associated',
          ),
        ],
      ),
      FxPhase(
        name: '4-Way Handshake (WPA2-PSK only — skip for Open networks)',
        frames: <FxFrame>[
          FxFrame(
            n: 8,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 1/4)',
            type: FxType.eap,
            note: 'AP sends ANonce. STA derives PTK from PMK + ANonce + SNonce',
          ),
          FxFrame(
            n: 9,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 2/4)',
            type: FxType.eap,
            note: 'STA sends SNonce + MIC. AP derives PTK and verifies MIC',
          ),
          FxFrame(
            n: 10,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 3/4)',
            type: FxType.eap,
            note: 'AP sends GTK (group key), encrypted with PTK. STA installs '
                'PTK',
          ),
          FxFrame(
            n: 11,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 4/4)',
            type: FxType.eap,
            note: 'STA confirms GTK installed. Both sides now have matching '
                'PTK/GTK',
          ),
        ],
      ),
      FxPhase(
        name: 'DHCP (via AP Relay)',
        frames: <FxFrame>[
          FxFrame(
            n: 12,
            dir: 'STA → AP',
            label: 'DHCP Discover',
            type: FxType.dhcp,
            note: 'Broadcast. AP relays to DHCP server',
          ),
          FxFrame(
            n: 13,
            dir: 'AP → STA',
            label: 'DHCP Offer',
            type: FxType.dhcp,
            note: 'DHCP server → AP relay → STA: proposed IP address',
          ),
          FxFrame(
            n: 14,
            dir: 'STA → AP',
            label: 'DHCP Request',
            type: FxType.dhcp,
            note: 'STA confirms it wants the offered address',
          ),
          FxFrame(
            n: 15,
            dir: 'AP → STA',
            label: 'DHCP Ack',
            type: FxType.dhcp,
            note: 'IP address assigned. STA is fully connected',
          ),
        ],
      ),
    ],
  ),
  FxScenario(
    key: 'wpa3',
    tabLabel: 'WPA3-SAE',
    title: 'WPA3-Personal (SAE) Association',
    phases: <FxPhase>[
      FxPhase(
        name: 'Probe & SAE Authentication',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'STA → AP',
            label: 'Probe Request / Beacon',
            type: FxType.mgmt,
            note: 'Same as WPA2 — STA discovers BSS',
          ),
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'SAE Commit (Auth Seq 1)',
            type: FxType.mgmt,
            note: 'STA initiates SAE Dragonfly handshake. Contains scalar and '
                'element derived from passphrase',
          ),
          FxFrame(
            n: 3,
            dir: 'AP → STA',
            label: 'SAE Commit (Auth Seq 1)',
            type: FxType.mgmt,
            note: 'AP replies with its own scalar and element',
          ),
          FxFrame(
            n: 4,
            dir: 'STA → AP',
            label: 'SAE Confirm (Auth Seq 2)',
            type: FxType.mgmt,
            note: 'STA sends confirmation token. Both sides derive PMK from the '
                'exchange — no password is transmitted',
          ),
          FxFrame(
            n: 5,
            dir: 'AP → STA',
            label: 'SAE Confirm (Auth Seq 2)',
            type: FxType.mgmt,
            note: 'AP confirms. Auth complete. PMK is now shared — forward '
                'secrecy guaranteed',
          ),
        ],
      ),
      FxPhase(
        name: 'Association',
        frames: <FxFrame>[
          FxFrame(
            n: 6,
            dir: 'STA → AP',
            label: 'Association Request',
            type: FxType.mgmt,
            note: 'Declares WPA3 RSN IE. PMF (802.11w) is mandatory',
          ),
          FxFrame(
            n: 7,
            dir: 'AP → STA',
            label: 'Association Response',
            type: FxType.mgmt,
            note: 'Status = 0. AID assigned',
          ),
        ],
      ),
      FxPhase(
        name: '4-Way Handshake',
        frames: <FxFrame>[
          FxFrame(
            n: 8,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 1/4)',
            type: FxType.eap,
            note: 'Same PTK derivation as WPA2, but PMK came from SAE not PSK',
          ),
          FxFrame(
            n: 9,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 2/4)',
            type: FxType.eap,
          ),
          FxFrame(
            n: 10,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 3/4)',
            type: FxType.eap,
            note: 'GTK delivered encrypted',
          ),
          FxFrame(
            n: 11,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 4/4)',
            type: FxType.eap,
            note: 'PTK and GTK installed. Management frames now PMF-protected',
          ),
        ],
      ),
      FxPhase(
        name: 'DHCP',
        frames: <FxFrame>[
          FxFrame(
            n: 12,
            dir: 'STA ↔ AP',
            label: 'DHCP Discover / Offer / Request / Ack',
            type: FxType.dhcp,
            note: 'Identical to WPA2 flow',
          ),
        ],
      ),
    ],
  ),
  FxScenario(
    key: 'dot1x',
    tabLabel: 'WPA2-Enterprise',
    title: 'WPA2-Enterprise (802.1X / EAP) Association',
    phases: <FxPhase>[
      FxPhase(
        name: 'Probe & Open Auth',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'STA → AP',
            label: 'Probe Request / Beacon',
            type: FxType.mgmt,
            note: 'STA discovers BSS',
          ),
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'Auth Request (Open)',
            type: FxType.mgmt,
            note: 'Open System auth — same as WPA2-PSK preamble',
          ),
          FxFrame(
            n: 3,
            dir: 'AP → STA',
            label: 'Auth Response',
            type: FxType.mgmt,
            note: 'Status = 0',
          ),
          FxFrame(
            n: 4,
            dir: 'STA → AP',
            label: 'Association Request',
            type: FxType.mgmt,
            note: 'RSN IE declares 802.1X/EAP AKMP',
          ),
          FxFrame(
            n: 5,
            dir: 'AP → STA',
            label: 'Association Response',
            type: FxType.mgmt,
            note: 'Status = 0. STA now associated but port is blocked '
                '(Controlled Port = closed)',
          ),
        ],
      ),
      FxPhase(
        name: 'EAP Authentication (over 802.1X)',
        frames: <FxFrame>[
          FxFrame(
            n: 6,
            dir: 'AP → STA',
            label: 'EAP-Request / Identity',
            type: FxType.eap,
            note: 'AP (Authenticator) prompts for identity',
          ),
          FxFrame(
            n: 7,
            dir: 'STA → AP',
            label: 'EAP-Response / Identity',
            type: FxType.eap,
            note: 'STA sends username/identity',
          ),
          FxFrame(
            n: 8,
            dir: 'AP → RADIUS',
            label: 'RADIUS Access-Request',
            type: FxType.wired,
            note: 'AP forwards identity to RADIUS server (UDP 1812)',
          ),
          FxFrame(
            n: 9,
            dir: 'RADIUS → AP',
            label: 'RADIUS Access-Challenge',
            type: FxType.wired,
            note: 'RADIUS sends EAP challenge (e.g. TLS tunnel setup for '
                'PEAP/EAP-TLS)',
          ),
          FxFrame(
            n: 10,
            dir: 'AP ↔ STA',
            label: 'EAP Method Exchange',
            type: FxType.eap,
            note: 'Multiple round-trips for the chosen EAP method (PEAP, '
                'EAP-TLS, EAP-TTLS). Credential exchange happens inside '
                'encrypted TLS tunnel',
          ),
          FxFrame(
            n: 11,
            dir: 'RADIUS → AP',
            label: 'RADIUS Access-Accept',
            type: FxType.wired,
            note: 'Auth succeeded. RADIUS optionally delivers MSK (Master '
                'Session Key) and VLAN assignment',
          ),
          FxFrame(
            n: 12,
            dir: 'AP → STA',
            label: 'EAP-Success',
            type: FxType.eap,
            note: 'AP notifies STA. Controlled Port opens',
          ),
        ],
      ),
      FxPhase(
        name: '4-Way Handshake',
        frames: <FxFrame>[
          FxFrame(
            n: 13,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 1/4)',
            type: FxType.eap,
            note: 'PMK is derived from MSK (not from a passphrase)',
          ),
          FxFrame(
            n: 14,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 2/4)',
            type: FxType.eap,
          ),
          FxFrame(
            n: 15,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 3/4)',
            type: FxType.eap,
          ),
          FxFrame(
            n: 16,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 4/4)',
            type: FxType.eap,
            note: 'PTK/GTK installed. Data can now flow',
          ),
        ],
      ),
    ],
  ),
  FxScenario(
    key: 'ft',
    tabLabel: '802.11r Roam',
    title: '802.11r Fast BSS Transition (Fast Roam)',
    phases: <FxPhase>[
      FxPhase(
        name: 'Initial Association (AP1)',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'STA → AP1',
            label: 'Standard association',
            type: FxType.mgmt,
            note: 'Full association and 4-Way Handshake with AP1. PMK-R0 and '
                'PMK-R1 keys are derived and cached at AP1 and the R0KH/R1KH',
          ),
        ],
      ),
      FxPhase(
        name: 'Roam Discovery',
        frames: <FxFrame>[
          FxFrame(
            n: 2,
            dir: 'STA → AP2',
            label: 'Probe Request (to AP2)',
            type: FxType.mgmt,
            note: 'STA scans for neighboring APs (aided by 802.11k Neighbor '
                'Report if supported)',
          ),
          FxFrame(
            n: 3,
            dir: 'AP2 → STA',
            label: 'Probe Response',
            type: FxType.mgmt,
            note: 'AP2 advertises FT capability in RSN IE (MDIE present)',
          ),
        ],
      ),
      FxPhase(
        name: 'FT Authentication (Over-the-Air)',
        frames: <FxFrame>[
          FxFrame(
            n: 4,
            dir: 'STA → AP2',
            label: 'FT Auth Request (Seq 1)',
            type: FxType.mgmt,
            note: 'STA sends MDIE + FTIE with SNonce. AP2 fetches PMK-R1 from '
                'R1KH (via DS or R0KH)',
          ),
          FxFrame(
            n: 5,
            dir: 'AP2 → STA',
            label: 'FT Auth Response (Seq 2)',
            type: FxType.mgmt,
            note: 'AP2 sends ANonce + FTIE. PTK is now derivable by both sides '
                'without a full 4-Way Handshake',
          ),
        ],
      ),
      FxPhase(
        name: 'Reassociation',
        frames: <FxFrame>[
          FxFrame(
            n: 6,
            dir: 'STA → AP2',
            label: 'FT Reassociation Request',
            type: FxType.mgmt,
            note: 'Contains MDIE + FTIE. No separate 4-Way Handshake needed — '
                'keys already negotiated',
          ),
          FxFrame(
            n: 7,
            dir: 'AP2 → STA',
            label: 'FT Reassociation Response',
            type: FxType.mgmt,
            note: 'Status = 0. STA is now associated to AP2. Total roam latency '
                '< 50 ms with 802.11r vs > 150 ms without',
          ),
        ],
      ),
    ],
  ),
];
