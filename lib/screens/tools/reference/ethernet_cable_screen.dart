// Ethernet Cable & Connector — read-only twisted-pair reference, offline.
//
// Consolidated 2026-06-12: the former `ethernet-cable`, `ethernet-pinout`, and
// `cable-connector` tiles are merged into this single tool (Keith: "all three
// into one"). Two clear sections:
//
//   1. Cable categories — the rich Cat5e→Cat8 capability chart ported verbatim
//      from the RF Tools PWA (app.js ETH_DATA): bandwidth, max speed, distance
//      at 1G/10G, PoE, shielding, typical use. Plus the BASE-T speed-grade
//      (multi-gig) table, the ISO/IEC 11801 shielding-code key, the Cat 7
//      "ISO/IEC Class F, not TIA" caveat, and the PoE++ heat footnote.
//   2. RJ-45 pinout — the T568A / T568B wiring reference (pin → wire color →
//      pair → 100/1000 Base-T function), toggled between the two standards.
//      Ported verbatim from the PWA `pinout` tool (PINOUT, pairColors). This is
//      the cleaner of the two pre-merge pinout implementations (the old
//      ethernet-pinout screen): it carries the pair number, the function, and
//      both the wire and pair swatches.
//
// This is a pure read-only reference — no inputs, no computation, no network.
// It works on every platform (no NetworkUnavailableView). The only interactive
// element is the T568B / T568A toggle and the §8.16 copy action. There is no
// loading, empty, or error path because nothing is fetched or parsed at runtime
// and neither dataset is ever empty.
//
// Overflow-safe: the wide capability table exceeds phone width, so it scrolls
// horizontally inside the fixed card — the same idiom as mcs_index_screen.
//
// Color glyph note: the pinout wire-insulation swatch and the pair-color swatch
// are DATA glyphs (the literal copper-pair colors an installer sees), not UI
// chrome. They are kept verbatim from the PWA hexes and are NOT design-system
// surface/text tokens; they stay literal in both themes (a 1px border keeps a
// near-white wire visible on the light card). Every text, surface, border,
// radius, and spacing value below is a GL-003 token. No em dash ships.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One Ethernet cable category row. Ported verbatim from PWA app.js ETH_DATA
/// (`[cat, max_mhz, max_speed, dist_1g, dist_10g, poe, shielding, use]`).
class EthCable {
  const EthCable({
    required this.category,
    required this.maxMhz,
    required this.maxSpeed,
    required this.dist1g,
    required this.dist10g,
    required this.poe,
    required this.shielding,
    required this.use,
  });

  /// Category label, e.g. "Cat6A".
  final String category;

  /// Max bandwidth in MHz.
  final int maxMhz;

  /// Max rated speed, e.g. "10 Gbps".
  final String maxSpeed;

  /// Max distance at 1 Gbps. "N/A" where the PWA shows a dash.
  final String dist1g;

  /// Max distance at 10 Gbps. "N/A" where the PWA shows a dash.
  final String dist10g;

  /// PoE support, e.g. "802.3bt (all)".
  final String poe;

  /// Shielding types, e.g. "F/UTP, S/FTP".
  final String shielding;

  /// Typical use note.
  final String use;
}

/// One BASE-T speed grade — the standard, its rate, the minimum cabling it
/// needs, the max channel distance, and the IEEE spec. Covers the multi-gig
/// rates (2.5G/5G, 802.3bz) that sit between 1G and 10G. Values per IEEE
/// 802.3bz-2016.
@immutable
class EthSpeedGrade {
  const EthSpeedGrade({
    required this.standard,
    required this.speed,
    required this.minCabling,
    required this.maxDistance,
    required this.ieeeSpec,
  });

  /// BASE-T standard, e.g. `2.5GBASE-T`.
  final String standard;

  /// Rate, e.g. `2.5 Gbps`.
  final String speed;

  /// Minimum cabling category, e.g. `Cat5e`.
  final String minCabling;

  /// Max channel distance, e.g. `100m`.
  final String maxDistance;

  /// Defining IEEE specification, e.g. `802.3bz (2016)`.
  final String ieeeSpec;
}

/// One ISO/IEC 11801 shielding code — the `[overall]/[per-pair]TP` notation
/// and its plain-language name. Per ISO/IEC 11801.
@immutable
class ShieldingCode {
  const ShieldingCode({
    required this.code,
    required this.overall,
    required this.perPair,
    required this.name,
  });

  /// Shielding code, e.g. `S/FTP`.
  final String code;

  /// Overall (cable-level) screen, e.g. `Braid`.
  final String overall;

  /// Per-pair screen, e.g. `Foil per pair`.
  final String perPair;

  /// Plain-language name.
  final String name;
}

/// Which RJ-45 wiring standard's pinout is shown. Two short options → segmented
/// toggle, not an AppSelect (GL-003 §8.14). T568B is the PWA's default tab.
enum WiringStandard { t568b, t568a }

/// One pin row in a wiring standard. Verbatim shape of the PWA's PINOUT array
/// entry `[pin, colorHex, colorName, pair, function]`.
class PinoutPin {
  const PinoutPin({
    required this.pin,
    required this.colorHex,
    required this.colorName,
    required this.pair,
    required this.function,
  });

  /// RJ-45 pin number, 1–8.
  final int pin;

  /// Wire-insulation color as the literal PWA hex — a DATA glyph (the real
  /// copper color), not a GL-003 token. A name containing '/' is a striped
  /// (color-on-white) wire; rendered as a 135° split swatch like the PWA.
  final int colorHex;

  /// Human-readable wire color, verbatim from the PWA (e.g. 'Orange / White').
  final String colorName;

  /// Twisted-pair number this wire belongs to, 1–4.
  final int pair;

  /// 100/1000 Base-T signal function (e.g. 'TX+', 'BI-D A+').
  final String function;
}

class EthernetCableScreen extends StatefulWidget {
  const EthernetCableScreen({super.key});

  /// Ethernet cable categories. Ported verbatim from PWA app.js ETH_DATA.
  /// The PWA's em-dash "not applicable" cells are reproduced as the ASCII
  /// marker "N/A" (no em dash ships in the app); every other value is exact.
  static const List<EthCable> ethData = [
    EthCable(
      category: 'Cat5e',
      maxMhz: 100,
      maxSpeed: '1 Gbps',
      dist1g: '100m',
      dist10g: 'N/A',
      poe: '802.3af / at',
      shielding: 'UTP or FTP',
      use: 'Standard LAN wiring',
    ),
    EthCable(
      category: 'Cat6',
      maxMhz: 250,
      maxSpeed: '10 Gbps',
      dist1g: '100m',
      // 37-55 m, not a flat 55 m. The two numbers are BOTH real: 55 m is the
      // favorable-alien-crosstalk case, 37 m is the dense-bundle planning
      // distance. The structured-cabling screen has carried both all along;
      // this one said "55m" and stopped, so the app contradicted itself. In a
      // real ceiling that gap is the install failing, so the number a designer
      // must plan to (37 m) leads.
      dist10g: '37-55m',
      poe: '802.3af / at',
      shielding: 'UTP or STP',
      use: 'Modern LAN, some 10G',
    ),
    EthCable(
      category: 'Cat6A',
      maxMhz: 500,
      maxSpeed: '10 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: '802.3bt (all)',
      shielding: 'F/UTP, S/FTP',
      use: 'Preferred for PoE++ APs',
    ),
    // Cat7 / Cat7A DEMOTED out of the peer-category rows (Keith's decision,
    // Wave-2 finding B): they are ISO/IEC Class F / FA, never TIA-recognized,
    // and use non-RJ45 connectors (GG45/TERA). The old Cat7A "40 Gbps" cell was
    // also flat wrong (no ratified standard put 40G on Cat7A; IEEE put 40G on
    // Cat8). They now live in the warning card (cat7Caveat) only, not as peer
    // rows beside real TIA categories. See cat7Caveat below.
    EthCable(
      category: 'Cat8',
      maxMhz: 2000,
      maxSpeed: '25/40 Gbps',
      dist1g: '100m',
      dist10g: '100m',
      poe: 'Limited',
      shielding: 'S/FTP',
      use: 'Data center short runs; 25/40G design rate to 30 m',
    ),
  ];

  /// BASE-T speed grades — the multi-gig rates (2.5G/5G) that fill the gap
  /// between 1G and 10G, with 1G and 10G as anchors. Per IEEE 802.3ab
  /// (1000BASE-T), 802.3bz-2016 (2.5G/5G), and 802.3an (10GBASE-T).
  static const List<EthSpeedGrade> speedGrades = <EthSpeedGrade>[
    EthSpeedGrade(
      standard: '1000BASE-T',
      speed: '1 Gbps',
      minCabling: 'Cat5e',
      maxDistance: '100m',
      ieeeSpec: '802.3ab (1999)',
    ),
    EthSpeedGrade(
      standard: '2.5GBASE-T',
      speed: '2.5 Gbps',
      minCabling: 'Cat5e',
      maxDistance: '100m',
      ieeeSpec: '802.3bz (2016)',
    ),
    EthSpeedGrade(
      standard: '5GBASE-T',
      speed: '5 Gbps',
      minCabling: 'Cat6',
      maxDistance: '100m',
      ieeeSpec: '802.3bz (2016)',
    ),
    EthSpeedGrade(
      standard: '10GBASE-T',
      speed: '10 Gbps',
      minCabling: 'Cat6A',
      maxDistance: '100m',
      ieeeSpec: '802.3an (2006)',
    ),
  ];

  /// Footnote for the speed-grade table — why the multi-gig rates exist, and
  /// which Cat6 10G distance to actually design to.
  ///
  /// The 10G-over-Cat6 reach is a RANGE, and the two ends are far apart enough
  /// to decide an install: 55 m only holds when alien crosstalk is favorable,
  /// and the planning distance in a dense bundle drops to 37 m. Quoting the
  /// 55 m figure alone (as this screen used to) hands a designer the best case
  /// as if it were the spec.
  static const String speedGradesFootnote =
      '2.5GBASE-T and 5GBASE-T (both 802.3bz) light up speeds above 1G on '
      'already-installed twisted pair without a Cat6A re-pull. 2.5G runs on '
      'Cat5e to 100 m; 5G is specified for Cat6 to 100 m. 10GBASE-T on Cat6 is '
      'reach-limited by alien crosstalk: about 55 m in the favorable case, but '
      'the dense-bundle planning distance is 37 m - design to 37 m unless the '
      'bundle is known to be loose. 10GBASE-T reaches the full 100 m channel '
      'only on Cat6A, which removes the concern entirely.';

  /// ISO/IEC 11801 shielding codes — the `[overall]/[per-pair]TP` notation.
  static const List<ShieldingCode> shieldingCodes = <ShieldingCode>[
    ShieldingCode(
      code: 'U/UTP',
      overall: 'None',
      perPair: 'None',
      name: 'Unshielded twisted pair',
    ),
    ShieldingCode(
      code: 'F/UTP',
      overall: 'Foil',
      perPair: 'None',
      name: 'Foil-screened, unshielded pairs (a.k.a. FTP)',
    ),
    ShieldingCode(
      code: 'S/FTP',
      overall: 'Braid',
      perPair: 'Foil per pair',
      name: 'Overall braid + per-pair foil (common Cat6A/Cat7)',
    ),
    ShieldingCode(
      code: 'SF/UTP',
      overall: 'Braid + Foil',
      perPair: 'None',
      name: 'Braid-and-foil overall screen, unshielded pairs',
    ),
    ShieldingCode(
      code: 'U/FTP',
      overall: 'None',
      perPair: 'Foil per pair',
      name: 'Individually foil-shielded pairs, no overall screen',
    ),
  ];

  /// Legend key for the shielding table.
  static const String shieldingFootnote =
      'Format is [overall screen]/[per-pair screen]TP. U = unshielded, F = foil, '
      'S = braided screen, TP = twisted pair. The character before the slash is '
      'the cable-level (overall) screen; the character(s) after describe the '
      'pair-level screen.';

  /// Cat 7 / Cat 7A caveat — ISO/IEC Class F/FA, NOT TIA categories. Surfaced
  /// as a warning verdict (glyph + word, §8.13). These were demoted out of the
  /// peer-category table (Wave-2 finding B) so they no longer read as TIA
  /// categories beside Cat6A/Cat8; this note is where they now live.
  static const String cat7Caveat =
      'Cat7 and Cat7A are ISO/IEC classes (Class F / FA) that TIA never '
      'recognized, and they use GG45 / TERA connectors, not native RJ-45. They '
      'are not shown as peer categories above. For 10G use Cat6A (the '
      'TIA-recognized 10G choice); for 25/40G short runs use Cat8. (There was '
      'never a ratified 40G standard on Cat7A - IEEE put 40GBASE-T on Cat8.)';

  /// PoE++ footnote. The "PoE (recommended)" column is guidance, not a
  /// capability limit: 802.3bt (up to 90 W) runs over Cat5e and up, so no
  /// category "cannot do" PoE++. The driver is bundle heat, which is why Cat6A
  /// is recommended. (Wave-2 finding B: the real constraint is heat, not
  /// category.)
  static const String footnote =
      'The "PoE (recommended)" column is guidance, not a capability limit: '
      '802.3bt (PoE++, up to 90 W) runs over Cat5e and every category above it, '
      'so no category is barred from PoE++. The real constraint is bundle heat. '
      'PoE++ tip: use Cat6A for 802.3bt deployments - bundled Cat6 cables '
      'running PoE++ generate significant heat, and Cat6A\'s larger conductor '
      'and diameter dissipate it better. TIA-568 recommends Cat6A for PoE++ in '
      'cable bundles. Cat8 carries 1G/10G to the full 100 m channel; its '
      '25G/40G design rate is limited to ~30 m (data-center top-of-rack).';

  // ── RJ-45 pinout dataset (public, const, unit-testable) ───────────────────

  /// Pin → wire-color → pair → function, per standard. Ported VERBATIM from
  /// the RF Tools PWA app.js `const PINOUT`. Hex values are the PWA's literal
  /// wire-color hexes (data glyphs). Do not edit without re-checking the PWA.
  static const Map<WiringStandard, List<PinoutPin>> pinout = {
    WiringStandard.t568b: [
      PinoutPin(
        pin: 1,
        colorHex: 0xFFE65100,
        colorName: 'Orange / White',
        pair: 2,
        function: 'TX+',
      ),
      PinoutPin(
        pin: 2,
        colorHex: 0xFFE65100,
        colorName: 'Orange',
        pair: 2,
        function: 'TX-',
      ),
      PinoutPin(
        pin: 3,
        colorHex: 0xFF2E7D32,
        colorName: 'Green / White',
        pair: 3,
        function: 'RX+',
      ),
      PinoutPin(
        pin: 4,
        colorHex: 0xFF1565C0,
        colorName: 'Blue',
        pair: 1,
        function: 'BI-D A+',
      ),
      PinoutPin(
        pin: 5,
        colorHex: 0xFF1565C0,
        colorName: 'Blue / White',
        pair: 1,
        function: 'BI-D A-',
      ),
      PinoutPin(
        pin: 6,
        colorHex: 0xFF2E7D32,
        colorName: 'Green',
        pair: 3,
        function: 'RX-',
      ),
      PinoutPin(
        pin: 7,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown / White',
        pair: 4,
        function: 'BI-D B+',
      ),
      PinoutPin(
        pin: 8,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown',
        pair: 4,
        function: 'BI-D B-',
      ),
    ],
    WiringStandard.t568a: [
      PinoutPin(
        pin: 1,
        colorHex: 0xFF2E7D32,
        colorName: 'Green / White',
        pair: 3,
        function: 'TX+',
      ),
      PinoutPin(
        pin: 2,
        colorHex: 0xFF2E7D32,
        colorName: 'Green',
        pair: 3,
        function: 'TX-',
      ),
      PinoutPin(
        pin: 3,
        colorHex: 0xFFE65100,
        colorName: 'Orange / White',
        pair: 2,
        function: 'RX+',
      ),
      PinoutPin(
        pin: 4,
        colorHex: 0xFF1565C0,
        colorName: 'Blue',
        pair: 1,
        function: 'BI-D A+',
      ),
      PinoutPin(
        pin: 5,
        colorHex: 0xFF1565C0,
        colorName: 'Blue / White',
        pair: 1,
        function: 'BI-D A-',
      ),
      PinoutPin(
        pin: 6,
        colorHex: 0xFFE65100,
        colorName: 'Orange',
        pair: 2,
        function: 'RX-',
      ),
      PinoutPin(
        pin: 7,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown / White',
        pair: 4,
        function: 'BI-D B+',
      ),
      PinoutPin(
        pin: 8,
        colorHex: 0xFF6D4C41,
        colorName: 'Brown',
        pair: 4,
        function: 'BI-D B-',
      ),
    ],
  };

  /// Pair number → wire-color hex. Verbatim from the PWA `pairCols` in
  /// buildPinoutTable. Data glyph, not a GL-003 token.
  static const Map<int, int> pairColors = {
    1: 0xFF1565C0, // Blue
    2: 0xFFE65100, // Orange
    3: 0xFF2E7D32, // Green
    4: 0xFF6D4C41, // Brown
  };

  /// Plug-orientation note, verbatim from the PWA pinout view.
  static const String orientationNote =
      'Plug face view. Clip facing down. Pin 1 is on the left.';

  /// Pinout footnote, verbatim from the PWA buildPinoutTable. The PWA's em dash
  /// is replaced with a comma per the no-em-dash hard rule.
  static const String pinoutFootnote =
      'Applies to Cat5, Cat5e, Cat6, Cat6A, Cat7, and Cat8. A crossover cable '
      'uses T568A on one end and T568B on the other, rarely needed today since '
      'most switches and NICs auto-MDI-X. T568A and T568B differ only in '
      'swapping the green and orange pairs.';

  @override
  State<EthernetCableScreen> createState() => _EthernetCableScreenState();
}

class _EthernetCableScreenState extends State<EthernetCableScreen> {
  WiringStandard _std = WiringStandard.t568b;

  static String _label(WiringStandard s) =>
      s == WiringStandard.t568b ? 'T568B' : 'T568A';

  void _onStandardChanged(WiringStandard next) {
    if (next == _std) return;
    setState(() => _std = next);
    // WCAG 4.1.3 — announce which standard's table is now shown.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_label(next)} pinout',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ethernet Cable & Connector'),
        toolbarHeight: 64,
        // §8.16 — copy the full reference (categories + pinout) as TSV. Static
        // data, always enabled.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the whole reference as TSV: the categories table
  /// (eight columns, including the typical-use column the scroll table drops to
  /// the footnote), the BASE-T speed grades, the shielding codes, the notes,
  /// and the SELECTED pinout standard's pin → wire → pair → function rows.
  /// Always non-null: the dataset is static, so copy is never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ethernet Cable & Connector')
      ..writeln()
      ..writeln('Cable categories')
      ..writeln(
        <String>[
          'Category',
          'MHz',
          'Max speed',
          '@1G',
          '@10G',
          'PoE (recommended)',
          'Shielding',
          'Typical use',
        ].join(tab),
      );
    for (final EthCable e in EthernetCableScreen.ethData) {
      buf.writeln(
        <String>[
          e.category,
          '${e.maxMhz}',
          e.maxSpeed,
          e.dist1g,
          e.dist10g,
          e.poe,
          e.shielding,
          e.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('BASE-T speed grades')
      ..writeln(
        <String>[
          'Standard',
          'Speed',
          'Min cabling',
          'Max distance',
          'IEEE spec',
        ].join(tab),
      );
    for (final EthSpeedGrade g in EthernetCableScreen.speedGrades) {
      buf.writeln(
        <String>[
          g.standard,
          g.speed,
          g.minCabling,
          g.maxDistance,
          g.ieeeSpec,
        ].join(tab),
      );
    }
    buf.writeln(EthernetCableScreen.speedGradesFootnote);
    buf
      ..writeln()
      ..writeln('Shielding codes (ISO/IEC 11801)')
      ..writeln(<String>['Code', 'Overall', 'Per pair', 'Name'].join(tab));
    for (final ShieldingCode s in EthernetCableScreen.shieldingCodes) {
      buf.writeln(<String>[s.code, s.overall, s.perPair, s.name].join(tab));
    }
    buf.writeln(EthernetCableScreen.shieldingFootnote);
    buf
      ..writeln()
      ..writeln('Notes')
      ..writeln('Cat7 / Cat7A: ISO/IEC Class F/FA, not TIA categories.')
      ..writeln(EthernetCableScreen.cat7Caveat)
      ..writeln(EthernetCableScreen.footnote);
    // The selected RJ-45 pinout standard.
    final List<PinoutPin> pins = EthernetCableScreen.pinout[_std]!;
    buf
      ..writeln()
      ..writeln('${_label(_std)} RJ-45 pinout (pin to pair)')
      ..writeln(
        <String>['Pin', 'Wire color', 'Pair', '100/1000 Base-T'].join(tab),
      );
    for (final PinoutPin p in pins) {
      buf.writeln(
        <String>['${p.pin}', p.colorName, '${p.pair}', p.function].join(tab),
      );
    }
    buf.writeln(EthernetCableScreen.pinoutFootnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
                    toolId: 'ethernet-cable',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ethernet-cable'))
                    const SizedBox(height: AppSpacing.md),
                  // ── Section 1: Cable categories ──
                  _SectionHeader(label: 'Cable categories'),
                  const SizedBox(height: AppSpacing.sm),
                  _tableCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _speedGradesCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _shieldingCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _cat7CaveatCard(colors, text),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(colors, text),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Section 2: RJ-45 pinout ──
                  _SectionHeader(label: 'RJ-45 pinout'),
                  const SizedBox(height: AppSpacing.sm),
                  _standardCard(colors, text),
                  const SizedBox(height: AppSpacing.sm),
                  _pinoutCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'ethernet-cable'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${EthernetCableScreen.ethData.length} cable categories',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Horizontal scroll: seven columns exceed phone width, so the data
          // table scrolls sideways inside the fixed card (mcs_index idiom).
          HorizontalScrollTable(child: _dataTable(colors, text, mono)),
        ],
      ),
    );
  }

  Widget _dataTable(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle cellStyle = (text.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
    );
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);

    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 56,
      columnSpacing: AppSpacing.md,
      horizontalMargin: 0,
      dividerThickness: 1,
      headingTextStyle: headStyle,
      columns: const [
        DataColumn(label: Text('Cat')),
        DataColumn(label: Text('MHz'), numeric: true),
        DataColumn(label: Text('Max Speed')),
        DataColumn(label: Text('@1G')),
        DataColumn(label: Text('@10G')),
        // "PoE (recommended)" not "PoE" (Wave-2 finding B): the column is
        // guidance, not capability. 802.3bt is not category-gated; the real
        // constraint is bundle heat (see footnote).
        DataColumn(label: Text('PoE (rec.)')),
        DataColumn(label: Text('Shielding')),
      ],
      rows: EthernetCableScreen.ethData.map((EthCable e) {
        // DataTable renders each DataCell as its own column node, so a screen
        // reader would otherwise read "Cat6A", "500", "10 Gbps"… as seven
        // disconnected nodes. We give the FIRST cell the full row summary via
        // Semantics(label:) and exclude the remaining cells from semantics, so
        // the row announces once as a coherent unit. (Vera F-02.)
        final String summary = rowLabel(e.category, <String?>[
          '${e.maxMhz} megahertz',
          'max speed ${e.maxSpeed}',
          e.dist1g == 'N/A' ? null : '${e.dist1g} at 1 gigabit',
          e.dist10g == 'N/A' ? null : '${e.dist10g} at 10 gigabit',
          'PoE ${e.poe}',
          'shielding ${e.shielding}',
        ]);
        return DataRow(
          cells: [
            DataCell(
              Semantics(
                label: summary,
                container: true,
                child: ExcludeSemantics(
                  child: Text(
                    e.category,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${e.maxMhz}',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(child: Text(e.maxSpeed, style: cellStyle)),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  e.dist1g,
                  style: mono.inlineCode.copyWith(
                    color: e.dist1g == 'N/A'
                        ? colors.textTertiary
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  e.dist10g,
                  style: mono.inlineCode.copyWith(
                    color: e.dist10g == 'N/A'
                        ? colors.textTertiary
                        : colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(ExcludeSemantics(child: Text(e.poe, style: smallStyle))),
            DataCell(
              ExcludeSemantics(child: Text(e.shielding, style: smallStyle)),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _speedGradesCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
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
            'BASE-T speed grades',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Standard')),
                DataColumn(label: Text('Speed')),
                DataColumn(label: Text('Min cabling')),
                DataColumn(label: Text('Max dist')),
                DataColumn(label: Text('IEEE spec')),
              ],
              rows: EthernetCableScreen.speedGrades.map((EthSpeedGrade g) {
                final String summary = rowLabel(g.standard, <String?>[
                  'speed ${g.speed}',
                  'minimum cabling ${g.minCabling}',
                  'max distance ${g.maxDistance}',
                  'spec ${g.ieeeSpec}',
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            g.standard,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          g.speed,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(g.minCabling, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          g.maxDistance,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(g.ieeeSpec, style: smallStyle),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            EthernetCableScreen.speedGradesFootnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _shieldingCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
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
            'Shielding codes (ISO/IEC 11801)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Code')),
                DataColumn(label: Text('Overall')),
                DataColumn(label: Text('Per pair')),
                DataColumn(label: Text('Name')),
              ],
              rows: EthernetCableScreen.shieldingCodes.map((ShieldingCode s) {
                final String summary = rowLabel(s.code, <String?>[
                  'overall screen ${s.overall}',
                  'per-pair screen ${s.perPair}',
                  s.name,
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            s.code,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(s.overall, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(s.perPair, style: smallStyle),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          s.name,
                          style: text.labelMedium?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            EthernetCableScreen.shieldingFootnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Cat 7 caveat as a warning verdict card (glyph + word, §8.13). Salvaged
  /// from the merged cable-connector tile.
  Widget _cat7CaveatCard(AppColorScheme colors, TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cat7 / Cat7A: ISO/IEC Class F/FA, not TIA categories',
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  EthernetCableScreen.cat7Caveat,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footnoteCard(AppColorScheme colors, TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            EthernetCableScreen.footnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The "typical use" column is dropped from the scroll table to keep
          // the row legible; surface it here so no PWA data is lost.
          ...EthernetCableScreen.ethData.map(
            (EthCable e) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                  children: [
                    TextSpan(
                      text: '${e.category}: ',
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: e.use),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The standard-selector card: T568B / T568A toggle + the plug-orientation
  /// note. Folded in from the merged ethernet-pinout tile.
  Widget _standardCard(AppColorScheme colors, TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Standard',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // T568B / T568A — two short options, segmented toggle (§8.14).
          _StandardToggle(value: _std, onChanged: _onStandardChanged),
          const SizedBox(height: AppSpacing.sm),
          Text(
            EthernetCableScreen.orientationNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _pinoutCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    final List<PinoutPin> pins = EthernetCableScreen.pinout[_std]!;
    return _TableCard(
      title: '${_label(_std)}: pin to pair',
      footnote: EthernetCableScreen.pinoutFootnote,
      header: const Row(
        children: [
          _HeaderCell('Pin', width: 40),
          _HeaderCell('Wire color', width: 152),
          _HeaderCell('Pair', width: 64),
          _HeaderCell('100/1000 Base-T', width: 120),
        ],
      ),
      rows: pins.map((p) => _PinRow(pin: p, mono: mono)).toList(),
    );
  }
}

/// A section divider header — bigger than the per-card label, marks the two
/// top-level sections (Cable categories / RJ-45 pinout) as a header for AT.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: (text.titleSmall ?? const TextStyle()).copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shared card chrome for the pinout table: title, horizontal-scroll grid
/// (header + rows), footnote. Mirrors the wifi_channels `_TableCard` idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

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
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Fixed-width cells inside a horizontal scroll: children of a
          // horizontal SingleChildScrollView get unbounded width, so
          // IntrinsicWidth lets every Row shrink-wrap its fixed-width cells
          // and share one common width — columns align and nothing is pinned
          // to a guessed (too-small) value that would overflow. Title and
          // footnote stay full-width and wrap.
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, mono-caption styled to align with the data cells.
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

/// One pin row: pin number, wire-color swatch + name, pair swatch + number,
/// Base-T function. Swatch fills are DATA glyphs (real wire colors), not UI
/// tokens.
class _PinRow extends StatelessWidget {
  const _PinRow({required this.pin, required this.mono});

  final PinoutPin pin;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool striped = pin.colorName.contains('/');
    // Pin function and pair carried by text, so the color swatch is never the
    // only signal (§8.13 rule 2 / WCAG 1.4.1).
    return Semantics(
      label:
          'Pin ${pin.pin}, ${pin.colorName}, pair ${pin.pair}, ${pin.function}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${pin.pin}',
                  style: mono.inlineCode.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 152,
                child: Row(
                  children: [
                    _WireSwatch(colorHex: pin.colorHex, striped: striped),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        pin.colorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 64,
                child: Row(
                  children: [
                    _WireSwatch(
                      colorHex: EthernetCableScreen.pairColors[pin.pair]!,
                      striped: false,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${pin.pair}',
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  pin.function,
                  style: mono.inlineCode.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wire-color swatch. Solid for a single-color wire; a 135° split (color over
/// white) for a striped wire — mirrors the PWA's linear-gradient wire dot. The
/// fill is the literal copper-pair color (a data glyph), bordered with a
/// low-alpha hairline like the PWA so a near-white wire reads on dark.
class _WireSwatch extends StatelessWidget {
  const _WireSwatch({required this.colorHex, required this.striped});

  final int colorHex;
  final bool striped;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color wire = Color(colorHex);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Hairline keeps the swatch visible on the dark card (§8.1 decorative
        // border is correct here — the swatch is non-interactive).
        border: Border.all(color: colors.border, width: 1),
        gradient: striped
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.5, 0.5],
                // Canonical T568 data swatch (§8.6.2 / §8.20.7 exception): the
                // striped half is the literal "white" of a white/colour pair,
                // the same data-glyph status as the wire hexes themselves. It
                // stays literal white in both themes (the 1px border keeps it
                // visible on the white light card), never a theme token.
                colors: [wire, const Color(0xFFFFFFFF)],
              )
            : null,
        color: striped ? null : wire,
      ),
    );
  }
}

/// Segmented standard toggle (T568B / T568A). Mirrors the wifi_channels
/// `_BandToggle` idiom (§8.14: a Toggle is correct for 2–3 short options).
class _StandardToggle extends StatelessWidget {
  const _StandardToggle({required this.value, required this.onChanged});

  final WiringStandard value;
  final ValueChanged<WiringStandard> onChanged;

  static const List<(WiringStandard, String)> _options = [
    (WiringStandard.t568b, 'T568B'),
    (WiringStandard.t568a, 'T568A'),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Row(
        children: _options.map((opt) {
          final bool selected = opt.$1 == value;
          // Each segment flexes to share the row width so the two chips never
          // overflow a narrow phone surface.
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onChanged(opt.$1),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: selected
                          ? colors.onPrimary
                          : colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
