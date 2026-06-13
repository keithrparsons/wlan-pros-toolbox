// Naming & Addressing Conventions — read-only reference for hostname/DNS-label
// rules, MAC EUI-48/EUI-64 format, the U/L and I/G bits, and the OUI/CID
// concept.
//
// Part of the "Addressing & Subnetting" reference sub-category. Mirrors the
// poe_reference_screen / power_phasing_screen template exactly: typed const
// datasets on the screen class, a §8.16 AppCopyAction that emits the whole page
// as sectioned TSV, the shared LayoutBuilder / ConstrainedBox /
// SingleChildScrollView scaffold, and a ToolHelpFooter keyed on the catalog id.
//
// NAMED GRAPHIC: this page carries one named diagram — the MAC first-octet
// bit-field (assets/tool-graphics/mac-bit-field.svg) — resolved by explicit
// asset name through MacBitFieldDiagram (the manifest-gated resolver, the same
// multi-graphic pattern power_phasing uses) and rendered by _BitFieldBand, which
// reuses the §8.20.7 light-mode recolor path (ConceptGraphicBand.applyLightSwap)
// exactly as the power_phasing waveform band does. The band degrades to nothing
// when the SVG is not yet bundled, so the page ships fully working before
// Charta's diagram lands. Every fact the diagram depicts (U/L, I/G bit positions
// and meanings) is also in the U/L and I/G table, so the band is decorative for
// screen readers per the GL-003 §8.6.2 a11y rule.
//
// Data provenance (GL-005): every row is sourced verbatim from the verified
// addressing dataset (Deliverables/2026-06-08-reference-batch/addressing-data.md,
// Section 3), assembled from RFC 952 / RFC 1123 §2.1 / RFC 1035 (hostname/FQDN),
// IEEE Std 802-2014 with RFC 5342 §2.1 as the independent IETF restatement
// (MAC/EUI/U-L/I-G/OUI), and RFC 4291 Appendix A (Modified EUI-64). The IEEE
// standard is paywalled, so RFC 5342 §2.1 is cited as the freely-available
// secondary anchor; the dataset flags MA-L/MA-M/MA-S counts and the CID policy
// as authoritative-but-single-issuer (IEEE Registration Authority is the sole
// assigner).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render; the bit-field band carries its own
// absent-asset empty state (render nothing). No loading/empty/error path for the
// data (GL-008 network/subprocess rules do not apply).
//
// Glyph notes (GL-004): "Wi-Fi" never "WiFi"; ASCII hyphen-minus only, never an
// em dash; US spelling; hex octets and bit values render in the mono inline-code
// register.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/mac_bit_field_diagram.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One rule row used by the hostname, MAC-format, and OUI/CID tables: a short
/// name, the specification in prose, and the defining source. Sourced verbatim
/// from the verified addressing dataset (Section 3A / 3B / 3D).
@immutable
class ConventionRule {
  const ConventionRule({
    required this.name,
    required this.spec,
    required this.source,
  });

  /// Short rule / concept name, e.g. `Max FQDN length` or `EUI-48`.
  final String name;

  /// The specification in prose.
  final String spec;

  /// The defining source, e.g. `RFC 1035 §2.3.4 / §3.1`.
  final String source;
}

/// One U/L or I/G bit row — bit position, name, and the meaning of each value.
/// Sourced verbatim from the verified addressing dataset (Section 3C).
@immutable
class MacBit {
  const MacBit({
    required this.bit,
    required this.position,
    required this.name,
    required this.value0,
    required this.value1,
    required this.source,
  });

  /// Bit label, e.g. `I/G` or `U/L`.
  final String bit;

  /// Position within the first octet, e.g. `bit 0 (LSB of first octet)`.
  final String position;

  /// Full name, e.g. `Individual/Group`.
  final String name;

  /// Meaning when the bit is 0.
  final String value0;

  /// Meaning when the bit is 1.
  final String value1;

  /// The defining source.
  final String source;
}

class NamingConventionsScreen extends StatelessWidget {
  const NamingConventionsScreen({super.key});

  /// Hostname / DNS-label rules. Verbatim from dataset Section 3A.
  static const List<ConventionRule> hostnameRules = <ConventionRule>[
    ConventionRule(
      name: 'Allowed characters',
      spec:
          'Letters (A-Z, a-z), digits (0-9), and the hyphen (-). No '
          'underscores, spaces, or other symbols in a standard hostname.',
      source: 'RFC 952; RFC 1123 §2.1',
    ),
    ConventionRule(
      name: 'First character',
      spec:
          'May be a letter OR a digit. (RFC 952 required a letter; RFC 1123 '
          '§2.1 relaxed this to allow a leading digit.)',
      source: 'RFC 1123 §2.1',
    ),
    ConventionRule(
      name: 'Last character',
      spec:
          'Must be a letter or digit — a label may NOT end with a hyphen.',
      source: 'RFC 952',
    ),
    ConventionRule(
      name: 'Hyphen placement',
      spec: 'Interior only. No leading hyphen, no trailing hyphen.',
      source: 'RFC 952',
    ),
    ConventionRule(
      name: 'Case sensitivity',
      spec: 'Case-insensitive (comparisons ignore case).',
      source: 'RFC 952; RFC 1035 §2.3.3',
    ),
    ConventionRule(
      name: 'Max label length',
      spec: '63 octets per label (single component between dots).',
      source: 'RFC 1035 §2.3.4 / §3.1',
    ),
    ConventionRule(
      name: 'Max FQDN length',
      spec:
          '253 characters (255 octets on the wire). The 255-octet wire-format '
          'cap, after length-prefix and root-label overhead, yields a 253-'
          'character practical text limit.',
      source: 'RFC 1035 §2.3.4 / §3.1',
    ),
    ConventionRule(
      name: 'Not all-numeric',
      spec:
          'A valid host name can never have the dotted-decimal form #.#.#.# — '
          'at least the top-level component must be alphabetic, so a hostname '
          'is never ambiguous with an IPv4 literal.',
      source: 'RFC 1123 §2.1',
    ),
  ];

  /// MAC EUI-48 / EUI-64 format rules. Verbatim from dataset Section 3B.
  static const List<ConventionRule> macFormat = <ConventionRule>[
    ConventionRule(
      name: 'EUI-48',
      spec:
          '48-bit identifier (6 octets), 12 hex digits. Common forms: '
          '00-1B-44-11-3A-B7 (hyphen), 00:1B:44:11:3A:B7 (colon), '
          '001B.4411.3AB7 (Cisco dotted). The legacy term "MAC-48" is '
          'deprecated in favor of EUI-48.',
      source: 'IEEE 802; RFC 5342 §2.1',
    ),
    ConventionRule(
      name: 'EUI-64',
      spec:
          '64-bit identifier (8 octets), 16 hex digits. Used directly by some '
          'link layers and by IPv6 Modified EUI-64 interface identifiers.',
      source: 'IEEE 802; RFC 5342 §2.2',
    ),
    ConventionRule(
      name: 'EUI-48 to EUI-64',
      spec:
          'Insert FF-FF between the OUI (first 3 octets) and the device '
          'portion (last 3 octets).',
      source: 'IEEE 802',
    ),
    ConventionRule(
      name: 'Modified EUI-64 (IPv6)',
      spec:
          'Insert FF-FE (not FF-FF) in the middle AND invert the U/L bit. Used '
          'to derive an IPv6 interface identifier from an EUI-48.',
      source: 'RFC 4291 Appendix A',
    ),
    ConventionRule(
      name: 'Transmission bit order',
      spec:
          'Octets transmitted most-significant-octet first; within each octet, '
          'least-significant bit first (canonical / LSB-first on Ethernet). The '
          'first transmitted bit of the first octet is the I/G bit.',
      source: 'IEEE 802',
    ),
  ];

  /// U/L and I/G bits — the two least-significant bits of the first octet.
  /// Verbatim from dataset Section 3C.
  static const List<MacBit> macBits = <MacBit>[
    MacBit(
      bit: 'I/G',
      position: 'bit 0 (LSB of first octet)',
      name: 'Individual/Group',
      value0: 'Individual (unicast)',
      value1: 'Group (multicast)',
      source: 'IEEE 802; RFC 5342 §2.1',
    ),
    MacBit(
      bit: 'U/L',
      position: 'bit 1 (second-LSB of first octet)',
      name: 'Universal/Local',
      value0: 'Universally administered (OUI-based, globally unique)',
      value1: 'Locally administered',
      source: 'IEEE 802; RFC 5342 §2.1',
    ),
  ];

  /// OUI / CID concept rows. Verbatim from dataset Section 3D.
  static const List<ConventionRule> ouiConcepts = <ConventionRule>[
    ConventionRule(
      name: 'OUI',
      spec:
          'Organizationally Unique Identifier — a 24-bit (3-octet) value '
          'assigned by the IEEE Registration Authority. Forms the high-order '
          'bits of universally administered EUI-48/EUI-64 addresses; the U/L '
          'bit is 0 (universal).',
      source: 'IEEE 802; RFC 5342 §2.1',
    ),
    ConventionRule(
      name: 'MA-L / MA-M / MA-S',
      spec:
          'IEEE assignment tiers: MA-L (large, 24-bit OUI, ~16.7M addresses), '
          'MA-M (medium, 28-bit, ~1M addresses), MA-S (small, 36-bit, 4096 '
          'addresses). MA-S and MA-M share a base OUI across organizations.',
      source: 'IEEE Registration Authority',
    ),
    ConventionRule(
      name: 'CID',
      spec:
          'Company ID — a 24-bit identifier for organizations needing a unique '
          'company identifier but NOT globally unique addresses. A CID always '
          'has the U/L bit set to 1 (locally administered) and the I/G bit 0, '
          'so CID-based addresses can never collide with OUI-based addresses.',
      source: 'IEEE 802; IEEE Registration Authority',
    ),
  ];

  /// The low-nibble derivation note, sitting under the U/L and I/G table.
  static const String nibbleNote =
      'Read the rule by the low nibble of the first byte: 2/6/A/E means '
      'locally administered unicast (U/L=1, I/G=0). An odd low nibble '
      '(1/3/5/7/9/B/D/F) means I/G=1, a multicast/group address. 0/4/8/C means '
      'universally administered unicast.';

  /// Provenance footnote shown at the foot of the U/L and I/G card.
  static const String bitsFootnote =
      'Source: IEEE Std 802-2014 §8.2 (U/L and I/G bit definitions); RFC 5342 '
      '§2.1 reproduces the IEEE bit assignments for IETF use. The bit-to-'
      'nibble derivation is arithmetic from those definitions. IEEE Std 802 is '
      'paywalled, so RFC 5342 §2.1 is the freely-available secondary anchor.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naming & Addressing Conventions'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: hostname rules, MAC
        // format, U/L and I/G bits, then OUI/CID. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as four TSV sections. Always non-null
  /// (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Naming & Addressing Conventions')
      ..writeln()
      ..writeln('Hostname / DNS label rules')
      ..writeln(<String>['Rule', 'Specification', 'Source'].join(tab));
    for (final ConventionRule r in hostnameRules) {
      buf.writeln(<String>[r.name, r.spec, r.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln('MAC format (EUI-48 / EUI-64)')
      ..writeln(<String>['Concept', 'Specification', 'Source'].join(tab));
    for (final ConventionRule r in macFormat) {
      buf.writeln(<String>[r.name, r.spec, r.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln('U/L and I/G bits (first octet)')
      ..writeln(
        <String>['Bit', 'Position', 'Name', 'Value 0', 'Value 1', 'Source']
            .join(tab),
      );
    for (final MacBit b in macBits) {
      buf.writeln(
        <String>[b.bit, b.position, b.name, b.value0, b.value1, b.source]
            .join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(nibbleNote)
      ..writeln()
      ..writeln('OUI / CID concept')
      ..writeln(<String>['Term', 'Definition', 'Source'].join(tab));
    for (final ConventionRule r in ouiConcepts) {
      buf.writeln(<String>[r.name, r.spec, r.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln(bitsFootnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                children: <Widget>[
                  _ruleCard(
                    title: 'Hostname / DNS label rules',
                    nameHeader: 'Rule',
                    nameWidth: 168,
                    specHeader: 'Specification',
                    rules: hostnameRules,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ruleCard(
                    title: 'MAC format (EUI-48 / EUI-64)',
                    nameHeader: 'Concept',
                    nameWidth: 168,
                    specHeader: 'Specification',
                    rules: macFormat,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _bitsCard(isDesktop, colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _ruleCard(
                    title: 'OUI / CID concept',
                    nameHeader: 'Term',
                    nameWidth: 168,
                    specHeader: 'Definition',
                    rules: ouiConcepts,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  ToolHelpFooter(toolId: 'naming-conventions'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A name/spec/source rule card shared by the hostname, MAC-format, and
  /// OUI/CID sections (same three-column shape, different header labels).
  Widget _ruleCard({
    required String title,
    required String nameHeader,
    required double nameWidth,
    required String specHeader,
    required List<ConventionRule> rules,
    required AppColorScheme colors,
    required TextTheme text,
    required AppMonoText mono,
  }) {
    return _TableCard(
      title: title,
      header: Row(
        children: <Widget>[
          _HeaderCell(nameHeader, width: nameWidth),
          _HeaderCell(specHeader, width: 440),
          const _HeaderCell('Source', width: 168),
        ],
      ),
      rows: rules.map((ConventionRule r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.name, <String?>[r.spec, r.source]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: nameWidth,
                  child: Text(
                    r.name,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 440,
                  child: Text(
                    r.spec,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    r.source,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// The U/L and I/G bits card — carries the named MAC bit-field diagram band
  /// above the bit table, the low-nibble derivation note, and the provenance
  /// footnote.
  Widget _bitsCard(
    bool isDesktop,
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
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
          Text(
            'U/L and I/G bits (first octet)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Named bit-field diagram — renders only when bundled; otherwise the
          // card reads fine on the bit table below (graceful degradation).
          _BitFieldBand(
            assetName: MacBitFieldDiagram.macBitField,
            isDesktop: isDesktop,
          ),
          if (MacBitFieldDiagram.has(MacBitFieldDiagram.macBitField))
            const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      _HeaderCell('Bit', width: 56),
                      _HeaderCell('Position', width: 200),
                      _HeaderCell('Name', width: 152),
                      _HeaderCell('Value 0', width: 232),
                      _HeaderCell('Value 1', width: 152),
                    ],
                  ),
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...macBits.map((MacBit b) {
                    return ReferenceRowSemantics(
                      label: rowLabel(b.bit, <String?>[
                        b.name,
                        b.position,
                        '0 = ${b.value0}',
                        '1 = ${b.value1}',
                      ]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 56,
                              child: Text(
                                b.bit,
                                style: mono.inlineCode.copyWith(
                                  color: colors.textAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: Text(
                                b.position,
                                style: text.labelMedium?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 152,
                              child: Text(
                                b.name,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 232,
                              child: Text(
                                b.value0,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 152,
                              child: Text(
                                b.value1,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            nibbleNote,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            bitsFootnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The MAC bit-field diagram band. Renders the bundled SVG
/// (`assets/tool-graphics/<asset-name>.svg`) inside a recessed band when it is
/// bundled, and collapses to nothing (SizedBox.shrink) when it is not — so the
/// page ships fully working before Charta's diagram lands. Decorative for screen
/// readers: every fact the diagram depicts is also in the U/L and I/G table per
/// the GL-003 §8.6.2 a11y rule.
///
/// LIGHT/DARK (GL-003 §8.20.7): the diagram is authored DARK-BAKED, so this
/// widget reuses the SAME §8.20.7 recolor path the concept graphics and the
/// power_phasing waveform band use, via the single-source swap
/// [ConceptGraphicBand.applyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte; dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap, then
///     render via SvgPicture.string. Cached per asset name so the replace runs
///     once, not on every rebuild.
class _BitFieldBand extends StatelessWidget {
  const _BitFieldBand({required this.assetName, required this.isDesktop});

  final String assetName;
  final bool isDesktop;

  // §8.6.2 band-height token: 140dp mobile / 160dp tablet-desktop. The bit-field
  // diagram is wider than tall, so it sits comfortably inside the band height.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per asset, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the diagram SVG source and applies the §8.20.7 allow-list light swap,
  /// caching per asset name. Returns the recolored source string.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[assetName] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(MacBitFieldDiagram.path(assetName));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[assetName] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled diagram → render nothing, layout unchanged.
    if (!MacBitFieldDiagram.has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightBitFieldSvg(future: _loadSwappedSvg(), bandHeight: bandHeight)
        : SvgPicture.asset(
            MacBitFieldDiagram.path(assetName),
            fit: BoxFit.contain,
            width: double.infinity,
            height: bandHeight,
            excludeFromSemantics: true,
            // A bundled-but-unparseable SVG collapses to nothing rather than
            // surfacing a broken-image box.
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode bit-field render: awaits the §8.20.7-swapped SVG source, then
/// draws it with `SvgPicture.string`. Collapses to nothing while loading or on
/// any parse failure — same graceful-degradation contract as the dark asset
/// path, so no broken-image box or layout jump ever appears. Mirrors
/// power_phasing's `_LightWaveformSvg`.
class _LightBitFieldSvg extends StatelessWidget {
  const _LightBitFieldSvg({required this.future, required this.bandHeight});

  final Future<String> future;
  final double bandHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
          // Loading or failed — render nothing (no broken box, no jump).
          return const SizedBox.shrink();
        }
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: double.infinity,
          height: bandHeight,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align). Matches the poe_reference_screen / power_phasing_screen
/// overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
