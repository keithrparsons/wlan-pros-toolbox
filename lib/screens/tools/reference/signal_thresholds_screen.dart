// Signal Thresholds (RSSI / SNR reference) — a fully offline, read-only
// reference table. Mirrors the gold-standard port_reference_screen idiom:
// Scaffold + AppBar (toolbarHeight 64), SafeArea(top:false), LayoutBuilder
// isDesktop@720, Center + ConstrainedBox(calculatorMaxWidth), one
// SingleChildScrollView of cards built from semantic tokens.
//
// States (SOP-007 §5): this surface is a static bundled dataset — there is no
// fetch, so no loading / error / empty paths exist. The only state is the
// rendered table (success). No NetworkUnavailableView: works on every
// platform, no OS data, no I/O.
//
// Data is ported VERBATIM from the rf-tools-pwa `rssi` tool (data-tool="rssi",
// "Signal Thresholds" view in www/index.html). Three blocks: the RSSI quality
// scale, the per-application RSSI/SNR threshold table, and the SNR→MCS table.
// Thresholds are reproduced, not invented.
//
// Signal quality and MCS bands carry a GL-003 §8.13 status verdict color
// (statusSuccess / statusWarning / statusDanger) ALWAYS paired with the quality
// word — never color-only (§8.13 rule 2 / WCAG 2.2 SC 1.4.1).

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';

/// Coarse signal verdict used to tint a row with the §8.13 status palette.
/// Always rendered alongside its label word, never as color alone.
enum SignalGrade { good, marginal, bad }

/// One RSSI quality band (the PWA "signal-scale" block).
class SignalBand {
  const SignalBand({
    required this.label,
    required this.range,
    required this.grade,
  });

  /// Quality word — "Excellent", "Good", "Fair", "Weak", "Poor".
  final String label;

  /// RSSI range as the PWA states it, e.g. "> -50 dBm", "-50 to -67".
  final String range;

  final SignalGrade grade;
}

/// One per-application threshold row (PWA "Application / Min RSSI / Min SNR /
/// Notes" table).
class AppThreshold {
  const AppThreshold({
    required this.application,
    required this.minRssi,
    required this.minSnr,
    required this.notes,
  });

  final String application;
  final String minRssi; // e.g. "-67 dBm"
  final String minSnr; // e.g. "25 dB"
  final String notes;
}

/// One SNR → MCS row (PWA "Min SNR / Typical MCS / Rate" table).
class SnrMcsRow {
  const SnrMcsRow({
    required this.minSnr,
    required this.mcs,
    required this.rate,
  });

  final String minSnr; // e.g. "5 dB"
  final String mcs; // e.g. "MCS 0 - BPSK 1/2"
  final String rate; // e.g. "~29-36 Mbps"
}

class SignalThresholdsScreen extends StatelessWidget {
  const SignalThresholdsScreen({super.key});

  // ─── Dataset (public static for testing) ──────────────────────────────────
  // Verbatim from rf-tools-pwa www/index.html, data-tool="rssi". Em dashes in
  // the PWA source are rendered as hyphens here per the no-em-dash rule; the
  // numeric thresholds are unchanged.

  /// RSSI quality scale. Excellent/Good read as a passing verdict, Fair as
  /// marginal, Weak/Poor as failing — paired with the word, never color-only.
  static const List<SignalBand> kSignalBands = <SignalBand>[
    SignalBand(label: 'Excellent', range: '> -50 dBm', grade: SignalGrade.good),
    SignalBand(label: 'Good', range: '-50 to -67', grade: SignalGrade.good),
    SignalBand(label: 'Fair', range: '-67 to -70', grade: SignalGrade.marginal),
    SignalBand(label: 'Weak', range: '-70 to -80', grade: SignalGrade.bad),
    SignalBand(label: 'Poor', range: '< -80 dBm', grade: SignalGrade.bad),
  ];

  /// Per-application minimum RSSI / SNR targets.
  static const List<AppThreshold> kAppThresholds = <AppThreshold>[
    AppThreshold(
      application: 'VoIP / Real-time',
      minRssi: '-67 dBm',
      minSnr: '25 dB',
      notes: 'Packet loss <1%',
    ),
    AppThreshold(
      application: 'Video streaming (HD)',
      minRssi: '-70 dBm',
      minSnr: '20 dB',
      notes: 'Buffer-sensitive',
    ),
    AppThreshold(
      application: 'General browsing',
      minRssi: '-70 dBm',
      minSnr: '15 dB',
      notes: 'Tolerates retries',
    ),
    AppThreshold(
      application: 'Email / basic data',
      minRssi: '-75 dBm',
      minSnr: '10 dB',
      notes: 'Low throughput OK',
    ),
    AppThreshold(
      application: 'IoT / low-rate',
      minRssi: '-80 dBm',
      minSnr: '8 dB',
      notes: 'Infrequent bursts',
    ),
    AppThreshold(
      application: 'Location / RTLS',
      minRssi: '-75 dBm',
      minSnr: '15 dB',
      notes: 'Accuracy degrades <-75',
    ),
  ];

  /// SNR → typical MCS index and indicative rate (80 MHz, 1 SS).
  static const List<SnrMcsRow> kSnrMcsRows = <SnrMcsRow>[
    SnrMcsRow(minSnr: '5 dB', mcs: 'MCS 0 - BPSK 1/2', rate: '~29-36 Mbps'),
    SnrMcsRow(minSnr: '8 dB', mcs: 'MCS 1 - QPSK 1/2', rate: '~58-72 Mbps'),
    SnrMcsRow(minSnr: '10 dB', mcs: 'MCS 2 - QPSK 3/4', rate: '~87-108 Mbps'),
    SnrMcsRow(
      minSnr: '13 dB',
      mcs: 'MCS 3 - 16-QAM 1/2',
      rate: '~117-144 Mbps',
    ),
    SnrMcsRow(
      minSnr: '16 dB',
      mcs: 'MCS 4 - 16-QAM 3/4',
      rate: '~175-216 Mbps',
    ),
    SnrMcsRow(
      minSnr: '20 dB',
      mcs: 'MCS 5 - 64-QAM 2/3',
      rate: '~234-288 Mbps',
    ),
    SnrMcsRow(
      minSnr: '22 dB',
      mcs: 'MCS 6 - 64-QAM 3/4',
      rate: '~263-324 Mbps',
    ),
    SnrMcsRow(
      minSnr: '24 dB',
      mcs: 'MCS 7 - 64-QAM 5/6',
      rate: '~292-360 Mbps',
    ),
    SnrMcsRow(
      minSnr: '28 dB',
      mcs: 'MCS 8 - 256-QAM 3/4',
      rate: '~351-432 Mbps',
    ),
    SnrMcsRow(
      minSnr: '30 dB',
      mcs: 'MCS 9 - 256-QAM 5/6',
      rate: '~390-480 Mbps',
    ),
    SnrMcsRow(
      minSnr: '33 dB',
      mcs: 'MCS 10 - 1024-QAM 3/4',
      rate: '~540 Mbps (ax)',
    ),
    SnrMcsRow(
      minSnr: '35 dB',
      mcs: 'MCS 11 - 1024-QAM 5/6',
      rate: '~600 Mbps (ax)',
    ),
  ];

  /// §8.13 verdict tint for a grade. Color is never the only signal — the
  /// quality word always renders beside it.
  static Color gradeColor(SignalGrade grade) {
    switch (grade) {
      case SignalGrade.good:
        return AppColors.statusSuccess;
      case SignalGrade.marginal:
        return AppColors.statusWarning;
      case SignalGrade.bad:
        return AppColors.statusDanger;
    }
  }

  /// Worded verdict for a grade — the clipboard carrier of the §8.13 status hue
  /// the RSSI quality scale paints on-screen (§8.16 verdict-word rule).
  static String gradeWord(SignalGrade grade) {
    switch (grade) {
      case SignalGrade.good:
        return 'Good';
      case SignalGrade.marginal:
        return 'Marginal';
      case SignalGrade.bad:
        return 'Bad';
    }
  }

  /// §8.16 copy payload — all three reference blocks as TSV. Static data, so
  /// always enabled. Three sections (subtitle + header + rows): the RSSI
  /// quality scale (verdict word carries the status hue), the per-application
  /// minimum RSSI/SNR table, and the SNR→MCS rate table.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Signal Thresholds (RSSI / SNR)')
      ..writeln()
      ..writeln('RSSI quality scale')
      ..writeln(<String>['Quality', 'Verdict', 'RSSI range'].join(tab));
    for (final SignalBand b in kSignalBands) {
      buf.writeln(<String>[b.label, gradeWord(b.grade), b.range].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Minimum signal by application')
      ..writeln(
        <String>['Application', 'Min RSSI', 'Min SNR', 'Notes'].join(tab),
      );
    for (final AppThreshold r in kAppThresholds) {
      buf.writeln(
        <String>[r.application, r.minRssi, r.minSnr, r.notes].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('SNR to MCS (80 MHz, 1 SS)')
      ..writeln(<String>['Min SNR', 'Typical MCS', 'Rate'].join(tab));
    for (final SnrMcsRow r in kSnrMcsRows) {
      buf.writeln(<String>[r.minSnr, r.mcs, r.rate].join(tab));
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signal Thresholds'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'signal-thresholds'),
        ],
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
                  ConceptGraphicBand(
                    toolId: 'signal-thresholds',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('signal-thresholds'))
                    const SizedBox(height: AppSpacing.md),
                  _intro(context),
                  const SizedBox(height: AppSpacing.sm),
                  _signalScaleCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _appThresholdsCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _snrMcsCard(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Honest framing — the PWA's own caveat, verbatim in intent.
  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Reference thresholds for RSSI and SNR. Values vary by client hardware, '
      'environment, and AP vendor. Treat as field-planning guidelines, not '
      'guarantees.',
      style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
    );
  }

  Widget _signalScaleCard(BuildContext context) {
    return _Card(
      heading: 'RSSI quality scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: kSignalBands.map(_SignalBandRow.new).toList(),
      ),
    );
  }

  Widget _appThresholdsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      heading: 'Minimum signal by application',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThresholdHeader(text: text),
          ...kAppThresholds.map(
            (AppThreshold r) => _ThresholdRow(row: r, text: text, mono: mono),
          ),
        ],
      ),
    );
  }

  Widget _snrMcsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      heading: 'SNR to MCS (80 MHz, 1 SS)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SnrMcsHeader(text: text),
          ...kSnrMcsRows.map(
            (SnrMcsRow r) => _SnrMcsRowTile(row: r, text: text, mono: mono),
          ),
        ],
      ),
    );
  }
}

/// Shared surface-1 card with a section heading — same shape the network tools
/// use, kept local since this is a reference-only screen.
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

/// One RSSI quality band: a verdict dot + the quality word (status-tinted) and
/// the dBm range on the right. Word + color together — never color-only.
class _SignalBandRow extends StatelessWidget {
  const _SignalBandRow(this.band);

  final SignalBand band;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color tint = SignalThresholdsScreen.gradeColor(band.grade);
    return Semantics(
      label: '${band.label} signal, ${band.range}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          children: [
            // Verdict dot — decorative; the word beside it is the real signal.
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                band.label,
                style: (text.bodyLarge ?? const TextStyle()).copyWith(
                  color: tint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              band.range,
              style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

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
            Expanded(flex: 5, child: Text('Application', style: style)),
            Expanded(
              flex: 3,
              child: Text('RSSI', style: style, textAlign: TextAlign.right),
            ),
            Expanded(
              flex: 2,
              child: Text('SNR', style: style, textAlign: TextAlign.right),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.row,
    required this.text,
    required this.mono,
  });

  final AppThreshold row;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${row.application}. Minimum RSSI ${row.minRssi}, '
          'minimum SNR ${row.minSnr}. ${row.notes}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    row.application,
                    style: (text.bodyLarge ?? const TextStyle()).copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.minRssi,
                    textAlign: TextAlign.right,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    row.minSnr,
                    textAlign: TextAlign.right,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              row.notes,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnrMcsHeader extends StatelessWidget {
  const _SnrMcsHeader({required this.text});

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
            Expanded(flex: 2, child: Text('SNR', style: style)),
            Expanded(flex: 5, child: Text('Typical MCS', style: style)),
            Expanded(
              flex: 3,
              child: Text('Rate', style: style, textAlign: TextAlign.right),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnrMcsRowTile extends StatelessWidget {
  const _SnrMcsRowTile({
    required this.row,
    required this.text,
    required this.mono,
  });

  final SnrMcsRow row;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${row.minSnr} SNR, ${row.mcs}, ${row.rate}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                row.minSnr,
                style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                row.mcs,
                style: (text.bodyLarge ?? const TextStyle()).copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                row.rate,
                textAlign: TextAlign.right,
                style: mono.inlineCode.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
