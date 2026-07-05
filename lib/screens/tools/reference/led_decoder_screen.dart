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
// States (SOP-007 §5): local const data, nothing fetched, shelled out to, or
// fabricated (GL-008 does not apply — there is nothing to reach). So only the
// success and interactive states are reachable:
//   - success     → the compile-time const data always renders. The three views
//     (vendor picker / line picker / state table) are the success surface.
//   - interactive → the picker rows and the back button carry the §8.3 lime
//     focus ring and are keyboard-reachable; the AppBar §8.16 copy action and
//     the §8.16.1 help footer each carry their own ring.
//   - loading / empty / error → not reachable; there is no async boundary and
//     the const dataset is never empty.
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
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_drilldown.dart';
import 'reference_prose.dart';

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

    return <Widget>[
      const ReferenceLead(kLedLead),
      const SizedBox(height: AppSpacing.md),
      const ReferenceWarnBand(kLedCollisionWarning),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kLedStandingCaveat),
      const SizedBox(height: AppSpacing.md),
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
      for (final LedModelLine l in v.lines) {
        b
          ..writeln()
          ..writeln('- ${l.name}');
        if (l.blurb != null) b.writeln(l.blurb);
        b.writeln(<String>['State', 'Signal', 'Meaning', 'Confidence'].join(tab));
        for (final LedStateRow r in l.rows) {
          b.writeln(
            <String>[r.state, r.signal, r.meaning, _confidenceWord(r.confidence)]
                .join(tab),
          );
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

    final String semantics =
        '${row.state}. ${row.signal}. ${row.meaning}. '
        '${_confidenceWord(row.confidence)}.';

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
              const SizedBox(width: AppSpacing.xs),
              _ConfidenceChip(confidence: row.confidence),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The signal line. For a lab-confirm row this is the honest marker,
          // rendered in the caution tone and italic — deliberately NOT a color
          // swatch, because the vendor documents none (GL-005).
          Text(
            row.signal,
            style: (text.bodySmall ?? const TextStyle()).copyWith(
              color: labConfirm ? colors.statusWarning : colors.textSecondary,
              fontStyle: labConfirm ? FontStyle.italic : FontStyle.normal,
            ),
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
