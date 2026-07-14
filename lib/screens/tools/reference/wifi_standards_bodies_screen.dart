// Wi-Fi Standards & Industry Bodies — reference screen.
//
// Teaches the three-layer model first, then lists the bodies GROUPED BY LAYER
// (not alphabetically). The whole reason the page exists: people conflate the
// standards body (defines how the radio works), the certification body (verifies
// products interoperate), and the regulator (sets the legal channel / power
// rules per country). A lead callout restates the sharpest confusion: IEEE
// writes 802.11; the Wi-Fi Alliance certifies and brands it — they are NOT the
// same — and "Wi-Fi" is a Wi-Fi Alliance TRADEMARK, not an acronym and not
// "Wireless Fidelity."
//
// CROSS-LINK: the regulator layer is a pointer to the existing Regulatory
// Domains page (single source of truth). This page does NOT restate FCC / Ofcom
// / ETSI-bloc national rules. ETSI appears here as a STANDARDS body, noted as
// also the EU's referenced harmonizer.
//
// PATTERN: mirrors regulatory_domains_screen.dart (search-as-you-type, tappable
// official-website links via url_launcher with an honest launch-error state,
// per-body logo slot with a name/abbreviation badge fallback gated on the asset
// manifest).
//
// STATES (SOP-007 §5): the dataset is a compile-time const, so there is no
// loading / fetch / parse path — `success` (the full list or a filtered subset)
// and `empty` (a query that matches nothing) are the only states. The per-tile
// website launch carries its own honest error state when the browser hand-off
// fails (the URL stays readable). GL-008: HTTPS browser hand-off, no in-app
// cleartext fetch, no subprocess.
//
// DESIGN: context.colors tokens only (theme-aware, light + dark); DM Mono
// (AppMonoText.inlineCode) for the abbreviation and the website URL identifier;
// §8.3 lime focus ring inherited from the theme on the tappable links.
//
// Glyph hygiene (GL-004): "Wi-Fi" never "WiFi"; "802.1X" never "802.1x"; ASCII
// hyphen-minus, no em dash; US spelling.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/wifi_bodies_data.dart';
import '../../../data/wifi_bodies_logos.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';

class WifiStandardsBodiesScreen extends StatefulWidget {
  const WifiStandardsBodiesScreen({
    super.key,
    this.bodies = kWifiBodies,
    this.launcher,
    this.onOpenRegulatoryDomains,
  });

  /// The records to render. Defaults to the bundled dataset; injectable so a
  /// widget test can pump a small fixture without depending on the full set.
  final List<WifiBody> bodies;

  /// Injectable URL opener for tests. Defaults to [launchUrl]
  /// (externalApplication). Returns whether the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  /// Optional hook to navigate to the Regulatory Domains page from the
  /// cross-link card. Larry wires the real route centrally; null here keeps the
  /// card informative (it still names the page) without a dangling navigation.
  final VoidCallback? onOpenRegulatoryDomains;

  /// Stable catalog id — backs the route and the help entry.
  static const String toolId = 'wifi-standards-bodies';

  @override
  State<WifiStandardsBodiesScreen> createState() =>
      _WifiStandardsBodiesScreenState();
}

class _WifiStandardsBodiesScreenState extends State<WifiStandardsBodiesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// The records matching the active query (substring over name + abbreviation +
  /// role + what-they-own + why-care). Empty query → all bodies.
  List<WifiBody> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.bodies;
    return widget.bodies
        .where((WifiBody b) => b.searchHaystack.contains(q))
        .toList(growable: false);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // SC 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final int n = _filtered.length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching bodies' : '$n matching ${n == 1 ? 'body' : 'bodies'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the teaching frame, then one TSV line per body grouped
  /// by layer, then the regulator-layer pointer.
  String _copyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Wi-Fi Standards & Industry Bodies')
      ..writeln(
        'Three layers: standards bodies define how the radio works; '
        'certification bodies verify products interoperate; regulators set the '
        'legal channel and power rules per country.',
      )
      ..writeln(
        'IEEE writes 802.11. The Wi-Fi Alliance certifies and brands it (not '
        'the same body). "Wi-Fi" is a Wi-Fi Alliance trademark, not an acronym '
        'and not "Wireless Fidelity."',
      )
      ..writeln()
      ..writeln(
        <String>['Body', 'Abbreviation', 'Role', 'What they own', 'Why a Wi-Fi pro cares', 'Website']
            .join(tab),
      );
    for (final BodyLayer layer in BodyLayer.values) {
      final List<WifiBody> inLayer =
          widget.bodies.where((WifiBody b) => b.layer == layer).toList();
      if (inLayer.isEmpty) continue;
      buf
        ..writeln()
        ..writeln(BodyLayerInfo.of(layer).title.toUpperCase());
      for (final WifiBody b in inLayer) {
        buf.writeln(
          <String>[
            b.contextOnly ? '${b.name} (context only)' : b.name,
            b.abbreviation,
            b.roleType,
            b.owns,
            b.whyCare,
            b.websiteUrl,
          ].join(tab),
        );
      }
    }
    buf
      ..writeln()
      ..writeln(
        'Regulates per country: see the Regulatory Domains reference for the '
        'national spectrum regulators (FCC, Ofcom, the ETSI-aligned EU bloc, '
        'and others).',
      );
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Standards Bodies'),
        toolbarHeight: 64,
        // §8.16 — copy the teaching frame + every body as TSV. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return CenteredContent(child: _body(edge));
          },
        ),
      ),
    );
  }

  Widget _body(double edge) {
    final List<WifiBody> rows = _filtered;
    final bool filtering = _query.trim().isNotEmpty;

    final List<Widget> children = <Widget>[
      const _ThreeLayerCallout(),
      const SizedBox(height: AppSpacing.sm),
      const _TrademarkCallout(),
      const SizedBox(height: AppSpacing.sm),
      _SearchField(controller: _queryCtrl, onChanged: _onQueryChanged),
      const SizedBox(height: AppSpacing.sm),
    ];

    if (rows.isEmpty) {
      children.add(_NoMatch(query: _query.trim()));
    } else {
      // Group BY LAYER (not alphabetically) — the brief's teaching requirement.
      for (final BodyLayer layer in BodyLayer.values) {
        final List<WifiBody> inLayer =
            rows.where((WifiBody b) => b.layer == layer).toList(growable: false);
        if (inLayer.isEmpty) continue;
        children.add(_LayerHeader(layer: layer));
        for (int i = 0; i < inLayer.length; i++) {
          children.add(
            _BodyCard(body: inLayer[i], launcher: widget.launcher),
          );
          if (i < inLayer.length - 1) {
            children.add(const SizedBox(height: AppSpacing.xs));
          }
        }
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      // The regulator layer is a cross-link, not restated data (SSOT).
      children.add(
        _RegulatorCrossLink(onOpen: widget.onOpenRegulatoryDomains),
      );
    }

    children.add(
      ToolHelpFooter(toolId: WifiStandardsBodiesScreen.toolId),
    );

    final String countLabel = filtering
        ? '${rows.length} of ${widget.bodies.length} bodies'
        : '${widget.bodies.length} bodies';

    return ListView(
      padding:
          EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge + AppSpacing.sm),
      children: <Widget>[
        Semantics(
          header: true,
          label: countLabel,
          child: const SizedBox.shrink(),
        ),
        ...children,
      ],
    );
  }
}

/// The lead teaching callout: the three-layer model in one info-toned card.
/// Wrapped in a single Semantics node so a screen reader reads it as one block.
class _ThreeLayerCallout extends StatelessWidget {
  const _ThreeLayerCallout();

  static const List<({String label, String gloss})> _layers =
      <({String label, String gloss})>[
    (
      label: 'Standards body',
      gloss: 'Defines HOW the radio works: the PHY, MAC, framing. (IEEE 802.11)'
    ),
    (
      label: 'Certification body',
      gloss: 'Verifies products from different vendors INTEROPERATE, and brands '
          'them. (Wi-Fi Alliance)'
    ),
    (
      label: 'Regulator',
      gloss: 'Sets what is LEGAL here: transmit power, channels, indoor / '
          'outdoor, per country. (FCC, Ofcom, the ETSI-aligned EU bloc)'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color info = colors.statusInfo;

    return Semantics(
      container: true,
      label: 'Three layers. A standards body defines how the radio works. A '
          'certification body verifies products interoperate. A regulator sets '
          'the legal channel and power rules per country.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isLight
              ? info.withValues(alpha: 0.06)
              : info.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.card),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'THREE LAYERS, THREE DIFFERENT JOBS',
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: info,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (int i = 0; i < _layers.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              RichText(
                text: TextSpan(
                  style: (text.bodyMedium ?? const TextStyle())
                      .copyWith(color: colors.textSecondary),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${_layers[i].label}: ',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: _layers[i].gloss),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The sharpest confusion, restated: IEEE writes 802.11; the Wi-Fi Alliance
/// certifies and brands it; "Wi-Fi" is a trademark, not an acronym.
class _TrademarkCallout extends StatelessWidget {
  const _TrademarkCallout();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'IEEE writes the 802.11 standard. The Wi-Fi Alliance certifies and '
          'brands it. They are not the same body. "Wi-Fi" is a Wi-Fi Alliance '
          'trademark, not an acronym, and does not stand for "Wireless '
          'Fidelity."',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.borderStrong, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.lightbulb_outline,
                    size: 20, color: colors.textAccent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'The one to get right',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'IEEE writes 802.11. The Wi-Fi Alliance certifies that products '
              'built to it interoperate, and it owns the consumer names '
              '(Wi-Fi 6, Wi-Fi 7). Two organizations, two jobs.',
              style: (text.bodyMedium ?? const TextStyle())
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"Wi-Fi" is a Wi-Fi Alliance trademark. It is not an acronym, and not '
              'short for "Wireless Fidelity."',
              style: (text.bodyMedium ?? const TextStyle())
                  .copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// In-screen search field (§8.4 input spec). 16px field text dodges iOS Safari
/// auto-zoom; mirrors the Regulatory Domains search field.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      textField: true,
      label: 'Search standards and industry bodies by name, role, or what they own',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.textPrimary),
        cursorColor: colors.textAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: colors.textTertiary),
          hintText: 'Search bodies, roles, or programs…',
        ),
      ),
    );
  }
}

/// The layer section header: the layer title + the one-line gloss that restates
/// the layer's job, so the grouping teaches rather than just sorts.
class _LayerHeader extends StatelessWidget {
  const _LayerHeader({required this.layer});

  final BodyLayer layer;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final BodyLayerInfo info = BodyLayerInfo.of(layer);

    return Semantics(
      header: true,
      container: true,
      label: '${info.title}. ${info.gloss}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              info.title.toUpperCase(),
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              info.gloss,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One body tile: logo (or abbreviation badge) + name + role + abbreviation, an
/// optional "context only" flag, what-they-own, why-a-pro-cares, and a tappable
/// official-website link. Stateful only to carry the per-tile launch error.
class _BodyCard extends StatefulWidget {
  const _BodyCard({required this.body, this.launcher});

  final WifiBody body;
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<_BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<_BodyCard> {
  String? _launchError;

  Future<void> _openWebsite() async {
    final Uri? uri = Uri.tryParse(widget.body.websiteUrl);
    if (uri == null) {
      _showLaunchError();
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError();
        return;
      }
      if (!mounted) return;
      setState(() => _launchError = null);
    } on Object {
      _showLaunchError();
    }
  }

  void _showLaunchError() {
    if (!mounted) return;
    setState(
      () => _launchError =
          'Could not open the browser. The link is ${widget.body.websiteUrl}',
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final WifiBody b = widget.body;

    return Semantics(
      container: true,
      label: '${b.name}, ${b.abbreviation}. '
          '${b.contextOnly ? 'Context only, not a Wi-Fi body. ' : ''}'
          'Role: ${b.roleType}. '
          'What they own: ${b.owns}. '
          'Why a Wi-Fi pro cares: ${b.whyCare}',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header: logo/badge + name + role + abbreviation.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _BodyLogo(body: b),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        b.name,
                        style: text.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.roleType,
                        style: text.labelMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            b.abbreviation,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (b.contextOnly) const _ContextOnlyChip(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _LabeledBlock(label: 'What they own', value: b.owns),
            const SizedBox(height: AppSpacing.xs),
            _LabeledBlock(label: 'Why a Wi-Fi pro cares', value: b.whyCare),
            const SizedBox(height: AppSpacing.sm),
            _WebsiteLink(
              url: b.websiteUrl,
              organization: b.name,
              onTap: _openWebsite,
            ),
            if (_launchError != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _LaunchError(message: _launchError!),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small pill flagging a body included for context that is NOT a Wi-Fi body
/// (Ecma). Warning-toned so it reads as "adjacent, take with a grain of salt."
class _ContextOnlyChip extends StatelessWidget {
  const _ContextOnlyChip();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: warn, width: 1),
      ),
      child: Text(
        'CONTEXT ONLY',
        style: (text.labelSmall ?? const TextStyle()).copyWith(
          color: warn,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The leading logo slot: the body's bundled wordmark when present, otherwise a
/// styled abbreviation badge (NEVER a broken image). 96x96 square so the row
/// aligns whether a logo or a badge shows (matches the Regulatory Domains slot).
class _BodyLogo extends StatelessWidget {
  const _BodyLogo({required this.body});

  final WifiBody body;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final String key = body.logoKey;
    final String? logoPath = WifiBodiesLogos.path(key);

    if (logoPath != null) {
      final Widget logo = WifiBodiesLogos.isSvg(key)
          ? SvgPicture.asset(
              logoPath,
              width: _size,
              height: _size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              placeholderBuilder: (_) =>
                  _AbbrevBadge(abbreviation: body.abbreviation),
            )
          : Image.asset(
              logoPath,
              width: _size,
              height: _size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, Object _, StackTrace? _) =>
                  _AbbrevBadge(abbreviation: body.abbreviation),
            );
      return SizedBox(
        width: _size,
        height: _size,
        // Lighter chip behind the wordmark so colored official marks read on the
        // dark surface; in light mode the card is already light.
        child: Container(
          decoration: BoxDecoration(
            color: colors.isLight ? colors.surface1 : colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: logo,
        ),
      );
    }

    return _AbbrevBadge(abbreviation: body.abbreviation);
  }
}

/// The fallback badge shown when a wordmark asset is not bundled: a tinted,
/// rounded square carrying the abbreviation in DM Mono. Kept short so it fits
/// the 96x96 square (first token, up to 5 chars — covers "IEEE", "3GPP", "ITU-R"
/// down to "ITU-R", and trims "Bluetooth SIG" to "Bluet").
class _AbbrevBadge extends StatelessWidget {
  const _AbbrevBadge({required this.abbreviation});

  final String abbreviation;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // First whitespace-delimited token, capped at 5 chars, so a long
    // abbreviation ("Bluetooth SIG") still fits the square as "Bluet".
    final String firstToken = abbreviation.split(' ').first;
    final String badge =
        firstToken.length > 5 ? firstToken.substring(0, 5) : firstToken;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Text(
        badge,
        textAlign: TextAlign.center,
        style: mono.inlineCode.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: badge.length > 3 ? AppTextSize.caption : AppTextSize.body,
        ),
      ),
    );
  }
}

/// A labeled prose block: a caption-style label over the value text.
class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: text.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// The tappable official-website link. An outlined, full-width control with a
/// link glyph and the URL in DM Mono (identifier). Carries the §8.3 lime focus
/// ring; explicit SR label names the body and that it opens in the browser.
class _WebsiteLink extends StatelessWidget {
  const _WebsiteLink({
    required this.url,
    required this.organization,
    required this.onTap,
  });

  final String url;
  final String organization;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      button: true,
      link: true,
      label: 'Open the $organization website in the browser',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.borderStrong, width: 1),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.open_in_new, size: 18, color: colors.textAccent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    url,
                    style: mono.inlineCode.copyWith(color: colors.textAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The regulator-layer cross-link card. The page does NOT restate national
/// spectrum rules (SSOT); it points to the Regulatory Domains reference. Tappable
/// when [onOpen] is wired; informative-only otherwise.
class _RegulatorCrossLink extends StatelessWidget {
  const _RegulatorCrossLink({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool tappable = onOpen != null;

    final Widget content = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.public, size: 24, color: colors.textAccent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'REGULATES PER COUNTRY',
                  style: (text.labelMedium ?? const TextStyle()).copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The third layer is the per-country regulator. Those national '
                  'channel and power rules live on the Regulatory Domains '
                  'reference (FCC, Ofcom, the ETSI-aligned EU bloc, and more) '
                  'so they stay in one place.',
                  style: text.labelMedium?.copyWith(color: colors.textSecondary),
                ),
                if (tappable) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      Text(
                        'Open Regulatory Domains',
                        style: text.labelMedium?.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Icon(Icons.arrow_forward,
                          size: 16, color: colors.textAccent),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!tappable) {
      return Semantics(
        container: true,
        label: 'Regulates per country. The per-country regulator rules live on '
            'the Regulatory Domains reference.',
        excludeSemantics: true,
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: 'Open the Regulatory Domains reference',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onOpen, child: content),
      ),
    );
  }
}

/// Honest error shown when the browser hand-off fails (the link stays readable).
class _LaunchError extends StatelessWidget {
  const _LaunchError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusDanger, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.statusDanger),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// In-screen no-results state when the live filter matches nothing.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No bodies loaded.'
                : 'No bodies match "$query".',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
