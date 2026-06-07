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
// Frame-type encoding: the PWA used four literal hex swatches (mgmt blue, eap
// purple, wired orange, dhcp green), which this screen first ported to the four
// §8.13 status hues. The §8.15 standing ruling (2026-06-01) names this exact
// table as case-3 — frame *types* are merely different categories, not a
// canonical color code and not a pass/warn/fail verdict, so they get NO hue.
// The status-hue legend is removed; frame types are now told apart by a neutral
// short type code (MGMT / EAP / WIRED / DHCP) rendered in DM Mono, plus the
// neutral step chip and the existing surface/border structure. No status token,
// no lime — a frame-sequence table has no single measured quantity to mark.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

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

  /// Short neutral type code shown per row in DM Mono. This is how the four
  /// categories are told apart now (§8.15 case-3) — a textual code, never a
  /// hue. It is also never the sole carrier of meaning: each row also names the
  /// frame in plain text and the legend expands every code.
  String get code {
    switch (this) {
      case FxType.mgmt:
        return 'MGMT';
      case FxType.eap:
        return 'EAP';
      case FxType.wired:
        return 'WIRED';
      case FxType.dhcp:
        return 'DHCP';
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

  FxScenario get _selected => FrameExchangeScreen.scenarios.firstWhere(
    (FxScenario s) => s.key == _selectedKey,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('802.11 Frame Exchange'),
        toolbarHeight: 64,
        // §8.16 — copy the selected scenario's frame sequence as TSV, one
        // section per phase. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the selected scenario's full frame sequence as a
  /// multi-section TSV. The scenario title names the document; each phase is
  /// its own section (phase name subtitle + header + one row per frame).
  /// Columns: Step, Type, Direction, Frame, Note. Always non-null (static
  /// data); the frame-type code is included as its WORD so the §8.15-suppressed
  /// category survives the copy.
  String _buildCopyText() {
    const String tab = '\t';
    final FxScenario s = _selected;
    final StringBuffer buf = StringBuffer()..writeln(s.title);
    for (final FxPhase phase in s.phases) {
      buf
        ..writeln()
        ..writeln(phase.name)
        ..writeln(
          <String>['Step', 'Type', 'Direction', 'Frame', 'Note'].join(tab),
        );
      for (final FxFrame f in phase.frames) {
        buf.writeln(
          <String>['${f.n}', f.type.code, f.dir, f.label, f.note].join(tab),
        );
      }
    }
    return buf.toString().trimRight();
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
                    toolId: 'frame-exchange',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('frame-exchange'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _selectorCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _sequenceCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _legendCard(context),
                  ToolHelpFooter(toolId: 'frame-exchange'),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _card(
      child: Text(
        '802.11 frame sequences for common association and roaming scenarios. '
        'Shows the order of frames exchanged between the STA, AP, RADIUS '
        'server, and DHCP server.',
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final FxScenario s = _selected;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: text.headlineSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final FxPhase phase in s.phases) _PhaseBlock(phase: phase),
        ],
      ),
    );
  }

  Widget _legendCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frame types',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase.name,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceRowSemantics(
      // The frame type is now spoken too (was carried only by the removed color
      // swatch) so screen-reader users get the category that sighted users read
      // from the type code.
      label: rowLabel('Step ${frame.n}', <String?>[
        '${frame.type.code} frame',
        frame.dir,
        frame.label,
        frame.note,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Neutral numbered step chip (§8.15 case-3): surface step + strong
            // border + DM Mono index. No status hue — the chip no longer encodes
            // a category by color. Excluded from semantics (the row label already
            // says "Step N"); the swatch is now purely structural.
            ExcludeSemantics(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: colors.borderStrong, width: 1),
                ),
                child: Text(
                  '${frame.n}',
                  style: mono.inlineCode.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          frame.dir,
                          style: text.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      // Neutral type code — the category, carried by text not hue.
                      _TypeTag(code: frame.type.code, mono: mono),
                    ],
                  ),
                  Text(
                    frame.label,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (frame.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        frame.note,
                        style: text.labelMedium?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
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

/// Neutral frame-type code tag (MGMT / EAP / WIRED / DHCP). A DM Mono pill on a
/// neutral surface + decorative border — the category is carried by the code
/// text, never by a status hue (§8.15 case-3). Excluded from semantics because
/// the row label already speaks the frame type.
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.code, required this.mono});

  final String code;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Text(
          code,
          style: mono.inlineCode.copyWith(
            fontSize: 11,
            height: 1.2,
            color: colors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// One legend entry: the neutral type-code tag + the full type label. Maps the
/// short row code (MGMT / EAP / WIRED / DHCP) to its plain-English meaning. No
/// color swatch — the legend now expands a textual code, not a hue (§8.15).
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.type});

  final FxType type;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TypeTag(code: type.code, mono: mono),
        const SizedBox(width: AppSpacing.xs),
        // Flexible + ellipsis so a long legend label ("Wired (RADIUS / DHCP)")
        // shrinks within the Wrap line at 320px instead of overflowing the row
        // (F-04). The Wrap bounds each item to the card-content width, which is
        // the constraint the Flexible flexes against.
        Flexible(
          child: Text(
            type.legendLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
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
            dir: 'AP → STA',
            label: 'Beacon Frame',
            type: FxType.mgmt,
            note: 'AP broadcasts BSS info (SSID, rates, capabilities, RSN IE)',
          ),
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'Probe Request',
            type: FxType.mgmt,
            note:
                'STA actively scans for specific SSID (optional — passive '
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
            note:
                'Open System auth — always succeeds; just a formality before '
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
            note:
                'STA requests association, declares its capabilities and RSN '
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
            note:
                'AP sends GTK (group key), encrypted with PTK. STA installs '
                'PTK',
          ),
          FxFrame(
            n: 11,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 4/4)',
            type: FxType.eap,
            note:
                'STA confirms GTK installed. Both sides now have matching '
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
            note:
                'STA initiates SAE Dragonfly handshake. Contains scalar and '
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
            note:
                'STA sends confirmation token. Both sides derive PMK from the '
                'exchange — no password is transmitted',
          ),
          FxFrame(
            n: 5,
            dir: 'AP → STA',
            label: 'SAE Confirm (Auth Seq 2)',
            type: FxType.mgmt,
            note:
                'AP confirms. Auth complete. PMK is now shared — forward '
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
    key: 'owe',
    tabLabel: 'OWE / Enhanced Open',
    title: 'OWE / Enhanced Open (Opportunistic Wireless Encryption)',
    phases: <FxPhase>[
      FxPhase(
        name: 'Discovery',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'AP → STA',
            label: 'Beacon / Probe Response',
            type: FxType.mgmt,
            note:
                'AP advertises OWE via the RSN element with AKM suite '
                '00-0F-AC:18 (OWE). No passphrase, no certificate.',
          ),
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'Probe Request',
            type: FxType.mgmt,
            note:
                'STA discovers / queries the BSS (optional if it already has '
                'the Beacon).',
          ),
        ],
      ),
      FxPhase(
        name: 'Open System Authentication',
        frames: <FxFrame>[
          FxFrame(
            n: 3,
            dir: 'STA → AP',
            label: 'Auth Request (Open), seq 1',
            type: FxType.mgmt,
            note: 'Open System authentication request. No keys yet.',
          ),
          FxFrame(
            n: 4,
            dir: 'AP → STA',
            label: 'Auth Response (Open), seq 2',
            type: FxType.mgmt,
            note: 'Open System authentication response, status success.',
          ),
        ],
      ),
      FxPhase(
        name: 'Association — Diffie-Hellman key exchange (the OWE crux)',
        frames: <FxFrame>[
          FxFrame(
            n: 5,
            dir: 'STA → AP',
            label: 'Association Request (+ DH Parameter element)',
            type: FxType.mgmt,
            note:
                'Carries the RSN element (OWE AKM) PLUS the Diffie-Hellman '
                "Parameter element with the STA's ECDH public key and group ID. "
                'This is where OWE differs from open: the key ride is in the '
                'Assoc Request.',
          ),
          FxFrame(
            n: 6,
            dir: 'AP → STA',
            label: 'Association Response (+ DH Parameter element)',
            type: FxType.mgmt,
            note:
                "Carries the AP's ECDH public key in its own Diffie-Hellman "
                'Parameter element. Both sides now compute the DH shared secret '
                '→ PMK (PMK = HKDF over the DH result and both public keys). No '
                'pre-shared material is used.',
          ),
        ],
      ),
      FxPhase(
        name: '4-Way Handshake (standard, using the OWE-derived PMK)',
        frames: <FxFrame>[
          FxFrame(
            n: 7,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 1/4)',
            type: FxType.eap,
            note: 'AP sends ANonce. Identical handshake to WPA2/WPA3, but the '
                'PMK came from the DH exchange above.',
          ),
          FxFrame(
            n: 8,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 2/4)',
            type: FxType.eap,
            note: 'STA sends SNonce + MIC; STA derives the PTK.',
          ),
          FxFrame(
            n: 9,
            dir: 'AP → STA',
            label: 'EAPOL Key (Msg 3/4)',
            type: FxType.eap,
            note: 'GTK delivered + MIC; install keys.',
          ),
          FxFrame(
            n: 10,
            dir: 'STA → AP',
            label: 'EAPOL Key (Msg 4/4)',
            type: FxType.eap,
            note:
                'ACK; both install the PTK. Every client gets a unique session '
                'key, so passive sniffing on the open SSID is defeated. '
                'Transition mode: an AP can pair a legacy Open BSS with a hidden '
                'OWE BSS so OWE-capable clients silently move to the encrypted '
                'one.',
          ),
        ],
      ),
    ],
  ),
  FxScenario(
    key: 'passpoint',
    tabLabel: 'Passpoint / Hotspot 2.0',
    title: 'Passpoint / Hotspot 2.0 (pre-association GAS/ANQP, then EAP)',
    phases: <FxPhase>[
      FxPhase(
        name: 'Discovery',
        frames: <FxFrame>[
          FxFrame(
            n: 1,
            dir: 'AP → STA',
            label: 'Beacon / Probe Response',
            type: FxType.mgmt,
            note:
                'AP advertises Hotspot 2.0 via the Interworking element (and '
                'HS2.0 Indication).',
          ),
        ],
      ),
      FxPhase(
        name: 'Pre-association query (GAS / ANQP — the distinct part)',
        frames: <FxFrame>[
          FxFrame(
            n: 2,
            dir: 'STA → AP',
            label: 'GAS Initial Request (Public Action)',
            type: FxType.mgmt,
            note:
                'Carries an ANQP query (NAI Realm List, Roaming Consortium / '
                'RCOI, 3GPP Cellular, Domain Name). Sent unauthenticated and '
                'unassociated — the STA has no IP yet, so GAS Public Action '
                'frames are the transport.',
          ),
          FxFrame(
            n: 3,
            dir: 'AP → STA',
            label: 'GAS Initial Response (Public Action)',
            type: FxType.mgmt,
            note:
                'Returns the ANQP data — or a delay token / comeback if the '
                'response is large or not ready. The STA can now decide WHETHER '
                'this network can authenticate it before committing.',
          ),
          FxFrame(
            n: 4,
            dir: 'STA ↔ AP',
            label: 'GAS Comeback Request / Response (optional)',
            type: FxType.mgmt,
            note:
                'Only when the ANQP response is fragmented or delayed: the STA '
                'fetches the remaining ANQP fragments. Skipped on short '
                'responses.',
          ),
        ],
      ),
      FxPhase(
        name: 'Association',
        frames: <FxFrame>[
          FxFrame(
            n: 5,
            dir: 'STA → AP',
            label: 'Auth Request (Open) + Association',
            type: FxType.mgmt,
            note:
                'STA has decided to join: Open System auth, then Association '
                'Request/Response negotiating the 802.1X AKM in the RSN '
                'element.',
          ),
        ],
      ),
      FxPhase(
        name: 'EAP authentication + 4-Way Handshake (ordinary 802.1X)',
        frames: <FxFrame>[
          FxFrame(
            n: 6,
            dir: 'STA ↔ AP ↔ RADIUS',
            label: '802.1X / EAP method exchange',
            type: FxType.eap,
            note:
                'Full EAP runs — typically EAP-TLS, EAP-TTLS, or EAP-SIM/AKA '
                'for carrier SIM auth. After association the air sequence is the '
                'ordinary 802.1X/EAP flow (see the WPA2-Enterprise scenario).',
          ),
          FxFrame(
            n: 7,
            dir: 'STA ↔ AP',
            label: '4-Way Handshake (Msg 1/4 … 4/4)',
            type: FxType.eap,
            note:
                'Standard handshake using the EAP-derived PMK. '
                'OpenRoaming note: OpenRoaming (WBA) is a federation built ON '
                'this Passpoint exchange — an RCOI match in the ANQP query '
                'triggers the EAP auth shown here. The roaming agreements and '
                'identity federation are backend (WBA WRIX), not new '
                'over-the-air frames. It can also be paired with OWE for its '
                'settlement-free open tier.',
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
            note:
                'Status = 0. STA now associated but port is blocked '
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
            note:
                'RADIUS sends EAP challenge (e.g. TLS tunnel setup for '
                'PEAP/EAP-TLS)',
          ),
          FxFrame(
            n: 10,
            dir: 'AP ↔ STA',
            label: 'EAP Method Exchange',
            type: FxType.eap,
            note:
                'Multiple round-trips for the chosen EAP method (PEAP, '
                'EAP-TLS, EAP-TTLS). Credential exchange happens inside '
                'encrypted TLS tunnel',
          ),
          FxFrame(
            n: 11,
            dir: 'RADIUS → AP',
            label: 'RADIUS Access-Accept',
            type: FxType.wired,
            note:
                'Auth succeeded. RADIUS optionally delivers MSK (Master '
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
            note:
                'PTK/GTK installed. Data can now flow. '
                'eduroam note: eduroam uses this EXACT air sequence — the '
                "difference is backend RADIUS proxying that routes auth to the "
                "user's home institution by the realm in the outer identity "
                '(user@institution.edu). There is no eduroam-specific over-the-'
                'air frame.',
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
            note:
                'Full association and 4-Way Handshake with AP1. PMK-R0 and '
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
            note:
                'STA scans for neighboring APs (aided by 802.11k Neighbor '
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
            note:
                'STA sends MDIE + FTIE with SNonce. AP2 fetches PMK-R1 from '
                'R1KH (via DS or R0KH)',
          ),
          FxFrame(
            n: 5,
            dir: 'AP2 → STA',
            label: 'FT Auth Response (Seq 2)',
            type: FxType.mgmt,
            note:
                'AP2 sends ANonce + FTIE. PTK is now derivable by both sides '
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
            note:
                'Contains MDIE + FTIE. No separate 4-Way Handshake needed — '
                'keys already negotiated',
          ),
          FxFrame(
            n: 7,
            dir: 'AP2 → STA',
            label: 'FT Reassociation Response',
            type: FxType.mgmt,
            note:
                'Status = 0. STA is now associated to AP2. Total roam latency '
                '< 50 ms with 802.11r vs > 150 ms without. '
                'Over-the-DS variant: instead of the FT Auth frames above going '
                'over the air to AP2, the STA sends an FT Action Request to its '
                'CURRENT AP, which relays it to the target AP through the '
                'distribution system; the FT Action Response comes back the same '
                'way. The roam then finishes with the same Reassociation '
                'Request/Response. Over-the-air uses Authentication frames (FT '
                'algorithm); over-the-DS uses Action frames.',
          ),
        ],
      ),
    ],
  ),
];
