// International Power Plugs — read-only reference mapping the IEC World Plugs
// letter system (Type A-O) to the national standards behind each plug, with
// country, voltage class, current rating, and type letter.
//
// Page 5 of 6 in the "Power & Cooling" reference category.
//
// BIG-graphic redesign (Keith, 2026-06-08): the page no longer carries one small
// concept graphic borrowed from the power-phasing resolver. It now renders one
// LARGE per-type FACE graphic per card — each = the big plug face plus that
// type's title/specs alongside (the reusable LargeFaceCard pattern the IEC page
// established), resolved by explicit asset name through the page's own dedicated
// InternationalPlugsDiagrams resolver (cloned from IecConnectorsDiagrams). The
// CEE 7 European family stays a compact table card (it is a sub-breakout of the
// C/E/F letters, not a distinct face). Every face degrades to nothing when its
// SVG is not yet bundled, so each card reads as title + specs alone until
// Charta's faces land.
//
// SAFETY (the load-bearing distinction): the "interchangeable Type I cluster"
// (Australia/NZ, China, Argentina) shares the two-flat-blades-in-a-V + earth
// SHAPE but is NOT safely interchangeable — Argentina (IRAM 2073) reverses line
// and neutral relative to Australia/China, so an Australian plug used in
// Argentina energizes the wrong contact. That is rendered as a prominent
// StatusTone.warning callout ABOVE the cards, using the §8.13/§8.20.4
// status-warning idiom the wpa/poe pages use (theme-aware statusToneColor border
// + tinted surface, never a baked Color).
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 5),
// sourced to the IEC World Plugs letter system and the named national standards
// (CEE 7, BS 1363, BS 546, AS/NZS 3112, GB 2099/CPCS-CCC, IRAM 2073, SEV 1011,
// CEI 23-50). The iec.ch World Plugs page returned HTTP 403 to automated fetch,
// so this page cites the underlying national standard numbers, not "per iec.ch".
// Facts only.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path because
// nothing is fetched or parsed at runtime; each face card carries its own
// absent-asset empty state (renders no graphic). GL-008 network/subprocess rules
// do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): degrees spelled out in prose, no degree glyph in
// the copy payload; ASCII hyphen-minus only, never an em dash; US spelling;
// "Access Point" never "router".

import 'package:flutter/material.dart';

import '../../../data/international_plugs_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One IEC World Plugs letter-type row — type letter mapped to the national
/// standard behind it, with voltage class, current rating, and example
/// countries. Field values are verified against Pax's research brief (Topic 5).
@immutable
class PlugType {
  const PlugType({
    required this.type,
    required this.standard,
    required this.voltageClass,
    required this.current,
    required this.countries,
    this.assetName,
  });

  /// IEC World Plugs type letter, e.g. `C`, `F`, `G`.
  final String type;

  /// The national standard behind the plug, e.g. `CEE 7/4 (Schuko)`.
  final String standard;

  /// Voltage class, e.g. `230V` or `120V`.
  final String voltageClass;

  /// Current rating, e.g. `16A`, `13A (fused)`, `2.5A`.
  final String current;

  /// Example countries, e.g. `Germany + most of continental Europe`.
  final String countries;

  /// The per-face SVG asset name for this plug type (one of the
  /// [InternationalPlugsDiagrams] face consts), or null when no dedicated face
  /// is produced (Type B shares the NEMA 5-15 face on the NEMA page). Resolved
  /// through the manifest-gated resolver and degrades gracefully when absent.
  final String? assetName;
}

/// One CEE 7 family member — the European plug system needs its own breakout
/// because four CEE 7 plugs map to three IEC letters (C, E, F) plus the E/F
/// hybrid that has no distinct letter. Verified against the research brief.
@immutable
class Cee7Member {
  const Cee7Member({
    required this.designation,
    required this.type,
    required this.current,
    required this.note,
  });

  /// CEE 7 designation, e.g. `CEE 7/4`, `CEE 7/16`.
  final String designation;

  /// IEC type letter, or `E/F` for the hybrid that fits both sockets.
  final String type;

  /// Current rating, e.g. `16A`, `2.5A`.
  final String current;

  /// What it is / where it fits.
  final String note;
}

class InternationalPlugsScreen extends StatelessWidget {
  const InternationalPlugsScreen({super.key});

  /// The IEC World Plugs letter system, in letter order. Verified against the
  /// research brief (Topic 5). Public-static for testing.
  static const List<PlugType> plugTypes = <PlugType>[
    PlugType(
      type: 'A',
      standard: 'NEMA 1-15 (ungrounded)',
      voltageClass: '120V',
      current: '15A',
      countries: 'US, Canada, Japan, Mexico',
      assetName: InternationalPlugsDiagrams.a,
    ),
    PlugType(
      type: 'B',
      standard: 'NEMA 5-15 (grounded)',
      voltageClass: '120V',
      current: '15A',
      countries: 'US, Canada',
    ),
    PlugType(
      type: 'C',
      standard: 'CEE 7/16 (Europlug)',
      voltageClass: '230V',
      current: '2.5A',
      countries: 'Europe (widespread, unearthed)',
      assetName: InternationalPlugsDiagrams.c,
    ),
    PlugType(
      type: 'D',
      standard: 'BS 546 (5A)',
      voltageClass: '230V',
      current: '5A',
      countries: 'India, around 40 countries',
      assetName: InternationalPlugsDiagrams.d,
    ),
    PlugType(
      type: 'E',
      standard: 'CEE 7/5 (French)',
      voltageClass: '230V',
      current: '16A',
      countries: 'France, Belgium, Poland, Czechia',
      assetName: InternationalPlugsDiagrams.e,
    ),
    PlugType(
      type: 'F',
      standard: 'CEE 7/4 (Schuko)',
      voltageClass: '230V',
      current: '16A',
      countries: 'Germany + most of continental Europe',
      assetName: InternationalPlugsDiagrams.f,
    ),
    PlugType(
      type: 'G',
      standard: 'BS 1363',
      voltageClass: '230V',
      current: '13A (fused)',
      countries: 'UK, Ireland, around 50 countries',
      assetName: InternationalPlugsDiagrams.g,
    ),
    PlugType(
      type: 'I',
      standard: 'AS/NZS 3112',
      voltageClass: '230V',
      current: '10A',
      countries: 'Australia, New Zealand',
      assetName: InternationalPlugsDiagrams.i,
    ),
    PlugType(
      type: 'I',
      standard: 'CPCS-CCC (GB 2099, China)',
      voltageClass: '230V',
      current: '10A',
      countries: 'China',
      assetName: InternationalPlugsDiagrams.i,
    ),
    PlugType(
      type: 'I',
      standard: 'IRAM 2073 (Argentina)',
      voltageClass: '230V',
      current: '10A',
      countries: 'Argentina (line/neutral reversed, see warning)',
      assetName: InternationalPlugsDiagrams.i,
    ),
    PlugType(
      type: 'J',
      standard: 'SEV 1011 / SN 441011',
      voltageClass: '230V',
      current: '10A',
      countries: 'Switzerland, Liechtenstein',
      assetName: InternationalPlugsDiagrams.j,
    ),
    PlugType(
      type: 'L',
      standard: 'CEI 23-50',
      voltageClass: '230V',
      current: '10 / 16A',
      countries: 'Italy, Chile',
      assetName: InternationalPlugsDiagrams.l,
    ),
    PlugType(
      type: 'M',
      standard: 'BS 546 (15A)',
      voltageClass: '230V',
      current: '15A',
      countries: 'South Africa',
      assetName: InternationalPlugsDiagrams.m,
    ),
  ];

  /// The CEE 7 European family breakout — four plugs, three letters plus the
  /// E/F hybrid. Verified against the research brief.
  static const List<Cee7Member> cee7Family = <Cee7Member>[
    Cee7Member(
      designation: 'CEE 7/16',
      type: 'C',
      current: '2.5A',
      note: 'Europlug: unearthed, fits most 230V sockets across Europe',
    ),
    Cee7Member(
      designation: 'CEE 7/4',
      type: 'F',
      current: '16A',
      note: 'Schuko: earthed, Germany and most of continental Europe',
    ),
    Cee7Member(
      designation: 'CEE 7/5',
      type: 'E',
      current: '16A',
      note: 'French: earthed, France, Belgium, Poland, Czechia',
    ),
    Cee7Member(
      designation: 'CEE 7/7',
      type: 'E/F',
      current: '16A',
      note: 'Hybrid plug designed to fit both French (E) and Schuko (F) sockets',
    ),
  ];

  /// The Type I safety warning — the load-bearing caveat. Verified (Topic 5).
  /// Rendered in a prominent StatusTone.warning callout, not buried in a row.
  static const String typeIWarningTitle =
      'Type I plugs are not safely interchangeable';

  static const String typeIWarningBody =
      'Australia and New Zealand (AS/NZS 3112), China (CPCS-CCC / GB 2099), and '
      'Argentina (IRAM 2073) all share the Type I two-flat-blades-in-a-V plus '
      'earth shape, but they are not freely interchangeable. Argentina is wired '
      'with the live and neutral contacts reversed relative to Australia and '
      'China, so an Australian plug used in Argentina energizes the wrong '
      'contact. Argentina\'s 10A and 20A variants also differ in pin spacing '
      'and do not intermate, and the Chinese variant has dimensional '
      'differences from the Australasian one. Same family, different polarity '
      'and spacing; do not assume cross-compatibility.';

  /// Provenance + clarifying footnotes shown beneath the cards.
  static const String tableFootnote =
      'Voltage is around 230V across virtually all of Europe, Asia, Oceania, '
      'and South America; A and B are the 120V North American types. BS 546 '
      'appears twice on purpose: Type D is the 5A plug (India), Type M is the '
      '15A plug (South Africa); same family, different sizes, not '
      'intermateable. Standards per the named national standards behind the IEC '
      'World Plugs letter system.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('International Power Plugs'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the IEC type table, the
        // CEE 7 European family, then the Type I safety warning. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as TSV sections. Section 1 is the IEC
  /// type table (type, standard, voltage, current, countries); section 2 is the
  /// CEE 7 family (designation, type, current, note); then the Type I safety
  /// warning and the footnote as prose. No degree or em-dash glyph is emitted.
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('International Power Plugs')
      ..writeln()
      ..writeln('IEC World Plugs letter system')
      ..writeln(
        <String>[
          'Type',
          'Standard',
          'Voltage',
          'Current',
          'Example countries',
        ].join(tab),
      );
    for (final PlugType p in plugTypes) {
      buf.writeln(
        <String>[
          p.type,
          p.standard,
          p.voltageClass,
          p.current,
          p.countries,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('CEE 7 European family')
      ..writeln(
        <String>['Designation', 'Type', 'Current', 'Note'].join(tab),
      );
    for (final Cee7Member m in cee7Family) {
      buf.writeln(
        <String>[m.designation, m.type, m.current, m.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('WARNING: $typeIWarningTitle')
      ..writeln(typeIWarningBody)
      ..writeln()
      ..writeln(tableFootnote);
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
                  // The Type I safety warning rides at the top, above the cards,
                  // so a tech sees it before scanning the Type I face-cards.
                  _WarningCallout(
                    title: typeIWarningTitle,
                    body: typeIWarningBody,
                    colors: colors,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // BIG-graphic redesign (Keith, 2026-06-08): one LARGE face-card
                  // per IEC World Plugs letter type, stacked vertically — each =
                  // the big plug face plus that type's title/specs alongside (the
                  // reusable LargeFaceCard pattern). Every face degrades to
                  // nothing when its SVG is not yet bundled, so each card reads as
                  // title + specs alone until Charta's faces land.
                  _SectionHeading(label: 'IEC World Plugs letter system'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._faceCards(isDesktop),
                  Text(
                    tableFootnote,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // The CEE 7 European family stays a compact table card — it is
                  // a sub-breakout of the C/E/F letters, not a distinct face.
                  _cee7Card(colors, text, mono),
                  ToolHelpFooter(toolId: 'international-plugs'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the stacked [LargeFaceCard] list, one big card per plug type, with an
  /// `AppSpacing.md` gap between them. Each card carries the type letter as the
  /// title, the national standard as a subtitle, the voltage/current/countries
  /// as specs, and its per-face SVG (degrading gracefully). The three Type I
  /// rows each render their own card so each national standard stays distinct;
  /// the polarity caveat is carried by the warning callout above.
  List<Widget> _faceCards(bool isDesktop) {
    final List<Widget> cards = <Widget>[];
    for (final PlugType p in plugTypes) {
      cards
        ..add(
          LargeFaceCard(
            title: 'Type ${p.type}',
            subtitle: p.standard,
            specs: <FaceSpec>[
              FaceSpec(label: 'Voltage', value: p.voltageClass),
              FaceSpec(label: 'Current', value: p.current, accent: true),
              FaceSpec(label: 'Countries', value: p.countries),
            ],
            assetName: p.assetName ?? '',
            path: InternationalPlugsDiagrams.path,
            has: (String name) =>
                name.isNotEmpty && InternationalPlugsDiagrams.has(name),
            isDesktop: isDesktop,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.md));
    }
    return cards;
  }

  Widget _cee7Card(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'CEE 7 European family',
      header: const Row(
        children: <Widget>[
          _HeaderCell('Designation', width: 96),
          _HeaderCell('Type', width: 56),
          _HeaderCell('Current', width: 72),
          _HeaderCell('Note', width: 300),
        ],
      ),
      rows: cee7Family.map((Cee7Member m) {
        return ReferenceRowSemantics(
          label: rowLabel(m.designation, <String?>[
            'type ${m.type}',
            'current ${m.current}',
            m.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    m.designation,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    m.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    m.current,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Text(
                    m.note,
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
}

/// A section heading inside the International Power Plugs reference. Title-styled,
/// secondary ink, matching the register the IEC page uses for its section labels
/// — standing on the page background above a stack of [LargeFaceCard]s.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      label,
      style: text.titleSmall?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// The Type I safety warning, rendered as a prominent callout using the
/// §8.13/§8.20.4 status-warning idiom the wpa/poe pages use: a surface1 card
/// with a 1px [StatusTone.warning] border (resolved at render via
/// [statusToneColor], never a baked Color, so it tracks light/dark), a warning
/// icon tinted to the same status token, and the warning title + body. The
/// status border clears SC 1.4.11 (3:1 non-text) on surface1; all warning text
/// is full-strength textPrimary/textSecondary so contrast does not depend on the
/// status hue.
class _WarningCallout extends StatelessWidget {
  const _WarningCallout({
    required this.title,
    required this.body,
    required this.colors,
    required this.text,
  });

  final String title;
  final String body;
  final AppColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final Color warning = colors.statusToneColor(StatusTone.warning);
    return Semantics(
      container: true,
      // Spoken as a single block so the warning is heard before the cards.
      label: 'Warning. $title. $body',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: warning, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: warning, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      body,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card surface wrapping a wide table: title over a horizontally-scrolling
/// IntrinsicWidth grid (header + rows share one width so columns align). Used
/// only for the CEE 7 family card now. Matches the
/// poe_reference_screen / power_phasing_screen / wifi_channels_screen
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
