// Rack Units & Mounting Hardware — read-only reference for the dimensions and
// mounting hardware a network/Wi-Fi installer meets at a 19-inch rack.
//
// The rack standard is dimensionally settled and safe to ship: 1U = 1.75 in =
// 44.45 mm exactly, by definition (EIA-310-D / IEC 60297). The two field traps
// this page exists to fix are the irregular vertical hole pattern (0.5 / 0.625 /
// 0.625 in per U, NOT evenly spaced) and the mounting hardware (10-32 vs 12-24
// vs M6 look alike but cross-thread and strip if forced; many racks ship as bare
// square holes needing cage nuts you must supply).
//
// Sections, conclusion-first:
//   (a) U conversion table — U -> inches -> mm, exact arithmetic from the
//       defined base. Horizontal-scroll, fixed-width cells (overflow-safe).
//   (b) Rack widths — the "19-inch is only the front panel" insight: holes on
//       18.312-in centers, opening >= 17.72 in. Nothing inside is 19 inches.
//   (c) EIA-310 vertical hole pattern — the load-bearing one; renders the 1U
//       dimension concept graphic (rack-1u-dimension) beside the explanation.
//   (d) Mounting hardware — thread types (10-32 / 12-24 / M6), rail types
//       (tapped / square-hole cage nut / unthreaded), the cage-nut concept
//       graphic (rack-cage-nut), and the two anti-patterns.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-rack-units-reference/RESEARCH-BRIEF.md). Facts only,
// triangulated across >=2 independent sources. The brief's caveats are honored
// verbatim:
//   * Per-vendor thread mapping is "commonly", never "always" (vendor
//     conventions drift across product generations).
//   * 42U is the reference full rack; 45U is presented as a taller variant, not
//     "common".
//   * The headline horizontal hole spacing is 18.312 in (465.1 mm), the
//     most-cited value (sources vary 464.2-465.8 mm).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; each concept-graphic
// slot carries its own absent-asset empty state (render nothing). GL-008
// network/subprocess rules do not apply (nothing fetched, nothing shelled out).
//
// Glyph / voice notes (GL-004): no em dash anywhere (ASCII hyphen-minus only);
// "Wi-Fi" never "WiFi"; US spelling; conclusion-first prose. Identifiers and
// dimensions render in DM Mono (the app numeric register); words in IBM Plex
// Sans (the body text theme).

import 'package:flutter/material.dart';

import '../../../data/rack_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One row of the U -> inches -> mm conversion table. Values are exact
/// arithmetic from the defined base (1U = 1.75 in = 44.45 mm); never rounded.
@immutable
class RackUnitRow {
  const RackUnitRow({
    required this.u,
    required this.inches,
    required this.mm,
    this.note = '',
  });

  /// Unit count label, e.g. `1U`.
  final String u;

  /// Height in inches, exact, e.g. `1.75`.
  final String inches;

  /// Height in millimetres, exact, e.g. `44.45`.
  final String mm;

  /// Optional field note, e.g. `standard full rack`.
  final String note;
}

/// One mounting-thread type. Per-vendor mapping is "commonly", never "always"
/// (research-brief caveat).
@immutable
class RackThread {
  const RackThread({
    required this.thread,
    required this.diameter,
    required this.pitch,
    required this.seenOn,
  });

  /// Thread designation, e.g. `10-32`.
  final String thread;

  /// Major diameter, e.g. `0.190 in`.
  final String diameter;

  /// Threads-per-inch or metric pitch, e.g. `32 TPI`.
  final String pitch;

  /// Where it is commonly seen (vendor convention, drifts over time).
  final String seenOn;
}

/// One rail/hole type — how you actually mount gear to it.
@immutable
class RackRailType {
  const RackRailType({
    required this.type,
    required this.mount,
    required this.tradeoff,
  });

  /// Rail/hole type, e.g. `Square hole + cage nut`.
  final String type;

  /// How you mount to it.
  final String mount;

  /// The pro/con in one line.
  final String tradeoff;
}

class RackUnitsScreen extends StatelessWidget {
  const RackUnitsScreen({super.key});

  // --- (a) U conversion table ------------------------------------------------

  /// U -> inches -> mm. Exact arithmetic from the defined base (1U = 1.75 in =
  /// 44.45 mm). Verified against the research brief (Section 1). Do not
  /// introduce a rounded mm-per-U constant: these are exact.
  static const List<RackUnitRow> conversions = <RackUnitRow>[
    RackUnitRow(u: '1U', inches: '1.75', mm: '44.45', note: 'base unit'),
    RackUnitRow(u: '2U', inches: '3.50', mm: '88.90'),
    RackUnitRow(u: '3U', inches: '5.25', mm: '133.35'),
    RackUnitRow(u: '4U', inches: '7.00', mm: '177.80'),
    RackUnitRow(u: '6U', inches: '10.50', mm: '266.70', note: 'small wall-mount'),
    RackUnitRow(u: '8U', inches: '14.00', mm: '355.60'),
    RackUnitRow(
      u: '12U',
      inches: '21.00',
      mm: '533.40',
      note: 'common wall / half-height',
    ),
    RackUnitRow(u: '24U', inches: '42.00', mm: '1066.80', note: 'half-rack'),
    RackUnitRow(
      u: '42U',
      inches: '73.50',
      mm: '1866.90',
      note: 'standard full rack',
    ),
    RackUnitRow(
      u: '45U',
      inches: '78.75',
      mm: '2000.25',
      note: 'taller data-center cabinet',
    ),
    RackUnitRow(
      u: '48U',
      inches: '84.00',
      mm: '2133.60',
      note: 'extra-tall cabinet',
    ),
  ];

  /// Caption for the conversion table — names the live formula so the page is
  /// not just a lookup. Verified (research brief Section 1).
  static const String conversionNote =
      'Exact by definition: inches = U x 1.75, mm = U x 44.45. EIA-310-D and '
      'IEC 60297 both fix 1U at 1.75 in = 44.45 mm. 42U is the standard full '
      'rack (about 6 ft of rail); 45U and 48U are taller data-center variants.';

  // --- (b) Rack widths -------------------------------------------------------

  /// The "19-inch is only the front panel" insight, stated conclusion-first.
  /// Verified (research brief Section 2). Headline horizontal hole spacing is
  /// 18.312 in (465.1 mm), the most-cited value.
  static const String widthsHeadline =
      '"19-inch" describes only the front panel width. Nothing inside the rack '
      'is 19 inches.';

  /// The three width facts that follow the headline.
  static const List<RackUnitRow> widthFacts = <RackUnitRow>[
    RackUnitRow(
      u: 'Front panel',
      inches: '19',
      mm: '482.6',
      note: 'flange / panel width only',
    ),
    RackUnitRow(
      u: 'Hole spacing',
      inches: '18.312',
      mm: '465.1',
      note: 'mounting holes, center-to-center',
    ),
    RackUnitRow(
      u: 'Rack opening',
      inches: '17.72',
      mm: '450',
      note: 'minimum usable between posts',
    ),
  ];

  /// The 23-inch telecom aside, kept brief and labeled legacy per the brief.
  static const String widthsTelecomNote =
      'A separate 23-inch telecom format exists in legacy ILEC/CLEC central '
      'offices (Western Electric holes on 1-in centers). It is not compatible '
      'with 19-inch gear, and several incompatible 23-inch conventions exist. '
      'Universal IT and Wi-Fi gear is 19-inch.';

  // --- (c) EIA-310 vertical hole pattern (the load-bearing one) -------------

  /// Conclusion-first explanation of the irregular vertical hole pattern.
  /// Verified across 4 independent sources (research brief Section 3).
  static const String holePatternHeadline =
      'Rack holes are NOT evenly spaced. Within each 1U the three holes repeat '
      'at 0.5 / 0.625 / 0.625 in, and the U boundary falls in the middle of the '
      '0.5-in gap.';

  /// The supporting detail beneath the headline.
  static const String holePatternBody =
      'A correct 1U faceplate uses the outer two holes of its group of three '
      '(the pair separated by 0.5 in across the U boundary above and below). '
      'Count holes wrong by one and the panel binds, so multi-U gear with '
      'evenly-spaced holes will not line up. After thread mismatch, this is the '
      'most common "why will this not mount" problem. In millimetres: 0.5 in = '
      '12.70 mm, 0.625 in = 15.88 mm.';

  // --- (d) Mounting hardware -------------------------------------------------

  /// Thread types. Per-vendor mapping is "commonly", never "always" (brief
  /// caveat, Section 4.1). M5 is omitted as field-rare; M6 is the metric one to
  /// teach.
  static const List<RackThread> threads = <RackThread>[
    RackThread(
      thread: '10-32',
      diameter: '0.190 in',
      pitch: '32 TPI',
      seenOn: 'Commonly Dell gear, audio/AV racks, lighter equipment',
    ),
    RackThread(
      thread: '12-24',
      diameter: '0.216 in',
      pitch: '24 TPI',
      seenOn: 'Commonly older general-purpose racks; the historical default',
    ),
    RackThread(
      thread: 'M6',
      diameter: '~6 mm',
      pitch: '1.0 mm',
      seenOn: 'Commonly HP/Compaq gear and modern square-hole + cage-nut setups',
    ),
  ];

  /// The thread-incompatibility gotcha, stated up front. Verified (Section 4.1).
  static const String threadGotcha =
      '10-32, 12-24, and M6 are NOT interchangeable. They are close enough to '
      'start in the wrong hole, then cross-thread and strip if forced. A 12-24 '
      'screw forced into a 10-32 tapped hole destroys the thread, and a stripped '
      'tapped rail is unmountable without a workaround or rail replacement. '
      'Match the screw to the rack tap, or to the cage nut you installed.';

  /// Rail/hole types — tapped vs cage-nut vs unthreaded. Verified (Section 4.2).
  static const List<RackRailType> railTypes = <RackRailType>[
    RackRailType(
      type: 'Tapped (threaded round holes)',
      mount: 'Screw goes straight in',
      tradeoff:
          'Fast, no extra parts; but fixed to ONE thread type, and a stripped '
          'thread kills that position.',
    ),
    RackRailType(
      type: 'Square hole + cage nut',
      mount: 'Clip a cage nut into the square hole, then screw into it',
      tradeoff:
          'Thread-agnostic (swap the cage nut) and strip-proof (replace the '
          'nut, not the rail); the modern standard. Slower and a touch fiddly.',
    ),
    RackRailType(
      type: 'Round unthreaded (universal)',
      mount: 'Accepts clip nuts, or needs a nut and bolt',
      tradeoff: 'Flexible; but you must bring the right nut hardware.',
    ),
  ];

  /// Cage-nut clarification rendered beside the cage-nut graphic.
  static const String cageNutNote =
      'A cage nut is a captive nut in a spring-steel cage that snaps into a '
      'square hole (about 3/8 in / 9.5 mm), converting it into a threaded hole '
      'of whatever spec you choose. A "universal rack" is a square-hole rack '
      'that accepts cage nuts of any thread, giving one frame compatibility '
      'with 10-32, 12-24, or M6 gear.';

  /// The two field anti-patterns, stated as the costliest assumptions. Verified
  /// (research brief Section 6, items 1 and 3).
  static const List<String> antiPatterns = <String>[
    'Assuming the rack is tapped. Many modern racks ship as bare square holes '
        'with no cage nuts included. Show up without cage nuts and you cannot '
        'mount anything. Confirm the rack hole type before install day.',
    'Mixing 10-32 and 12-24. They look near-identical and cross-thread when '
        'forced, the most damaging hardware error. Match the screw to the tap; '
        'when in doubt, use a square-hole rack with the right cage nut.',
  ];

  /// "U is height only" footnote — depth is an independent check.
  static const String depthFootnote =
      'U measures height only. A 1U switch and a 1U server can have very '
      'different depths, so depth is a separate check. Most Wi-Fi and network '
      'gear is shallow (a 600 mm / 23.6 in cabinet is usually fine), but always '
      'check usable rail-to-rail depth against the deepest device, with cables '
      'attached, before committing.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rack Units'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: U conversions, rack
        // widths, hole pattern, thread types, rail types, and the anti-patterns.
        // Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as sectioned TSV. ASCII-only (no em
  /// dash, no degree glyph); "x" for the multiply in the formula caption so the
  /// pasted text stays plain-text safe. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Rack Units & Mounting Hardware')
      ..writeln()
      ..writeln('U conversion (exact)')
      ..writeln(<String>['U', 'Inches', 'mm', 'Note'].join(tab));
    for (final RackUnitRow r in conversions) {
      buf.writeln(<String>[r.u, r.inches, r.mm, r.note].join(tab));
    }
    buf
      ..writeln()
      ..writeln(conversionNote)
      ..writeln()
      ..writeln('Rack widths')
      ..writeln(widthsHeadline)
      ..writeln(<String>['Dimension', 'Inches', 'mm', 'Note'].join(tab));
    for (final RackUnitRow r in widthFacts) {
      buf.writeln(<String>[r.u, r.inches, r.mm, r.note].join(tab));
    }
    buf
      ..writeln()
      ..writeln(widthsTelecomNote)
      ..writeln()
      ..writeln('EIA-310 vertical hole pattern')
      ..writeln(holePatternHeadline)
      ..writeln(holePatternBody)
      ..writeln()
      ..writeln('Mounting hardware - thread types')
      ..writeln(threadGotcha)
      ..writeln(
        <String>['Thread', 'Diameter', 'Pitch', 'Commonly seen on'].join(tab),
      );
    for (final RackThread t in threads) {
      buf.writeln(
        <String>[t.thread, t.diameter, t.pitch, t.seenOn].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Mounting hardware - rail types')
      ..writeln(<String>['Rail type', 'How you mount', 'Trade-off'].join(tab));
    for (final RackRailType rt in railTypes) {
      buf.writeln(<String>[rt.type, rt.mount, rt.tradeoff].join(tab));
    }
    buf
      ..writeln()
      ..writeln(cageNutNote)
      ..writeln()
      ..writeln('Anti-patterns');
    for (final String a in antiPatterns) {
      buf.writeln('- $a');
    }
    buf
      ..writeln()
      ..writeln(depthFootnote);
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
                  // (a) U conversion table.
                  _conversionCard(text, mono),
                  const SizedBox(height: AppSpacing.md),

                  // (b) Rack widths — the "19-inch is only the front panel" one.
                  _widthsCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),

                  // (c) EIA-310 vertical hole pattern — load-bearing; renders
                  // the 1U dimension concept graphic above the explanation. The
                  // graphic degrades to nothing when its SVG is not yet bundled,
                  // so the section reads as text alone until Charta's graphic
                  // lands.
                  _SectionHeading(label: 'EIA-310 vertical hole pattern'),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: RackDiagrams.rack1u,
                    path: RackDiagrams.path,
                    has: RackDiagrams.has,
                  ),
                  if (RackDiagrams.has(RackDiagrams.rack1u))
                    const SizedBox(height: AppSpacing.md),
                  _holePatternCard(colors, text),
                  const SizedBox(height: AppSpacing.md),

                  // (d) Mounting hardware — threads, then rail types with the
                  // cage-nut concept graphic, then the anti-patterns.
                  _SectionHeading(label: 'Mounting hardware'),
                  const SizedBox(height: AppSpacing.sm),
                  _threadCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  LargeGraphic(
                    assetName: RackDiagrams.cageNut,
                    path: RackDiagrams.path,
                    has: RackDiagrams.has,
                  ),
                  if (RackDiagrams.has(RackDiagrams.cageNut))
                    const SizedBox(height: AppSpacing.md),
                  _railTypeCard(colors, text),
                  const SizedBox(height: AppSpacing.md),
                  _antiPatternCard(colors, text),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(colors, text),

                  ToolHelpFooter(toolId: 'rack-units'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// (a) U -> inches -> mm — wider than a phone, so it scrolls horizontally with
  /// fixed-width cells (overflow-safe). The note wraps full-width below.
  Widget _conversionCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'U conversion (exact)',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ConversionHeaderRow(text: text),
                  const SizedBox(height: AppSpacing.xs),
                  for (final RackUnitRow r in conversions)
                    _ConversionRow(row: r, text: text, mono: mono),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NoteText(conversionNote),
        ],
      ),
    );
  }

  /// (b) Rack widths — headline insight, then the three width facts, then the
  /// telecom aside.
  Widget _widthsCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    return _Card(
      heading: 'Rack widths',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widthsHeadline,
            style: text.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _WidthHeaderRow(text: text),
                  const SizedBox(height: AppSpacing.xs),
                  for (final RackUnitRow r in widthFacts)
                    _WidthRow(row: r, text: text, mono: mono),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NoteText(widthsTelecomNote),
        ],
      ),
    );
  }

  /// (c) EIA-310 hole pattern — headline first, then the supporting detail. The
  /// dimensions inside the headline carry meaning, so the dimension figures sit
  /// in DM Mono via the body text otherwise. Kept as prose for readability; the
  /// graphic above carries the visual.
  Widget _holePatternCard(AppColorScheme colors, TextTheme text) {
    return _Card(
      heading: 'Why off-by-one binds',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            holePatternHeadline,
            style: text.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            holePatternBody,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// (d) Thread types — the incompatibility gotcha up front, then the table.
  Widget _threadCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    return _Card(
      heading: 'Thread types',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            threadGotcha,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ThreadHeaderRow(text: text),
                  const SizedBox(height: AppSpacing.xs),
                  for (final RackThread t in threads)
                    _ThreadRow(thread: t, text: text, mono: mono),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// (d) Rail types — full-width rows so the trade-off line wraps. The cage-nut
  /// clarification sits beneath.
  Widget _railTypeCard(AppColorScheme colors, TextTheme text) {
    return _Card(
      heading: 'Rail / hole types',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final RackRailType rt in railTypes)
            _RailTypeRow(railType: rt, text: text),
          const SizedBox(height: AppSpacing.xs),
          _NoteText(cageNutNote),
        ],
      ),
    );
  }

  /// (d) The two anti-patterns, stated as the costliest assumptions.
  Widget _antiPatternCard(AppColorScheme colors, TextTheme text) {
    return _Card(
      heading: 'Anti-patterns',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < antiPatterns.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Decorative bullet; the text beside it carries the meaning.
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: AppSpacing.xs),
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.priority_high,
                      size: AppTextSize.caption,
                      color: colors.textAccent,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    antiPatterns[i],
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _footnoteCard(AppColorScheme colors, TextTheme text) {
    return _Card(
      heading: 'Depth is a separate check',
      headingText: text,
      child: Text(
        depthFootnote,
        style: text.labelMedium?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// Shared card surface — matches the fiber / dB / port reference idiom.
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
          Text(
            heading,
            style: headingText.labelMedium?.copyWith(
              color: colors.textSecondary,
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

/// A section heading standing on the page background above a stacked graphic +
/// card group. Mirrors the IEC screen's _SectionHeading register.
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

/// A wrapping tertiary-ink note line, reused by every card footer.
class _NoteText extends StatelessWidget {
  const _NoteText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme theme = Theme.of(context).textTheme;
    return Text(
      text,
      style: theme.labelMedium?.copyWith(color: colors.textTertiary),
    );
  }
}

// Fixed cell widths for the horizontally-scrolled conversion + width grids.
// Constant so the header and every data row align column-for-column.
const double _kUW = 88;
const double _kInchW = 80;
const double _kMmW = 88;
const double _kNoteW = 200;

/// Column header for the U conversion matrix.
class _ConversionHeaderRow extends StatelessWidget {
  const _ConversionHeaderRow({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? style = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: _kUW, child: Text('U', style: style)),
          SizedBox(width: _kInchW, child: Text('Inches', style: style)),
          SizedBox(width: _kMmW, child: Text('mm', style: style)),
          SizedBox(width: _kNoteW, child: Text('Note', style: style)),
        ],
      ),
    );
  }
}

/// One row in the U conversion matrix. The U label and dimensions render in DM
/// Mono (the numeric register); the note wraps in body text.
class _ConversionRow extends StatelessWidget {
  const _ConversionRow({
    required this.row,
    required this.text,
    required this.mono,
  });

  final RackUnitRow row;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(row.u, <String?>[
        '${row.inches} inches',
        '${row.mm} millimetres',
        row.note.isEmpty ? null : row.note,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: _kUW,
              child: Text(
                row.u,
                style: mono.inlineCode.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _kInchW,
              child: Text(
                row.inches,
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kMmW,
              child: Text(
                row.mm,
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kNoteW,
              child: Text(
                row.note,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Column header for the rack-width matrix.
class _WidthHeaderRow extends StatelessWidget {
  const _WidthHeaderRow({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? style = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: _kNoteW, child: Text('Dimension', style: style)),
          SizedBox(width: _kInchW, child: Text('Inches', style: style)),
          SizedBox(width: _kMmW, child: Text('mm', style: style)),
        ],
      ),
    );
  }
}

/// One rack-width fact row. The label wraps in body text; the dimensions render
/// in DM Mono. The per-fact note wraps full-width beneath.
class _WidthRow extends StatelessWidget {
  const _WidthRow({
    required this.row,
    required this.text,
    required this.mono,
  });

  final RackUnitRow row;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(row.u, <String?>[
        '${row.inches} inches',
        '${row.mm} millimetres',
        row.note.isEmpty ? null : row.note,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: _kNoteW,
                  child: Text(
                    row.u,
                    style: text.bodyLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                SizedBox(
                  width: _kInchW,
                  child: Text(
                    row.inches,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: _kMmW,
                  child: Text(
                    row.mm,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.note,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Fixed cell widths for the horizontally-scrolled thread grid.
const double _kThreadW = 80;
const double _kDiaW = 88;
const double _kPitchW = 72;
const double _kSeenW = 280;

/// Column header for the thread-type matrix.
class _ThreadHeaderRow extends StatelessWidget {
  const _ThreadHeaderRow({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? style = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: _kThreadW, child: Text('Thread', style: style)),
          SizedBox(width: _kDiaW, child: Text('Diameter', style: style)),
          SizedBox(width: _kPitchW, child: Text('Pitch', style: style)),
          SizedBox(width: _kSeenW, child: Text('Commonly seen on', style: style)),
        ],
      ),
    );
  }
}

/// One thread-type row. The thread designation and specs render in DM Mono; the
/// "commonly seen on" note wraps in body text.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.text,
    required this.mono,
  });

  final RackThread thread;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(thread.thread, <String?>[
        'diameter ${thread.diameter}',
        'pitch ${thread.pitch}',
        thread.seenOn,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _kThreadW,
              child: Text(
                thread.thread,
                style: mono.inlineCode.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _kDiaW,
              child: Text(
                thread.diameter,
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kPitchW,
              child: Text(
                thread.pitch,
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kSeenW,
              child: Text(
                thread.seenOn,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One rail/hole-type row: type + how-you-mount on the top line, the trade-off
/// beneath. Full-width so both lines wrap (overflow-safe at phone width).
class _RailTypeRow extends StatelessWidget {
  const _RailTypeRow({required this.railType, required this.text});

  final RackRailType railType;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(railType.type, <String?>[
        railType.mount,
        railType.tradeoff,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              railType.type,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                railType.mount,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                railType.tradeoff,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
