// Enterprise AP Model-Number Decoder (per vendor) — the INTERACTIVE drill-down
// reference screen (Field & Trade Reference set, 2026-07-05):
//
//   pick a vendor -> read that vendor's model-number scheme (what each segment
//   encodes) plus a worked example.
//
// Deliberately NOT a "paste a model number -> auto-decode" input (GL-005,
// load-bearing): several vendors (Extreme especially) do not digit-encode Wi-Fi
// generation / streams / antenna, so an auto-decoder would fabricate precision
// the SKU does not carry. The honest shape is a per-vendor schema plus the
// "confirm on the per-model datasheet" caveat where the content flags it. A
// warning band up front carries the "decode per-vendor, never a shared letter
// dictionary" rule (the E-letter collision).
//
// Renders vendor_model_decode_data.dart VERBATIM (Penn/Pax voice-gated,
// SOP-020 PASS; source
// Deliverables/2026-07-05-field-trade-reference/content/19-vendor-model-decode.md).
//
// States (SOP-007 §5): local const data, nothing fetched, shelled out to, or
// fabricated (GL-008 does not apply). Only success + interactive are reachable:
//   - success     → the const data always renders; the two views (vendor picker
//     / vendor detail) are the success surface.
//   - interactive → the picker rows and the back button carry the §8.3 lime
//     focus ring and are keyboard-reachable; the AppBar §8.16 copy action and
//     the §8.16.1 help footer each carry their own ring.
//   - loading / empty / error → not reachable (no async boundary; const data is
//     never empty).
//   - disabled → copy is always enabled (the full reference is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The honest-rule callout is a §8.13 warning band; the caveat/defer are info
// bands.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

import 'package:flutter/material.dart';

import '../../../data/vendor_model_decode_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_drilldown.dart';
import 'reference_prose.dart';

class VendorModelDecodeScreen extends StatefulWidget {
  const VendorModelDecodeScreen({super.key});

  @override
  State<VendorModelDecodeScreen> createState() =>
      _VendorModelDecodeScreenState();
}

class _VendorModelDecodeScreenState extends State<VendorModelDecodeScreen> {
  /// The selected vendor, or null at the vendor picker.
  String? _vendorId;

  DecodeVendor? get _vendor {
    final String? id = _vendorId;
    if (id == null) return null;
    for (final DecodeVendor v in kDecodeVendors) {
      if (v.id == id) return v;
    }
    return null;
  }

  void _selectVendor(DecodeVendor v) => setState(() => _vendorId = v.id);
  void _backToVendors() => setState(() => _vendorId = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Model Decode'),
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
                  children: _vendor == null
                      ? _vendorPickerView()
                      : _vendorDetailView(_vendor!),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────── view: vendor picker ──────────────────────────

  List<Widget> _vendorPickerView() {
    return <Widget>[
      const ReferenceLead(kDecodeLead),
      const SizedBox(height: AppSpacing.md),
      const ReferenceWarnBand(kDecodeHonestRule),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kDecodeStandingCaveat),
      const SizedBox(height: AppSpacing.md),
      for (int i = 0; i < kDecodeVendors.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: AppSpacing.xs),
        ReferencePickerRow(
          title: kDecodeVendors[i].name,
          subtitle: 'Confidence: ${kDecodeVendors[i].confidence}',
          onTap: () => _selectVendor(kDecodeVendors[i]),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      const ReferenceCard(child: ReferenceBody(kDecodeBacklogNote)),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kDecodeDeferNote),
      ToolHelpFooter(toolId: kVendorModelDecodeToolId),
    ];
  }

  // ─────────────────────────── view: vendor detail ──────────────────────────

  List<Widget> _vendorDetailView(DecodeVendor vendor) {
    return <Widget>[
      ReferenceBackButton(label: 'All vendors', onTap: _backToVendors),
      const SizedBox(height: AppSpacing.sm),
      _detailHeading(vendor.name, 'Confidence: ${vendor.confidence}'),
      const SizedBox(height: AppSpacing.sm),
      ReferenceBody(vendor.intro),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kDecodeStandingCaveat),
      const SizedBox(height: AppSpacing.md),
      ReferenceCard(
        title: 'Read the model left to right',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < vendor.tokens.length; i++) ...<Widget>[
              if (i > 0) _rowDivider(),
              _TokenRowView(token: vendor.tokens[i]),
            ],
          ],
        ),
      ),
      if (vendor.suffixMeanings.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        ReferenceCard(
          title: vendor.suffixTitle,
          child: ReferenceBullets(vendor.suffixMeanings),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      ReferenceCard(
        title: 'Worked example: ${vendor.exampleSku}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < vendor.exampleSteps.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _DecodeStepView(step: vendor.exampleSteps[i]),
            ],
            const SizedBox(height: AppSpacing.md),
            _readBack(vendor.readBack),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      ReferenceCard(
        title: 'Confidence and caveats',
        child: ReferenceBody(vendor.confidenceNote),
      ),
      const SizedBox(height: AppSpacing.md),
      const ReferenceInfoBand(kDecodeDeferNote),
      ToolHelpFooter(toolId: kVendorModelDecodeToolId),
    ];
  }

  // ───────────────────────────── small helpers ──────────────────────────────

  Widget _detailHeading(String vendor, String confidence) {
    return Builder(
      builder: (BuildContext context) {
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              vendor,
              style: (text.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              confidence,
              style: text.labelMedium?.copyWith(
                color: colors.textAccent,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _readBack(String readBack) {
    return Builder(
      builder: (BuildContext context) {
        final AppColorScheme colors = context.colors;
        final TextTheme text = Theme.of(context).textTheme;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Read-back',
                style: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                readBack,
                style: (text.bodyMedium ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
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

  // ─────────────────────────────── copy (§8.16) ─────────────────────────────

  /// §8.16 plain-text payload — the FULL per-vendor reference.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Enterprise AP Model-Number Decoder (per vendor)')
      ..writeln()
      ..writeln(kDecodeLead)
      ..writeln()
      ..writeln(kDecodeHonestRule)
      ..writeln()
      ..writeln(kDecodeStandingCaveat);
    for (final DecodeVendor v in kDecodeVendors) {
      b
        ..writeln()
        ..writeln('== ${v.name} (Confidence: ${v.confidence}) ==')
        ..writeln(v.intro)
        ..writeln(<String>['Token', 'Encodes', 'Example'].join(tab));
      for (final ModelToken t in v.tokens) {
        b.writeln(<String>[t.token, t.encodes, t.example].join(tab));
      }
      if (v.suffixMeanings.isNotEmpty) {
        b.writeln(v.suffixTitle ?? 'Suffix meanings');
        for (final String s in v.suffixMeanings) {
          b.writeln('- $s');
        }
      }
      b.writeln('Worked example: ${v.exampleSku}');
      for (final DecodeStep s in v.exampleSteps) {
        b.writeln('- ${s.segment}: ${s.meaning}');
      }
      b
        ..writeln('Read-back: ${v.readBack}')
        ..writeln(v.confidenceNote);
    }
    b
      ..writeln()
      ..writeln(kDecodeBacklogNote)
      ..writeln()
      ..writeln(kDecodeDeferNote);
    return b.toString().trimRight();
  }
}

/// One token -> encodes -> example row.
class _TokenRowView extends StatelessWidget {
  const _TokenRowView({required this.token});

  final ModelToken token;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${token.token}. ${token.encodes}. Example: ${token.example}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            token.token,
            style: mono.inlineCode.copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            token.encodes,
            style: (text.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Example: ${token.example}',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One worked-example step: a mono segment chip then its meaning.
class _DecodeStepView extends StatelessWidget {
  const _DecodeStepView({required this.step});

  final DecodeStep step;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;

    // Stacked (chip above meaning) rather than side-by-side, so a long segment
    // label (e.g. Extreme's "Wi-Fi gen / streams / antenna") wraps cleanly and
    // never forces a horizontal overflow at 320px.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${step.segment}: ${step.meaning}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(minWidth: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: colors.border, width: 1),
              ),
              child: Text(
                step.segment,
                style: mono.inlineCode.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            step.meaning,
            style: (text.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
