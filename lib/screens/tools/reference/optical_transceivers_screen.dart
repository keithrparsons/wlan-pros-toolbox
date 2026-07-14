// Optical Transceivers — an offline reference of optical Ethernet transceiver
// variants (1G–400G) grouped by speed tier, plus the SFP→OSFP form-factor
// ladder. Clones the data-driven Port Reference pattern (bundled JSON asset →
// pure service → search/group → render).
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner with an AT
//    announcement.
//  - error   → the bundled asset failed to load or parse (should not happen in a
//    shipped build); shown via the shared message card.
//  - success → matching tiers + the form-factor table render.
//  - empty   → a query that matches nothing; an honest "no match" card, never a
//    fabricated row.
//
// HONESTY (GL-005 / Pax brief): IEEE-ratified variants get a neutral IEEE chip;
// vendor / coherent variants (ZR/ZX/EX, 400G-ZR coherent DWDM) get an amber
// VENDOR chip + the verbatim "loss-budget dependent" caveat rendered in the §8.13
// warning token (amber in dark, bronze in light per §8.20.1). Vendor reach is
// never presented as an IEEE-guaranteed figure.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw AppColors.* — so the screen renders correctly in both
// dark (§8) and light (§8.20). No new tokens introduced.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../data/tool_assets.dart';
import '../../../services/network/optical_transceiver_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the icon/graphic assets, the help
/// entry, and the tests.
const String kOpticalTransceiversToolId = 'optical-transceivers';

/// Asset path for the bundled optical-transceiver table. Overridable in tests so
/// a fixture string can stand in for the bundled asset.
const String kOpticalTransceiversAsset = 'assets/data/optical_transceivers.json';

class OpticalTransceiversScreen extends StatefulWidget {
  const OpticalTransceiversScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final OpticalTransceiverService? service;

  @override
  State<OpticalTransceiversScreen> createState() =>
      _OpticalTransceiversScreenState();
}

class _OpticalTransceiversScreenState extends State<OpticalTransceiversScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  OpticalTransceiverService? _service;
  String? _loadError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service;
    } else {
      _loadAsset();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    try {
      final String raw = await rootBundle.loadString(kOpticalTransceiversAsset);
      final OpticalTransceiverService svc =
          OpticalTransceiverService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _loadError = 'Could not load the optical transceiver table: $e',
      );
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // WCAG 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final OpticalTransceiverService? svc = _service;
    if (svc == null) return;
    final int n = svc
        .search(value)
        .fold<int>(0, (int sum, OpticalTier t) => sum + t.entries.length);
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching transceivers' : '$n matching transceiver${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optical Transceivers'),
        toolbarHeight: 64,
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: kOpticalTransceiversToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kOpticalTransceiversToolId))
                    const SizedBox(height: AppSpacing.md),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _content(context),
                  ToolHelpFooter(toolId: kOpticalTransceiversToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool ready = _service != null;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Search',
        hint: 'designation, reach, fiber, wavelength',
        semanticLabel:
            'Search transceivers by designation, reach, fiber, or wavelength',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          enabled: ready,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(
            hintText: 'e.g. SR, LR4, 100G, or 850 nm',
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loadError != null) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Reference unavailable',
        body: _loadError!,
      );
    }

    final OpticalTransceiverService? svc = _service;
    if (svc == null) {
      return _LoadingCard(label: 'Loading optical transceiver table');
    }

    final List<OpticalTier> tiers = svc.search(_query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _Legend(),
        const SizedBox(height: AppSpacing.md),
        _SectionHeading(label: 'Optical variants · by speed tier'),
        const SizedBox(height: AppSpacing.xs),
        if (tiers.isEmpty)
          _MessageCard(
            icon: Icons.search_off,
            title: 'No match',
            body: 'No transceiver matches "${_query.trim()}".',
          )
        else
          ...tiers.map((OpticalTier t) => _TierBlock(tier: t)),
        // The form-factor ladder is a fixed companion table — always shown in
        // full (it is not part of the variant search), so a search that hides
        // tiers still leaves the form-factor reference available.
        //
        // THE BUG THIS FIXES: the guard used to read
        //   `if (!filtering || tiers.isNotEmpty)`
        // which HID this table on exactly the case the comment promises it
        // survives — a filtering search with no tier match. The comment above
        // said "always shown in full"; the code beneath it did the opposite.
        // It is now unconditional, which is what the comment always claimed.
        const SizedBox(height: AppSpacing.lg),
        _SectionHeading(label: 'Form factors · SFP → OSFP'),
        const SizedBox(height: AppSpacing.xs),
        _FormFactorTable(rows: svc.formFactors),
      ],
    );
  }
}

/// The §8.16-style legend explaining REACH, VENDOR, and the fiber chips.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
          _legendRow(
            context,
            const _ReachChip(),
            'IEEE maximum on the listed fiber. This is the number to trust first.',
          ),
          const SizedBox(height: AppSpacing.xs),
          _legendRow(
            context,
            const _VendorChip(),
            'Not IEEE-ratified; reach depends on the link loss budget.',
          ),
          const SizedBox(height: AppSpacing.xs),
          _legendRow(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                _FiberChip(label: 'MMF', kind: OpticalFiberKind.mmf),
                SizedBox(width: AppSpacing.xs),
                _FiberChip(label: 'SMF', kind: OpticalFiberKind.smf),
              ],
            ),
            'Multimode (OM grade) vs single-mode (OS2).',
          ),
        ],
      ),
    );
  }

  Widget _legendRow(BuildContext context, Widget lead, String text) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        lead,
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A speed-tier block: the tier header (badge + form factor + optional
/// "Commonly ordered" flag + count) and its variant cards.
class _TierBlock extends StatelessWidget {
  const _TierBlock({required this.tier});

  final OpticalTier tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TierHeader(tier: tier),
          const SizedBox(height: AppSpacing.xs),
          ...tier.entries.map((OpticalVariant v) => _ModuleCard(variant: v)),
        ],
      ),
    );
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier});

  final OpticalTier tier;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          // Lime tier badge (fill + onPrimary text — lime as a FILL, valid in
          // both themes per §8.20.2).
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              tier.tier,
              style: (t.labelMedium ?? const TextStyle()).copyWith(
                color: colors.onPrimary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // The form-factor label can be long ("QSFP-DD / OSFP"); let it shrink
          // with an ellipsis on narrow phones rather than overflow the header.
          Flexible(
            child: Text(
              tier.formFactor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: t.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (tier.lead) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            const _LeadFlag(),
          ],
          const SizedBox(width: AppSpacing.xs),
          // The divider takes remaining space but yields it first when the
          // header is tight (min width 0 so the flex resolves on narrow phones).
          Expanded(child: Divider(color: colors.border, height: 1)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${tier.entries.length}',
            style: t.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// "COMMONLY ORDERED" pill on the lead tiers — outlined in the foreground-lime
/// accent (textAccent), which is safe as a thin line/text in both themes.
class _LeadFlag extends StatelessWidget {
  const _LeadFlag();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.textAccent, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'COMMONLY ORDERED',
        style: (t.labelSmall ?? const TextStyle()).copyWith(
          color: colors.textAccent,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// One variant card: designation + IEEE/VENDOR chip, the prominent reach line
/// (with amber caveat for vendor rows), the fiber/λ/connector spec grid, and the
/// note. Vendor cards carry an amber left border (status-bearing accent).
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.variant});

  final OpticalVariant variant;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool vendor = variant.vendor;
    // §8.20.3: a status-bearing left accent is a filled AREA, so warning/amber
    // (statusWarning) is valid as a fill in both themes. It is drawn as a
    // separate left strip inside a clipped rounded card — a non-uniform Border
    // (a differently-colored left side) cannot coexist with a borderRadius in
    // Flutter, so the accent is a sibling fill, not a border side. Light bumps
    // the strip wider for legibility. The amber strip is reinforced by the
    // VENDOR chip + caveat (never color-only meaning).
    final double accentWidth = colors.isLight ? 4 : 3;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      // The amber vendor strip is a full-height left fill drawn via Positioned
      // (NOT a non-uniform Border, which can't coexist with a borderRadius, and
      // NOT an IntrinsicHeight Row, which cannot contain the spec-grid's
      // LayoutBuilder). The Stack sizes to the card body; the strip fills its
      // left edge top-to-bottom.
      child: Stack(
        children: <Widget>[
          _cardBody(context, colors, t, leadingInset: vendor ? accentWidth : 0),
          if (vendor)
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: Container(width: accentWidth, color: colors.statusWarning),
            ),
        ],
      ),
    );
  }

  Widget _cardBody(
    BuildContext context,
    AppColorScheme colors,
    TextTheme t, {
    double leadingInset = 0,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm + leadingInset,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Designation + chip.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  variant.designation,
                  style: (t.titleMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontFamily: 'DM Mono',
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              variant.vendor ? const _VendorChip() : const _IeeeChip(),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Reach — the prominent, trust-first line.
          _ReachLine(variant: variant),
          const SizedBox(height: AppSpacing.xs),
          // Spec grid: fiber / wavelength / connector. Each item is capped to the
          // card's inner width so a long value shrinks within the card rather
          // than overflowing the Wrap run on a 320px phone.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double itemMax = c.maxWidth;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _SpecItem(
                    label: 'Fiber',
                    maxWidth: itemMax,
                    child: _FiberChip(
                      label: variant.fiber,
                      kind: variant.fiberKind,
                    ),
                  ),
                  _SpecItem(
                    label: 'λ',
                    maxWidth: itemMax,
                    child: Text(
                      variant.wavelength,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (t.bodySmall ?? const TextStyle()).copyWith(
                        color: colors.textSecondary,
                        fontFamily: 'DM Mono',
                      ),
                    ),
                  ),
                  _SpecItem(
                    label: 'Conn',
                    maxWidth: itemMax,
                    child: _ConnectorChip(
                      label: variant.connector,
                      kind: variant.connectorKind,
                    ),
                  ),
                ],
              );
            },
          ),
          if (variant.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              variant.notes,
              style: t.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The reach line: a small REACH label + the value, then (for vendor rows) the
/// amber loss-budget caveat — preserved verbatim, rendered in the warning token.
class _ReachLine extends StatelessWidget {
  const _ReachLine({required this.variant});

  final OpticalVariant variant;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        const _ReachChip(),
        Text(
          variant.reach,
          style: (t.bodyMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (variant.vendor && variant.reachCaveat.isNotEmpty)
          Text(
            variant.reachCaveat,
            style: (t.bodySmall ?? const TextStyle()).copyWith(
              color: colors.statusWarning,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

/// The small "REACH" label chip — outlined in the foreground-lime accent.
class _ReachChip extends StatelessWidget {
  const _ReachChip();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.textAccent, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'REACH',
        style: (t.labelSmall ?? const TextStyle()).copyWith(
          color: colors.textAccent,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Neutral "IEEE" chip — outlined in the strong border, tertiary text. Carries
/// no verdict color (an IEEE-ratified variant is the baseline, not a warning).
class _IeeeChip extends StatelessWidget {
  const _IeeeChip();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: 'IEEE ratified',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderStrong, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'IEEE',
          style: (t.labelSmall ?? const TextStyle()).copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Amber "VENDOR" chip — the §8.13 warning verdict (amber in dark, bronze in
/// light). Always paired with text (never color-only) and reinforced by the
/// loss-budget caveat on the reach line.
class _VendorChip extends StatelessWidget {
  const _VendorChip();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: 'Vendor variant, not IEEE ratified',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.statusWarning, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'VENDOR',
          style: (t.labelSmall ?? const TextStyle()).copyWith(
            color: colors.statusWarning,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A fiber chip (MMF/SMF/mixed). The label always carries the fact; the outline
/// is a neutral category aid (never color-only meaning).
class _FiberChip extends StatelessWidget {
  const _FiberChip({required this.label, required this.kind});

  final String label;
  final OpticalFiberKind kind;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (t.bodySmall ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
          fontFamily: 'DM Mono',
        ),
      ),
    );
  }
}

/// A connector chip (LC / MPO). MPO (parallel) reads slightly stronger.
class _ConnectorChip extends StatelessWidget {
  const _ConnectorChip({required this.label, required this.kind});

  final String label;
  final OpticalConnectorKind kind;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool mpo = kind == OpticalConnectorKind.mpo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (t.bodySmall ?? const TextStyle()).copyWith(
          color: mpo ? colors.textPrimary : colors.textSecondary,
          fontFamily: 'DM Mono',
        ),
      ),
    );
  }
}

/// A labeled spec item: an uppercase key and its value/chip. [maxWidth] is the
/// card's inner content width — the item is capped to it so a long value (a wide
/// fiber chip or a verbose WDM wavelength) shrinks/wraps within the card instead
/// of overflowing the Wrap run on a 320px phone.
class _SpecItem extends StatelessWidget {
  const _SpecItem({
    required this.label,
    required this.child,
    required this.maxWidth,
  });

  final String label;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// The form-factor ladder table (SFP → OSFP).
class _FormFactorTable extends StatelessWidget {
  const _FormFactorTable({required this.rows});

  final List<OpticalFormFactor> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _FormFactorRow.header(),
          ...List<Widget>.generate(rows.length, (int i) {
            return _FormFactorRow(
              row: rows[i],
              isLast: i == rows.length - 1,
            );
          }),
        ],
      ),
    );
  }
}

class _FormFactorRow extends StatelessWidget {
  const _FormFactorRow({required this.row, required this.isLast})
      : isHeader = false;

  const _FormFactorRow.header()
      : row = null,
        isLast = false,
        isHeader = true;

  final OpticalFormFactor? row;
  final bool isLast;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;

    Widget cell(String text, int flex,
        {bool mono = false, bool name = false, bool head = false}) {
      final TextStyle base = head
          ? (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            )
          : name
              ? (t.bodySmall ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                )
              : (t.bodySmall ?? const TextStyle()).copyWith(
                  color: colors.textSecondary,
                  fontFamily: mono ? 'DM Mono' : null,
                );
      return Expanded(
        flex: flex,
        // maxLines + ellipsis keeps each flex cell inside its allotted box so a
        // sub-pixel flex-rounding remainder clips instead of overflowing the row
        // on the 320px phone surface.
        child: Text(
          head ? text.toUpperCase() : text,
          style: base,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final OpticalFormFactor? r = row;
    return Container(
      decoration: BoxDecoration(
        color: isHeader ? colors.surface2 : colors.surface1,
        border: isHeader || !isLast
            ? Border(bottom: BorderSide(color: colors.border, width: 1))
            : null,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.rowPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: isHeader
            ? <Widget>[
                cell('Module', 13, head: true),
                cell('Max rate', 10, head: true),
                cell('Lanes', 9, head: true),
                cell('Power', 9, head: true),
              ]
            : <Widget>[
                cell(r!.formFactor, 13, name: true),
                cell(r.maxRate, 10, mono: true),
                cell(r.lanes, 9, mono: true),
                cell(r.power, 9, mono: true),
              ],
      ),
    );
  }
}

/// A section heading with a short lime underbar accent.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: (t.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 38,
            height: 3,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Semantics(
            label: label,
            liveRegion: true,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textAccent,
            ),
          ),
        ),
      ),
    );
  }
}

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
        children: <Widget>[
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
