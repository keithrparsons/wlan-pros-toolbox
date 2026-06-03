// Roaming Parameters (802.11k/r/v reference) — a fully offline, read-only
// reference. Mirrors the signal_thresholds_screen idiom: Scaffold + AppBar
// (toolbarHeight 64), SafeArea(top:false), LayoutBuilder isDesktop@720,
// Center + ConstrainedBox(calculatorMaxWidth), one SingleChildScrollView of
// cards built from semantic tokens.
//
// States (SOP-007 §5): this surface is a static dataset compiled into the
// screen — there is no fetch, so no loading / error / empty paths exist. The
// only state is the rendered reference (success). No NetworkUnavailableView:
// works on every platform, no OS data, no I/O.
//
// Data is ported VERBATIM from the rf-tools-pwa `roaming` tool
// (data-tool="roaming", "Roaming Parameters" view in www/index.html, plus the
// ROAMING_PROTOCOLS and ROAMING_THRESHOLDS consts in www/app.js). Two blocks:
// the protocol overview (802.11r / 802.11k / 802.11v) and the RSSI/SNR design
// threshold table. Thresholds are reproduced, not invented. The PWA defines
// exactly these three protocols — OKC is not in the source and is not added.
//
// The threshold scenarios carry a GL-003 §8.13 status verdict color
// (statusSuccess / statusWarning / statusDanger) ALWAYS paired with the
// scenario word — never color-only (§8.13 rule 2 / WCAG 2.2 SC 1.4.1).
//
// Overflow-safe: the 5-column threshold table is wider than phone width, so it
// renders inside a horizontal SingleChildScrollView with fixed-width cells —
// it scrolls sideways rather than overflowing.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';

/// Coarse roaming verdict used to tint a scenario with the §8.13 status
/// palette. Always rendered alongside its label word, never as color alone.
enum RoamGrade { good, marginal, bad }

/// One roaming protocol (the PWA `ROAMING_PROTOCOLS` entries).
class RoamingProtocol {
  const RoamingProtocol({
    required this.proto,
    required this.name,
    required this.what,
    required this.requirements,
    required this.note,
  });

  /// Protocol label, e.g. "802.11r". Never "802.11R".
  final String proto;

  /// Full name, e.g. "Fast BSS Transition (FT)".
  final String name;

  /// What it does.
  final String what;

  /// Deployment requirements.
  final String requirements;

  /// Field note / caveat.
  final String note;
}

/// One roaming design-threshold row (the PWA `ROAMING_THRESHOLDS` rows).
class RoamingThreshold {
  const RoamingThreshold({
    required this.scenario,
    required this.minRssi,
    required this.minSnr,
    required this.roamLatency,
    required this.designRule,
    required this.grade,
  });

  final String scenario;
  final String minRssi; // e.g. "≥ −67 dBm"
  final String minSnr; // e.g. "≥ 25 dB"
  final String roamLatency; // e.g. "< 50 ms (with 802.11r)" or "—"
  final String designRule;
  final RoamGrade grade;
}

class RoamingScreen extends StatelessWidget {
  const RoamingScreen({super.key});

  // ─── Datasets (public static for testing) ─────────────────────────────────
  // Verbatim from rf-tools-pwa www/app.js. Em dashes in the PWA prose are
  // rendered as hyphens here per the no-em-dash rule; the PWA's own minus signs
  // (U+2212) in the dBm values and its em-dash "no value" cell marker are kept
  // exactly as the PWA paints them so the reference reads identically.

  /// 802.11r / 802.11k / 802.11v protocol overview.
  static const List<RoamingProtocol> kProtocols = <RoamingProtocol>[
    RoamingProtocol(
      proto: '802.11r',
      name: 'Fast BSS Transition (FT)',
      what:
          'Pre-authenticates the client to neighboring APs before roaming '
          'occurs, caching the Pairwise Master Key. Reduces roaming latency '
          'from >150 ms to <50 ms.',
      requirements:
          'Both AP and client must support 802.11r. Must be enabled per SSID '
          'on the controller.',
      note:
          'Essential for VoIP / UC over Wi-Fi. Some legacy clients have '
          'compatibility issues - test before deploying enterprise-wide.',
    ),
    RoamingProtocol(
      proto: '802.11k',
      name: 'Neighbor Report',
      what:
          'AP provides the client a list of neighboring APs (channel, BSSID, '
          'RSSI) so the client scans only relevant channels rather than all '
          '40+ available.',
      requirements: 'Both AP and client must support 802.11k.',
      note:
          'Reduces channel scan time. Does not speed up the association step '
          'itself. Works alongside 802.11r.',
    ),
    RoamingProtocol(
      proto: '802.11v',
      name: 'BSS Transition Management',
      what:
          'AP can suggest - or request - that a client roam to a better or '
          'less loaded AP. Primary tool for steering sticky clients.',
      requirements:
          'Client must support 802.11v BSS-TM. Not all clients honor the '
          'request; behavior is client-firmware dependent.',
      note:
          'Android and iOS generally comply. Some Windows Wi-Fi drivers ignore '
          'BSS-TM requests entirely.',
    ),
  ];

  /// RSSI / SNR / latency design thresholds. Grades map the scenario to a
  /// §8.13 verdict: the two design targets pass (good), the overlap zone is
  /// marginal, the sticky-trigger and unusable rows fail (bad).
  static const List<RoamingThreshold> kThresholds = <RoamingThreshold>[
    RoamingThreshold(
      scenario: 'VoIP / UC design target',
      minRssi: '≥ −67 dBm',
      minSnr: '≥ 25 dB',
      roamLatency: '< 50 ms (with 802.11r)',
      designRule: '≥ 2 APs at −67 dBm everywhere',
      grade: RoamGrade.good,
    ),
    RoamingThreshold(
      scenario: 'Standard data design target',
      minRssi: '≥ −70 dBm',
      minSnr: '≥ 20 dB',
      roamLatency: '< 150 ms',
      designRule: '≥ 2 APs at −70 dBm everywhere',
      grade: RoamGrade.good,
    ),
    RoamingThreshold(
      scenario: 'Roaming overlap zone (target)',
      minRssi: '−70 to −72 dBm',
      minSnr: '≥ 15 dB',
      roamLatency: '—',
      designRule: '15–20% cell overlap minimum',
      grade: RoamGrade.marginal,
    ),
    RoamingThreshold(
      scenario: 'Sticky client trigger (typical)',
      minRssi: '−75 to −80 dBm',
      minSnr: '< 15 dB',
      roamLatency: '—',
      designRule: 'NIC should roam here - many do not',
      grade: RoamGrade.bad,
    ),
    RoamingThreshold(
      scenario: 'Unusable - roam immediately',
      minRssi: '< −80 dBm',
      minSnr: '< 10 dB',
      roamLatency: '—',
      designRule: 'Connection unreliable below this',
      grade: RoamGrade.bad,
    ),
  ];

  /// §8.13 verdict tint for a grade. Color is never the only signal — the
  /// scenario word always renders beside it.
  static Color gradeColor(RoamGrade grade) {
    switch (grade) {
      case RoamGrade.good:
        return AppColors.statusSuccess;
      case RoamGrade.marginal:
        return AppColors.statusWarning;
      case RoamGrade.bad:
        return AppColors.statusDanger;
    }
  }

  /// Worded verdict for a grade — the clipboard carrier of the §8.13 status hue
  /// the threshold rows paint on-screen (§8.16 verdict-word rule).
  static String gradeWord(RoamGrade grade) {
    switch (grade) {
      case RoamGrade.good:
        return 'Good';
      case RoamGrade.marginal:
        return 'Marginal';
      case RoamGrade.bad:
        return 'Bad';
    }
  }

  /// §8.16 copy payload — both reference blocks as TSV. Static data, so always
  /// enabled. Two sections (subtitle + header + rows): the 802.11k/r/v protocol
  /// overview, then the RSSI/SNR/latency design thresholds. The threshold
  /// grade is carried as a worded Verdict cell so the on-screen status hue
  /// survives the copy.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Roaming Parameters (802.11k/r/v)')
      ..writeln()
      ..writeln('Protocols')
      ..writeln(
        <String>[
          'Protocol',
          'Name',
          'What it does',
          'Requirements',
          'Note',
        ].join(tab),
      );
    for (final RoamingProtocol p in kProtocols) {
      buf.writeln(
        <String>[p.proto, p.name, p.what, p.requirements, p.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Thresholds')
      ..writeln(
        <String>[
          'Scenario',
          'Verdict',
          'Min RSSI',
          'Min SNR',
          'Roam latency',
          'Design rule',
        ].join(tab),
      );
    for (final RoamingThreshold r in kThresholds) {
      buf.writeln(
        <String>[
          r.scenario,
          gradeWord(r.grade),
          r.minRssi,
          r.minSnr,
          r.roamLatency,
          r.designRule,
        ].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roaming Parameters'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
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
                  ConceptGraphicBand(toolId: 'roaming', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('roaming'))
                    const SizedBox(height: AppSpacing.md),
                  _intro(context),
                  const SizedBox(height: AppSpacing.sm),
                  _protocolsCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _thresholdsCard(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Honest framing — the PWA tool description, in intent.
  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      '802.11k/r/v protocol overview and RSSI/SNR thresholds for enterprise '
      'roaming design. Targets vary by client hardware and AP vendor; treat as '
      'design guidelines, not guarantees.',
      style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
    );
  }

  Widget _protocolsCard(BuildContext context) {
    return _Card(
      heading: 'Protocols',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < kProtocols.length; i++) ...<Widget>[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Divider(height: 1, color: AppColors.border),
              ),
            _ProtocolBlock(protocol: kProtocols[i]),
          ],
        ],
      ),
    );
  }

  Widget _thresholdsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Wide 5-column table: scroll horizontally so it never overflows on phone
    // width. Fixed-width cells keep the columns aligned across rows.
    return _Card(
      heading: 'Thresholds',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThresholdHeader(text: text),
              ...kThresholds.map(
                (RoamingThreshold r) =>
                    _ThresholdRow(row: r, text: text, mono: mono),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Fixed column widths for the horizontally-scrolled threshold table ───────
const double _kScenarioW = 200;
const double _kRssiW = 120;
const double _kSnrW = 84;
const double _kLatencyW = 168;
const double _kRuleW = 220;

/// Shared surface-1 card with a section heading — same shape the sibling
/// reference screens use, kept local since this is a reference-only screen.
class _Card extends StatelessWidget {
  const _Card({required this.heading, required this.child});

  final String heading;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// One protocol: "802.11r — Fast BSS Transition (FT)" heading (proto in lime,
/// the active/interactive accent role per §8.2), then the What / Requirements
/// lines and a muted field note.
class _ProtocolBlock extends StatelessWidget {
  const _ProtocolBlock({required this.protocol});

  final RoamingProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      label:
          '${protocol.proto}, ${protocol.name}. '
          'What it does: ${protocol.what} '
          'Requirements: ${protocol.requirements} '
          '${protocol.note}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heading: proto label + full name. "—" joins them, matching the
            // PWA "${proto} — ${name}" heading.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: protocol.proto,
                    style: (text.bodyLarge ?? const TextStyle()).copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  ${protocol.name}',
                    style: (text.bodyLarge ?? const TextStyle()).copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _LabeledLine(label: 'What it does', body: protocol.what),
            const SizedBox(height: AppSpacing.xs),
            _LabeledLine(label: 'Requirements', body: protocol.requirements),
            const SizedBox(height: AppSpacing.xs),
            Text(
              protocol.note,
              style: text.labelMedium?.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "Label: body" line where the label is emphasized and the body is body
/// copy. Used for the What it does / Requirements rows.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: (text.bodyMedium ?? const TextStyle()).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: body,
            style: (text.bodyMedium ?? const TextStyle()).copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header row for the horizontally-scrolled threshold table.
class _ThresholdHeader extends StatelessWidget {
  const _ThresholdHeader({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = text.labelMedium?.copyWith(
      color: AppColors.textTertiary,
      letterSpacing: 0.3,
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: _kScenarioW,
              child: Text('Scenario', style: style),
            ),
            SizedBox(
              width: _kRssiW,
              child: Text('Min RSSI', style: style),
            ),
            SizedBox(
              width: _kSnrW,
              child: Text('Min SNR', style: style),
            ),
            SizedBox(
              width: _kLatencyW,
              child: Text('Roam Latency', style: style),
            ),
            SizedBox(
              width: _kRuleW,
              child: Text('Design Rule', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// One threshold scenario row. The scenario word is status-tinted (§8.13) and
/// the numeric cells render in mono so the dBm/dB columns align. Color is never
/// the only signal — the scenario word carries the verdict in text.
class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.row,
    required this.text,
    required this.mono,
  });

  final RoamingThreshold row;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final Color tint = RoamingScreen.gradeColor(row.grade);
    final TextStyle monoCell = mono.inlineCode.copyWith(
      color: AppColors.textPrimary,
      fontSize: AppTextSize.caption,
    );
    return Semantics(
      label:
          '${row.scenario}. Minimum RSSI ${row.minRssi}, '
          'minimum SNR ${row.minSnr}, roam latency ${row.roamLatency}. '
          '${row.designRule}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scenario — status-tinted verdict word + a verdict dot. The word
            // carries the meaning; the dot is decorative reinforcement.
            SizedBox(
              width: _kScenarioW,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      row.scenario,
                      style: (text.bodyMedium ?? const TextStyle()).copyWith(
                        color: tint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _kRssiW,
              child: Text(row.minRssi, style: monoCell),
            ),
            SizedBox(
              width: _kSnrW,
              child: Text(row.minSnr, style: monoCell),
            ),
            SizedBox(
              width: _kLatencyW,
              child: Text(
                row.roamLatency,
                style: monoCell.copyWith(color: AppColors.textTertiary),
              ),
            ),
            SizedBox(
              width: _kRuleW,
              child: Text(
                row.designRule,
                style: text.labelMedium?.copyWith(
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
