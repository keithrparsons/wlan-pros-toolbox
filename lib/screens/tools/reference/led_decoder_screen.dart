// AP Status-LED Decoder (cross-vendor) — the INTERACTIVE drill-down reference
// screen (Field & Trade Reference set, 2026-07-05). Unlike the static reference
// screens, this one carries selection state:
//
//   pick a vendor -> pick a model line (only when the vendor has >1 line)
//   -> read that line's own LED state table.
//
// The structure IS the point (GL-005): resolving the model line before any
// color is shown is what stops the cross-vendor color collision from ever being
// presented as a universal key. A warning band up front states the collision in
// plain terms; the standing caveat rides every view.
//
// Renders led_decoder_data.dart VERBATIM (Penn/Pax voice-gated, SOP-020 PASS;
// source Deliverables/2026-07-05-field-trade-reference/content/18-led-decoder.md).
//
// The vendor picker also carries, at its head (above the vendor list), the
// Vera-passed MASTER CROSS-VENDOR COMPARISON plate (a dark-baked raster, the
// whole color matrix on one dense chart) mounted in the established zoomable
// DarkRasterDiagramCard — tap to open the full-screen pinch-zoom view, the
// right presentation for a large dense chart. It is an ADDITION at the top, not
// a replacement: the drill-down (pick vendor -> line -> table) is intact, and it
// is decorative for screen readers (every fact is also in the tables the
// drill-down reaches). It is gated on the PNG actually being bundled
// (ReferenceImages.isBundled), so a missing asset degrades to just the
// drill-down and never a broken box.
//
// States (SOP-007 §5): local const data, nothing fetched, shelled out to, or
// fabricated (GL-008 does not apply — there is nothing to reach). So only the
// success and interactive states are reachable:
//   - success     → the compile-time const data always renders. The three views
//     (vendor picker / line picker / state table) are the success surface. The
//     comparison plate is a bundled-asset-gated success element on the picker.
//   - interactive → the picker rows and the back button carry the §8.3 lime
//     focus ring and are keyboard-reachable; the comparison plate is a labeled
//     tap-to-zoom target; the AppBar §8.16 copy action and the §8.16.1 help
//     footer each carry their own ring.
//   - loading / empty / error → not reachable; there is no async boundary and
//     the const dataset is never empty. A missing plate PNG is not an error
//     state — the card is simply omitted.
//   - disabled → copy is always enabled (the full reference is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The collision warning is a §8.13 warning band (warning_amber_rounded + text,
// never color-only); the caveat/defer are §8.13 info bands. Confidence markers
// are icon + word chips (never color-only).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

import 'package:flutter/material.dart';

import '../../../data/led_decoder_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_drilldown.dart';
import 'reference_prose.dart';

/// Asset id (under the convention-based [ReferenceImages] resolver) for the
/// Vera-passed master cross-vendor comparison plate — the whole color matrix on
/// one dense chart. Distinct from [kLedDecoderToolId]: the decoder tool is the
/// interactive drill-down; THIS is a single supporting overview plate the
/// picker shows at the top. Resolves to `assets/reference/led-master-comparison.png`.
const String kLedComparisonPlateId = 'led-master-comparison';

class LedDecoderScreen extends StatefulWidget {
  const LedDecoderScreen({super.key});

  @override
  State<LedDecoderScreen> createState() => _LedDecoderScreenState();
}

class _LedDecoderScreenState extends State<LedDecoderScreen> {
  /// The selected vendor, or null at the root vendor picker.
  String? _vendorId;

  /// The selected model line, or null before a line is chosen. Auto-resolved
  /// for a single-line vendor.
  String? _lineId;

  LedVendor? get _vendor {
    final String? id = _vendorId;
    if (id == null) return null;
    for (final LedVendor v in kLedVendors) {
      if (v.id == id) return v;
    }
    return null;
  }

  LedModelLine? get _line {
    final LedVendor? v = _vendor;
    final String? id = _lineId;
    if (v == null || id == null) return null;
    for (final LedModelLine l in v.lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  void _selectVendor(LedVendor v) {
    setState(() {
      _vendorId = v.id;
      // A single-line vendor resolves straight to its table; a note-only vendor
      // (MikroTik) has no line to resolve.
      _lineId = (v.lines.length == 1) ? v.lines.first.id : null;
    });
  }

  void _selectLine(LedModelLine l) => setState(() => _lineId = l.id);

  void _backToVendors() => setState(() {
        _vendorId = null;
        _lineId = null;
      });

  void _backToLines() => setState(() => _lineId = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LED Decoder'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return CenteredContent(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _viewChildren(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _viewChildren() {
    final LedVendor? vendor = _vendor;
    if (vendor == null) return _vendorPickerView();
    if (vendor.honestNote != null) return _honestNoteView(vendor);
    if (_line == null) return _linePickerView(vendor);
    return _lineDetailView(vendor, _line!);
  }

  // ─────────────────────────── view: vendor picker ──────────────────────────

  List<Widget> _vendorPickerView() {
    final List<LedVendor> enterprise = kLedVendors
        .where((LedVendor v) => v.vendorClass == LedVendorClass.enterprise)
        .toList();
    final List<LedVendor> consumer = kLedVendors
        .where((LedVendor v) => v.vendorClass == LedVendorClass.consumer)
        .toList();

    final Widget? plate = _comparisonPlate();
    // The master comparison plate is also offered as a "Download PDF" (save/
    // share) right on the comparison card at the top of the picker, via the same
    // seam the PDF reference cards use. Gated independently of the PNG so the
    // download degrades separately from the inline plate.
    final bool hasComparisonPdf =
        ReferencePdfs.isBundled(kLedComparisonPlateId);

    return <Widget>[
      const ReferenceLead(kLedLead),
      const SizedBox(height: AppSpacing.md),
      const ReferenceWarnBand(kLedCollisionWarning),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedStandingCaveat),
      const SizedBox(height: AppSpacing.md),
      // The cross-vendor overview plate at the head of the list — an addition
      // above the drill-down, shown when the PNG and/or the download PDF exist.
      if (plate != null || hasComparisonPdf) ...<Widget>[
        _sectionLabel('Cross-vendor comparison'),
        const SizedBox(height: AppSpacing.xs),
        ?plate,
        if (plate != null && hasComparisonPdf)
          const SizedBox(height: AppSpacing.sm),
        if (hasComparisonPdf)
          ReferencePdfDownloadCard(
            assetPath: ReferencePdfs.pathFor(kLedComparisonPlateId),
            title: 'LED Decoder',
            subtitle: 'Save or share the cross-vendor comparison plate',
          ),
        const SizedBox(height: AppSpacing.md),
      ],
      _sectionLabel('Enterprise'),
      const SizedBox(height: AppSpacing.xs),
      ..._vendorRows(enterprise),
      const SizedBox(height: AppSpacing.md),
      _sectionLabel('Consumer mesh'),
      const SizedBox(height: AppSpacing.xs),
      ..._vendorRows(consumer),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedDeferNote),
      ToolHelpFooter(toolId: kLedDecoderToolId),
    ];
  }

  List<Widget> _vendorRows(List<LedVendor> vendors) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < vendors.length; i++) {
      final LedVendor v = vendors[i];
      if (i > 0) rows.add(const SizedBox(height: AppSpacing.xs));
      final String? trailing = v.honestNote != null
          ? 'Note only'
          : v.hasMultipleLines
              ? '${v.lines.length} lines'
              : null;
      rows.add(
        ReferencePickerRow(
          title: v.name,
          subtitle: v.honestNote != null
              ? 'No standardized LED scheme'
              : v.hasMultipleLines
                  ? 'Forks by management line'
                  : null,
          trailingLabel: trailing,
          onTap: () => _selectVendor(v),
        ),
      );
    }
    return rows;
  }

  // ─────────────────── cross-vendor comparison plate (top) ───────────────────

  /// True aspect ratio (width / height) of the master comparison PNG, pinned so
  /// the inline card is the right shape with no letterbox gutters. Matches the
  /// real asset dims (3760 x 3368).
  static const double _comparisonPlateAspect = 3760 / 3368;

  /// The Vera-passed master cross-vendor comparison plate, or null when the PNG
  /// is not bundled (the resolver gate keeps a missing asset from ever reaching
  /// Image.asset, so the drill-down still reads end-to-end). Mounted in the
  /// established DarkRasterDiagramCard: a tap-to-zoom, always-dark plate that
  /// opens the full-screen pinch-zoom view — the right presentation for a large,
  /// dense chart. Decorative for screen readers (every fact is also in the
  /// per-vendor tables the drill-down reaches).
  Widget? _comparisonPlate() {
    if (!ReferenceImages.isBundled(kLedComparisonPlateId)) return null;
    return DarkRasterDiagramCard(
      assetPath: ReferenceImages.pathFor(kLedComparisonPlateId),
      aspectRatio: _comparisonPlateAspect,
      semanticLabel: 'cross-vendor LED comparison chart',
      caption: 'See the full cross-vendor comparison on one chart.',
    );
  }

  // ─────────────────────────── view: line picker ────────────────────────────

  List<Widget> _linePickerView(LedVendor vendor) {
    return <Widget>[
      ReferenceBackButton(label: 'All vendors', onTap: _backToVendors),
      const SizedBox(height: AppSpacing.sm),
      _detailHeading(vendor.name, 'Pick the model line'),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedStandingCaveat),
      const SizedBox(height: AppSpacing.md),
      for (int i = 0; i < vendor.lines.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: AppSpacing.xs),
        ReferencePickerRow(
          title: vendor.lines[i].name,
          subtitle: vendor.lines[i].blurb,
          onTap: () => _selectLine(vendor.lines[i]),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedDeferNote),
      ToolHelpFooter(toolId: kLedDecoderToolId),
    ];
  }

  // ──────────────────────────── view: line detail ───────────────────────────

  List<Widget> _lineDetailView(LedVendor vendor, LedModelLine line) {
    // Back target: a multi-line vendor returns to its line picker; a
    // single-line vendor returns to the vendor picker.
    final Widget back = vendor.hasMultipleLines
        ? ReferenceBackButton(label: '${vendor.name} lines', onTap: _backToLines)
        : ReferenceBackButton(label: 'All vendors', onTap: _backToVendors);

    return <Widget>[
      back,
      const SizedBox(height: AppSpacing.sm),
      _detailHeading(vendor.name, line.name),
      if (line.blurb != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        ReferenceBody(line.blurb!),
      ],
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedStandingCaveat),
      const SizedBox(height: AppSpacing.md),
      ReferenceCard(
        title: 'LED states',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < line.rows.length; i++) ...<Widget>[
              if (i > 0) _rowDivider(),
              _LedStateRowView(row: line.rows[i]),
            ],
          ],
        ),
      ),
      if (line.extraNote != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        ReferenceCard(child: ReferenceBody(line.extraNote!)),
      ],
      if (line.source != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        _sourceLine(line.source!),
      ],
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedDeferNote),
      ToolHelpFooter(toolId: kLedDecoderToolId),
    ];
  }

  // ─────────────────────────── view: honest note ────────────────────────────

  List<Widget> _honestNoteView(LedVendor vendor) {
    return <Widget>[
      ReferenceBackButton(label: 'All vendors', onTap: _backToVendors),
      const SizedBox(height: AppSpacing.sm),
      _detailHeading(vendor.name, 'No standardized status LEDs'),
      const SizedBox(height: AppSpacing.md),
      ReferenceCard(child: ReferenceBody(vendor.honestNote!)),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedDeferNote),
      ToolHelpFooter(toolId: kLedDecoderToolId),
    ];
  }

  // ───────────────────────────── small helpers ──────────────────────────────

  Widget _sectionLabel(String label) {
    return Builder(
      builder: (BuildContext context) {
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        return Text(
          label,
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        );
      },
    );
  }

  Widget _detailHeading(String vendor, String line) {
    return Builder(
      builder: (BuildContext context) {
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              vendor,
              style: text.labelMedium?.copyWith(
                color: colors.textAccent,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              line,
              style: (text.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _rowDivider() {
    return Builder(
      builder: (BuildContext context) => Divider(
        color: context.colors.border,
        height: AppSpacing.md,
      ),
    );
  }

  Widget _sourceLine(String source) {
    return Builder(
      builder: (BuildContext context) {
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        return Text(
          'Source: $source',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        );
      },
    );
  }

  // ─────────────────────────────── copy (§8.16) ─────────────────────────────

  /// §8.16 plain-text payload — the FULL cross-vendor reference, so a field tech
  /// copies the whole decoder regardless of the current drill-down position.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('AP Status-LED Decoder (cross-vendor)')
      ..writeln()
      ..writeln(kLedLead)
      ..writeln()
      ..writeln(kLedCollisionWarning)
      ..writeln()
      ..writeln(kLedStandingCaveat);
    for (final LedVendor v in kLedVendors) {
      b
        ..writeln()
        ..writeln('== ${v.name} '
            '(${v.vendorClass == LedVendorClass.consumer ? 'consumer' : 'enterprise'}) ==');
      if (v.honestNote != null) {
        b.writeln(v.honestNote);
        continue;
      }
      // The confidence column is a debug-only QA taxonomy, gated with the
      // chips (§ debugShowLedConfidenceChips). The honest disclosure the user
      // needs is already carried by the Signal/Meaning columns (the
      // kLabConfirmMarker text and the "no distinct signal" notes), so a
      // release copy stays fully honest without the QA stamp.
      final bool withConfidence = debugShowLedConfidenceChips;
      for (final LedModelLine l in v.lines) {
        b
          ..writeln()
          ..writeln('- ${l.name}');
        if (l.blurb != null) b.writeln(l.blurb);
        b.writeln(<String>[
          'State',
          'Signal',
          'Meaning',
          if (withConfidence) 'Confidence',
        ].join(tab));
        for (final LedStateRow r in l.rows) {
          b.writeln(<String>[
            r.state,
            r.signal,
            r.meaning,
            if (withConfidence) _confidenceWord(r.confidence),
          ].join(tab));
        }
        if (l.extraNote != null) b.writeln(l.extraNote);
        if (l.source != null) b.writeln('Source: ${l.source}');
      }
    }
    b
      ..writeln()
      ..writeln(kLedDeferNote);
    return b.toString().trimRight();
  }
}

/// Plain word for a confidence marker (used in the copy payload and the chip).
String _confidenceWord(LedConfidence c) {
  switch (c) {
    case LedConfidence.confirmed:
      return 'Confirmed';
    case LedConfidence.byDesign:
      return 'By design';
    case LedConfidence.labConfirm:
      return 'Lab-confirm';
  }
}

/// One rendered LED state row: the state name, its signal (or the honest
/// lab-confirm marker), the meaning, and a confidence chip. Collapsed into one
/// semantic node so a screen reader hears "State. Signal. Meaning. Confidence".
class _LedStateRowView extends StatelessWidget {
  const _LedStateRowView({required this.row});

  final LedStateRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool labConfirm = row.confidence == LedConfidence.labConfirm;

    // The confidence chip (and its semantics phrase) is a DEBUG-ONLY QA marker
    // (Keith-directed 2026-07-05): it shows while testing a debug build and
    // never ships in release. The user-facing honesty is unaffected — the
    // signal text (incl. kLabConfirmMarker) and the LedColor.unknown "?" glyph
    // on undocumented rows stay visible in both build modes.
    final bool showChip = debugShowLedConfidenceChips;

    final String semantics = showChip
        ? '${row.state}. ${row.signal}. ${row.meaning}. '
            '${_confidenceWord(row.confidence)}.'
        : '${row.state}. ${row.signal}. ${row.meaning}.';

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  row.state,
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showChip) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _ConfidenceChip(confidence: row.confidence),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The signal line, LED-BALL FIRST: the literal colored indicator(s)
          // lead the verbatim signal text. The dot is never the only signal —
          // the color name is in the text beside it (GL-003 §8.13 / WCAG 1.4.1).
          // For a lab-confirm row the signal is the honest marker, rendered in
          // the caution tone and italic; its glyph is the neutral "?" (no
          // fabricated color, GL-005).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _LedIndicatorCluster(indicators: row.indicators),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  row.signal,
                  style: (text.bodySmall ?? const TextStyle()).copyWith(
                    color: labConfirm
                        ? colors.statusWarning
                        : colors.textSecondary,
                    fontStyle: labConfirm ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            row.meaning,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// A confidence marker chip: an icon + word, never color-only (§8.13 rule 2).
///   - Confirmed  → success tone + check
///   - By design  → info tone + tune glyph (a deliberate design choice, not a
///     gap)
///   - Lab-confirm → warning tone + warning glyph (not documented, confirm on a
///     lab AP)
class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final LedConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final Color tone;
    final Color fill;
    final IconData glyph;
    switch (confidence) {
      case LedConfidence.confirmed:
        tone = colors.statusSuccess;
        fill = colors.statusSuccessFill;
        glyph = Icons.check_circle_outline;
        break;
      case LedConfidence.byDesign:
        tone = colors.statusInfo;
        fill = colors.statusInfoFill;
        glyph = Icons.tune;
        break;
      case LedConfidence.labConfirm:
        tone = colors.statusWarning;
        fill = colors.statusWarningFill;
        glyph = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tone, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(glyph, size: 14, color: tone),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            _confidenceWord(confidence),
            style: text.labelSmall?.copyWith(
              color: tone,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── literal LED indicator glyphs ─────────────────────
//
// The colored "ball" per state. GL-003 governance:
//   * The dot COLORS are literal light hues (green/amber/red/blue/white/purple/
//     magenta) under the §8.15 case-1 / §8.6.2 canonical-color exception — the
//     color IS the data, the same clause as the T568A/B wire colors and the
//     TIA-598-C fiber jacket swatches. The §8.13 status palette is deliberately
//     NOT reused (rule 6 bars status hues on indicator dots).
//   * The color is never the only signal: the signal text names the color in
//     words beside the dot (§8.13 / WCAG 1.4.1). The glyph is decorative and is
//     excluded from semantics.
//   * Perceptibility floor (SC 1.4.11, 3:1 on both canvases) is carried by the
//     theme-aware borderStrong RING on every dot, so a true white/amber fill
//     stays legible on a white card.
//   * Solid = a filled dot; flashing = a gentle ~1s opacity pulse. Under reduced
//     motion / MediaQuery.disableAnimations the pulse is dropped and a static
//     concentric HALO ring is drawn instead, so solid-vs-flashing still reads
//     without motion (§8.8). Off = a hollow grey ring; a by-design "no distinct
//     signal" = a neutral dash; an undocumented lab-confirm state = a neutral
//     hollow "?" (never a fabricated color, GL-005).

/// Diameter of a single LED "ball".
const double _kLedDotSize = 12;

/// Footprint reserved for each glyph — larger than the dot so the reduced-motion
/// halo ring never changes the row's layout between motion-on and reduced
/// motion. Solid and flashing glyphs occupy the same box.
const double _kLedGlyphBox = 20;

/// Blink loop period — a gentle ~1s opacity pulse (Keith-directed), an ambient
/// loop like [PacketFlowProgress], not a §8.8 transition token. Collapsed to a
/// static halo under reduced motion.
const Duration _kLedBlinkPeriod = Duration(milliseconds: 1000);

/// Maps a [LedColor] to its literal light hue, or null for the hollow / neutral
/// glyphs (off / none / unknown). Canonical subject-matter colors per §8.15
/// case-1 — NOT design tokens.
Color? _ledFill(LedColor c) {
  switch (c) {
    case LedColor.green:
      return const Color(0xFF3FB950);
    case LedColor.amber:
      return const Color(0xFFF5A623);
    case LedColor.red:
      return const Color(0xFFE5484D);
    case LedColor.blue:
      return const Color(0xFF2E90FA);
    case LedColor.white:
      return const Color(0xFFFFFFFF);
    case LedColor.purple:
      return const Color(0xFFA25DDC);
    case LedColor.magenta:
      return const Color(0xFFD6409F);
    case LedColor.off:
    case LedColor.none:
    case LedColor.unknown:
      return null;
  }
}

/// Renders the literal LED "ball(s)" for one state row. Owns a single ambient
/// pulse controller (started only when motion is allowed AND a dot flashes),
/// mirroring the [PacketFlowProgress] reduced-motion contract.
class _LedIndicatorCluster extends StatefulWidget {
  const _LedIndicatorCluster({required this.indicators});

  final List<LedIndicator> indicators;

  @override
  State<_LedIndicatorCluster> createState() => _LedIndicatorClusterState();
}

class _LedIndicatorClusterState extends State<_LedIndicatorCluster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kLedBlinkPeriod);
    // Never fully off — the dot stays perceivable; the pulse only reads as
    // "flashing". Dim floor 0.4 keeps the fill's hue legible mid-pulse.
    _pulse = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bool anyFlashing = widget.indicators
        .any((LedIndicator i) => i.blink == LedBlink.flashing);

    // A controller that never animates costs nothing per frame; run it only
    // when motion is allowed and something actually flashes.
    if (!reduceMotion && anyFlashing) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else if (_controller.isAnimating) {
      _controller.stop();
    }

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < widget.indicators.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.xxs),
                _LedGlyph(
                  indicator: widget.indicators[i],
                  colors: colors,
                  reduceMotion: reduceMotion,
                  pulseOpacity: _pulse.value,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One LED glyph within a [_LedIndicatorCluster].
class _LedGlyph extends StatelessWidget {
  const _LedGlyph({
    required this.indicator,
    required this.colors,
    required this.reduceMotion,
    required this.pulseOpacity,
  });

  final LedIndicator indicator;
  final AppColorScheme colors;
  final bool reduceMotion;
  final double pulseOpacity;

  @override
  Widget build(BuildContext context) {
    final Color ring = colors.borderStrong; // SC 1.4.11 floor carrier
    final Color? fill = _ledFill(indicator.color);
    final bool flashing = indicator.blink == LedBlink.flashing;

    final Widget core;
    if (indicator.color == LedColor.none) {
      // No distinct signal (by-design / confirmed-none): a neutral dash.
      core = Container(
        width: _kLedDotSize,
        height: 2,
        decoration: BoxDecoration(
          color: colors.textTertiary,
          borderRadius: BorderRadius.circular(1),
        ),
      );
    } else if (indicator.color == LedColor.unknown) {
      // Undocumented: a neutral hollow "?" — never a color (GL-005).
      core = Container(
        width: _kLedDotSize,
        height: _kLedDotSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 1.5),
        ),
        child: Text(
          '?',
          style: TextStyle(
            fontSize: 9,
            height: 1.0,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
      );
    } else if (fill == null) {
      // Off: a hollow grey ring.
      core = Container(
        width: _kLedDotSize,
        height: _kLedDotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 1.5),
        ),
      );
    } else {
      // A literal colored ball. The ring carries the SC 1.4.11 floor so the
      // true fill (incl. white / amber) stays legible on both canvases.
      core = Container(
        width: _kLedDotSize,
        height: _kLedDotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: ring, width: 1.0),
        ),
      );
    }

    // Flashing under motion → pulse the opacity; under reduced motion → a static
    // concentric halo instead (the solid-vs-flashing cue without motion, §8.8).
    final Widget shown = (flashing && !reduceMotion)
        ? Opacity(opacity: pulseOpacity, child: core)
        : core;
    final bool showHalo = flashing && reduceMotion;

    return SizedBox(
      width: _kLedGlyphBox,
      height: _kLedGlyphBox,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (showHalo)
            Container(
              key: const ValueKey<String>('led-flash-halo'),
              width: _kLedGlyphBox - 2,
              height: _kLedGlyphBox - 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.borderStrong.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
            ),
          shown,
        ],
      ),
    );
  }
}
