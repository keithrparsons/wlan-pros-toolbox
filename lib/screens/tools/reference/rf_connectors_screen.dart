// RF Connectors — read-only RF coaxial connector reference card.
//
// One static table ported verbatim from the RF Tools PWA (app.js
// RF_CONN_DATA, view data-tool="rfconn"): each connector's impedance, max
// frequency, mating style, and field notes.
//
// This is a pure read-only reference — no inputs, no computation, no network.
// It works on every platform (no NetworkUnavailableView). The only state is
// "success": the bundled dataset always renders. There is no loading, empty,
// or error path because nothing is fetched or parsed at runtime.
//
// Layout note: the PWA renders this as a 5-column scrolling HTML table. On
// phone width that table is too wide to fit, so each connector is rendered as
// a card-internal block instead — name + impedance/frequency/mating as mono
// data rows, notes beneath. No horizontal scroll needed; the row idiom matches
// db_reference_screen and avoids a RenderFlex overflow at 320pt.
//
// Glyph note: negatives/ranges use ASCII hyphen-minus (U+002D) to match the
// rest of the app (dbm_watt converter Vera F-08). The PWA's en dash in
// frequency ranges ("DC–11 GHz") is normalized to a hyphen here. The ohm sign
// (Ω) is preserved as a data glyph, not punctuation.
//
// De-emphasis: the PWA paints 75Ω rows at opacity 0.6 (F-Type — wrong
// impedance for Wi-Fi). We carry that signal with a warning-tinted impedance
// chip plus a textual "75Ω — not for WLAN" note rather than opacity, so the
// cue survives a colorblind/low-vision read (never color-only, GL-003 §8.13).

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One RF connector row. Fields mirror the PWA's RF_CONN_DATA tuple
/// [name, impedance, maxFreq, mating, notes].
class RfConnector {
  const RfConnector({
    required this.name,
    required this.impedance,
    required this.maxFreq,
    required this.mating,
    required this.notes,
  });

  final String name;
  final String impedance;
  final String maxFreq;
  final String mating;
  final String notes;

  /// True when the connector is not 50 ohm — a Wi-Fi impedance mismatch the
  /// PWA de-emphasizes. Used to tint the impedance chip and flag the row.
  bool get isImpedanceMismatch => !impedance.startsWith('50');
}

class RfConnectorsScreen extends StatelessWidget {
  const RfConnectorsScreen({super.key});

  /// RF connector reference. Ported verbatim from PWA app.js RF_CONN_DATA
  /// (tuple order: name, impedance, maxFreq, mating, notes). En-dash frequency
  /// ranges normalized to ASCII hyphen-minus per the app-wide glyph rule.
  static const List<RfConnector> rfConnectors = [
    RfConnector(
      name: 'N-Type',
      impedance: '50Ω',
      maxFreq: 'DC-11 GHz',
      mating: 'Screw thread',
      notes:
          'Outdoor WLAN standard - rooftop antennas, WISP sectors, outdoor APs. '
          'Weatherproof when fully mated.',
    ),
    RfConnector(
      name: 'TNC',
      impedance: '50Ω',
      maxFreq: 'DC-11 GHz',
      mating: 'Threaded (BNC body)',
      notes:
          'Vibration-resistant BNC variant. Vehicle-mount, in-building DAS, '
          'military.',
    ),
    RfConnector(
      name: 'BNC',
      impedance: '50Ω',
      maxFreq: 'DC-4 GHz',
      mating: 'Bayonet push-twist',
      notes:
          'Test equipment and lab cables only. Do not use for Wi-Fi antenna '
          'runs above 1 GHz.',
    ),
    RfConnector(
      name: 'SMA',
      impedance: '50Ω',
      maxFreq: 'DC-18 GHz',
      mating: 'Screw (1/4-36 UNF)',
      notes:
          'Indoor AP pigtails, small antennas, module jumpers. Handles 2.4, 5, '
          'and 6 GHz.',
    ),
    RfConnector(
      name: 'RP-SMA',
      impedance: '50Ω',
      maxFreq: 'DC-18 GHz',
      mating: 'Screw (reversed pin)',
      notes:
          'FCC Part 15 anti-interconnect - center contact is reversed vs '
          'standard SMA. Consumer APs, USB adapters. NOT interchangeable with '
          'SMA.',
    ),
    RfConnector(
      name: 'MCX',
      impedance: '50Ω',
      maxFreq: 'DC-6 GHz',
      mating: 'Snap-on',
      notes:
          'Compact embedded systems. Smaller than SMA. Used on M.2 Wi-Fi cards.',
    ),
    RfConnector(
      name: 'MMCX',
      impedance: '50Ω',
      maxFreq: 'DC-6 GHz',
      mating: 'Snap-on (rotates)',
      notes:
          'Rotates 360 degrees after mating. Laptops, mini-PCIe, and M.2 Wi-Fi '
          'cards.',
    ),
    RfConnector(
      name: 'U.FL/IPEX',
      impedance: '50Ω',
      maxFreq: 'DC-6 GHz',
      mating: 'Push-snap (fragile)',
      notes:
          'Internal PCB antenna connections. Rated ~30 mate cycles. Used on '
          'virtually all embedded Wi-Fi modules.',
    ),
    RfConnector(
      name: 'F-Type',
      impedance: '75Ω',
      maxFreq: 'DC-3 GHz',
      mating: 'Screw',
      notes:
          '75Ω CATV standard - impedance mismatch with 50Ω Wi-Fi causes '
          'significant loss. Do not use for WLAN.',
    ),
  ];

  /// Footnote — context for the impedance-mismatch flag. Not a PWA string;
  /// it surfaces the same de-emphasis the PWA shows via opacity, in text.
  static const String footnote =
      'Wi-Fi is a 50Ω system. Connectors flagged as 75Ω (F-Type) carry an '
      'impedance mismatch and significant loss - do not use them on WLAN '
      'antenna runs. Frequency ranges are typical maximums; verify against the '
      'specific part before design decisions.';

  /// §8.16 copy payload — the RF-connector table as TSV. Static reference data,
  /// so the affordance is always enabled (never returns null). Title line, a
  /// header row, then one tab-separated row per connector; the 75Ω mismatch
  /// flag is carried as a worded cell so the on-screen warning hue survives the
  /// copy (§8.16 verdict-word rule).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Coaxial RF Connectors')
      ..writeln(
        <String>[
          'Connector',
          'Impedance',
          'Max freq.',
          'Mating',
          'Wi-Fi impedance',
          'Notes',
        ].join(tab),
      );
    for (final RfConnector c in rfConnectors) {
      buf.writeln(
        <String>[
          c.name,
          c.impedance,
          c.maxFreq,
          c.mating,
          c.isImpedanceMismatch ? 'Mismatch (not for WLAN)' : 'Match (50Ω)',
          c.notes,
        ].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RF Connectors'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'rf-connectors'),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
                    toolId: 'rf-connectors',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('rf-connectors'))
                    const SizedBox(height: AppSpacing.md),
                  _connectorsCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(text),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _connectorsCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Coaxial RF Connectors',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rfConnectors.length; i++) ...[
            if (i > 0)
              const Divider(
                height: AppSpacing.md,
                thickness: 1,
                color: AppColors.border,
              ),
            _ConnectorBlock(connector: rfConnectors[i], text: text, mono: mono),
          ],
        ],
      ),
    );
  }

  Widget _footnoteCard(TextTheme text) {
    return _Card(
      heading: 'Notes',
      headingText: text,
      child: Text(
        footnote,
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

/// Shared card surface — matches the reference-card idiom in
/// db_reference_screen.
class _Card extends StatelessWidget {
  const _Card({
    required this.heading,
    required this.headingText,
    required this.child,
  });

  final String heading;
  final TextTheme headingText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            style: headingText.labelMedium?.copyWith(
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

/// One connector block: name + impedance chip on the title line, then the
/// frequency and mating as mono data rows, then the field notes. Stacks
/// vertically so it never overflows at phone width (no 5-column table).
class _ConnectorBlock extends StatelessWidget {
  const _ConnectorBlock({
    required this.connector,
    required this.text,
    required this.mono,
  });

  final RfConnector connector;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    // Group the whole connector block as one container labelled by the
    // connector name, so a screen reader announces "BNC" then steps through
    // its impedance / frequency / mating / notes as a coherent unit rather
    // than as orphaned nodes. merge:false keeps the impedance chip's own
    // label/value node intact. (Vera F-02.)
    return ReferenceRowSemantics(
      label: connector.name,
      merge: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title line: connector name + impedance chip.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    connector.name,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _ImpedanceChip(connector: connector, mono: mono),
              ],
            ),
            const SizedBox(height: 4),
            // Frequency + mating as labeled mono data rows.
            _DataRow(label: 'Max freq.', value: connector.maxFreq, mono: mono),
            _DataRow(label: 'Mating', value: connector.mating, mono: mono),
            // Field notes.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                connector.notes,
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

/// Impedance chip. 50Ω reads as a quiet neutral chip; a non-50Ω mismatch
/// (F-Type, 75Ω) reads in the warning hue AND keeps its text label, so the
/// cue is not color-only (GL-003 §8.13 rule 2 / WCAG 2.2 SC 1.4.1).
class _ImpedanceChip extends StatelessWidget {
  const _ImpedanceChip({required this.connector, required this.mono});

  final RfConnector connector;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final bool mismatch = connector.isImpedanceMismatch;
    final Color fg = mismatch
        ? AppColors.statusWarning
        : AppColors.textSecondary;
    // §8.13 rule 3 sanctions a low-alpha status tint band. Derive it from the
    // statusWarning token (no literal hex) at ~10% alpha over the card.
    final Color bg = mismatch
        ? AppColors.statusWarning.withValues(alpha: 0.10)
        : AppColors.surface2;
    final String semanticValue = mismatch
        ? '${connector.impedance}, impedance mismatch for Wi-Fi'
        : connector.impedance;
    return Semantics(
      label: 'Impedance',
      value: semanticValue,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          connector.impedance,
          style: mono.inlineCode.copyWith(
            color: fg,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// One labeled data row inside a connector block: a fixed-width caption label
/// and a mono value. The value uses Expanded so long mating descriptions wrap
/// instead of overflowing at narrow width.
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    required this.mono,
  });

  final String label;
  final String value;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono.inlineCode.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
