// Antenna Fundamentals — a read-along teaching / reference screen for the
// Quick Reference category. NOT a calculator and NOT a how-to-with-download: it
// is Penn's approved, Keith-voice teaching copy (SOP-020 PASS) rendered verbatim
// with Charta's seven line diagrams embedded at their section markers.
//
// CONTENT IS APPROVED — rendered verbatim (only minimal formatting applied: the
// markdown structure becomes section cards, bullets become rows, the directional
// type table becomes a card-styled table, the through-line thesis becomes a
// pull-quote, the §8.13 mounting warning becomes a warning band). No copy is
// rewritten. The literal strings below are the on-screen copy from
// Deliverables/2026-06-05-antenna-fundamentals/teaching-copy.md.
//
// States (SOP-007 §5): this is a static reference screen with no inputs, no
// network, and no async data — the copy is compiled in. So the only states are:
//  - success → the full teaching scroll (the always-rendered state).
//  - the per-diagram band degrades gracefully: a diagram whose SVG is not in the
//    bundle (or fails to parse) renders nothing, never a broken-image box, so the
//    prose still reads end-to-end (loading/empty/error of the OPTIONAL art).
// There is no loading or error state for the copy itself (nothing to load); a
// disabled state does not apply (no interactive inputs). The one interactive
// element is the §8.16.1 "About this tool" footer, which carries its own §8.3
// focus ring.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw AppColors.*, no literal hex/px — so the screen renders
// correctly in both dark (§8) and light (§8.20). The seven diagrams are authored
// DARK-BAKED on the §8.20.7 allow-list hexes and recolor for light through the
// single source-of-truth swap ConceptGraphicBand.applyLightSwap (same path the
// concept graphics and the connector diagrams use), so no raw lime/scaffold
// stroke ever hits a light surface.
//
// ACCESSIBILITY: each section is a Semantics(header: true) landmark; the diagram
// bands are decorative (ExcludeSemantics + excludeFromSemantics) because every
// fact a diagram depicts is already in the prose (GL-003 §8.6.2 a11y rule). The
// thesis pull-quote and warning band carry text, never color-only meaning
// (§8.13).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/antenna_fundamentals_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;

/// Stable catalog tool id — backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kAntennaFundamentalsToolId = 'antenna-fundamentals';

class AntennaFundamentalsScreen extends StatelessWidget {
  const AntennaFundamentalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antenna Fundamentals'),
        toolbarHeight: 64,
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
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
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              children: <Widget>[
                // ── Section 0 — The one idea ──────────────────────────────
                const _Thesis(),
                const SizedBox(height: AppSpacing.md),
                const _Section(
                  number: '0',
                  title: 'The one idea',
                  paragraphs: <String>[
                    'An antenna is not a power booster. It is a shaper.',
                    'Take the same radio, leave the transmit power exactly where '
                        'it is, and point it through a different antenna. You '
                        'cover a completely different shape of space. The radio '
                        'did not get stronger. The energy just went somewhere '
                        'else. That is the whole job of an antenna, and it is the '
                        'whole point of this resource.',
                    'Here is the rule everything else hangs on: use the antenna '
                        'that covers what you want covered, without covering '
                        'areas you don’t want.',
                    'Two words do most of the work in antenna design, and most '
                        'antenna confusion is really confusion about those two '
                        'words, not about math. The next section gets us agreeing '
                        'on them: azimuth and elevation. Get those two straight '
                        'and the pattern charts stop being mysterious. By the end '
                        'of this you will be able to look at any antenna’s '
                        'pattern chart and know what it will cover and what it '
                        'will leave alone.',
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Section 1 — Azimuth and elevation ─────────────────────
                _Section(
                  number: '1',
                  title: 'Azimuth and elevation: the two planes',
                  leadingDiagram: 'g1-azimuth-vs-elevation',
                  isDesktop: isDesktop,
                  paragraphs: const <String>[
                    'An antenna’s coverage is a three-dimensional shape. We '
                        'describe that shape with two flat slices, taken at right '
                        'angles to each other.',
                  ],
                  bullets: const <_Bullet>[
                    _Bullet(
                      lead: 'Azimuth is the horizontal plane.',
                      rest: ' Stand on the ceiling and look straight down on the '
                          'antenna. The width of coverage in that top-down view '
                          'is the horizontal beamwidth.',
                    ),
                    _Bullet(
                      lead: 'Elevation is the vertical plane.',
                      rest: ' Step to the side and look at the antenna in '
                          'profile. The height of coverage in that side view is '
                          'the vertical beamwidth.',
                    ),
                  ],
                  trailingParagraphs: const <String>[
                    'A ceiling-mounted omni shows you both at once. In azimuth it '
                        'covers a full 360°, a circle on the floor all the '
                        'way around. In elevation it covers only a limited slice. '
                        'It does not fire much straight up or straight down. That '
                        'is why the client sitting directly under the AP can be '
                        'weaker than the one across the room.',
                  ],
                  midDiagram: 'g2-omni-donut',
                  afterMidParagraphs: const <String>[
                    'Now the load-bearing idea, the one a novice gets backward '
                        'and a pro never bothers to say because it is obvious to '
                        'them. Gain trades against beamwidth. Higher gain always '
                        'means a narrower beam. Gain does not add energy to the '
                        'radio. It takes the same energy and concentrates it into '
                        'a tighter shape. You get more reach where the beam is '
                        'pointed and less everywhere else. Gain is a shaping tool, '
                        'not a volume knob.',
                    'Watch what that does to an omni. Add gain and the donut '
                        'flattens into a pancake. A high-gain omni reaches farther '
                        'across a flat floor, but it covers a thinner vertical '
                        'slice. That is exactly right for a warehouse with a high '
                        'flat ceiling and long aisles. It is exactly wrong for a '
                        'multi-story building, where the flattened pattern sprays '
                        'down the floor it is on and starves the floors above and '
                        'below.',
                  ],
                  aside: const _Aside(
                    title: 'Read the spec, don’t derive it.',
                    body: '“More gain means a narrower beam” is always '
                        'directionally true. The exact beamwidth that comes with '
                        'a given gain depends on the specific antenna’s '
                        'design, so it is a rule of thumb, not a formula you can '
                        'run in your head. Trust the published beamwidth on the '
                        'antenna’s data sheet. Don’t try to back it out '
                        'of the gain number.',
                  ),
                  closer:
                      'The thesis, lived through this section: azimuth and '
                      'elevation are the two dials you turn to match coverage to '
                      'the room. Pick the beamwidths that fill the space you '
                      'want, and stop at the edges you don’t.',
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Section 2 — Orientation ───────────────────────────────
                _Section(
                  number: '2',
                  title: 'Orientation: mounting, polarization, and tilt',
                  isDesktop: isDesktop,
                  paragraphs: const <String>[
                    'Orientation is the cheapest coverage-shaping tool you own. '
                        'It costs nothing but getting it right, and getting it '
                        'wrong is the most common self-inflicted wound in the '
                        'field.',
                  ],
                  subsections: <_Subsection>[
                    _Subsection(
                      title: 'Polarization: match them, or pay',
                      leadingDiagram: 'g7-polarization',
                      isDesktop: isDesktop,
                      paragraphs: const <String>[
                        'Polarization is the orientation of the radio wave’s '
                            'electric field, and it is set by the physical '
                            'orientation of the antenna element. A vertical '
                            'antenna radiates a vertically polarized wave. Tip the '
                            'antenna over and you tip the wave with it.',
                        'Transmit and receive polarization should match. When '
                            'they line up, the signal transfers fully. When they '
                            'sit 90° apart, one vertical and one horizontal, '
                            'that is the worst case. In theory it is total loss. '
                            'In the real world, reflections and imperfect '
                            'alignment leave you some signal, but you are paying a '
                            'heavy, avoidable penalty. Ninety degrees is the '
                            'number to remember as “worst,” and you do '
                            'not have to be a physicist to avoid it.',
                        'Most Wi-Fi clients are phones and laptops held more or '
                            'less upright, so they are near-vertical most of the '
                            'time. That is why most APs are designed vertically '
                            'polarized: to match the devices they serve. '
                            'Orientation is not cosmetic. It is a signal-budget '
                            'decision.',
                      ],
                    ),
                    _Subsection(
                      title: 'The wall-clock mistake',
                      isDesktop: isDesktop,
                      paragraphs: const <String>[
                        'A ceiling-tuned omni is built to hang horizontally and '
                            'fire its donut out across the floor below it. That is '
                            'the shape it was designed to make.',
                        'Mount that same AP flat against a wall, like a clock, and '
                            'you rotate the whole pattern 90°. Two bad things '
                            'happen at once.',
                      ],
                      bullets: const <_Bullet>[
                        _Bullet(
                          rest: 'The strongest energy now fires up into the floor '
                              'above and down into the floor below. You are '
                              'covering exactly the two places you did not want '
                              'covered.',
                        ),
                        _Bullet(
                          rest: 'You have rotated the antenna’s polarization '
                              '90° relative to your upright clients, which '
                              'costs you roughly 6 dB right off the top.',
                        ),
                      ],
                      trailingParagraphs: const <String>[
                        'One wrong mounting decision breaks the thesis twice '
                            'over: wrong coverage shape, and a polarization '
                            'mismatch on top of it.',
                      ],
                      warning: 'Never mount an Access Point on a wall like a '
                          'clock.',
                    ),
                    _Subsection(
                      title: 'Tilt and downtilt',
                      isDesktop: isDesktop,
                      paragraphs: const <String>[
                        'Downtilt aims a directional antenna’s main lobe '
                            'below the horizon. Instead of throwing coverage '
                            'straight out at the far wall or the parking lot, you '
                            'push it down onto the floor or the service area where '
                            'the clients actually are.',
                      ],
                      midDiagram: 'g6-downtilt',
                      afterMidParagraphs: const <String>[
                        'A ceiling AP pointing straight down is just the extreme '
                            'case, effectively 90° of downtilt. On a high '
                            'mount, a warehouse, an atrium, a stadium, downtilt is '
                            'how you land the energy on the floor where the people '
                            'are instead of on a wall 40 feet up that nobody is '
                            'standing against.',
                      ],
                    ),
                  ],
                  closer:
                      'The thesis, lived through this section: mount the antenna '
                      'the way its pattern was designed, point the energy where '
                      'the clients are, and match the polarization. Get those '
                      'three right and you have shaped your coverage before you '
                      'have touched a single configuration setting.',
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Section 3 — How to read an antenna diagram ────────────
                _Section(
                  number: '3',
                  title: 'How to read an antenna diagram',
                  isDesktop: isDesktop,
                  introParagraphs: const <String>[
                    'This is the literacy section. Read it and a manufacturer’s '
                        'radiation-pattern chart stops being a Rorschach blot and '
                        'starts being a spec sheet you can act on.',
                  ],
                  leadingDiagram: 'g3-polar-plot-anatomy',
                  trailingParagraphs: const <String>[
                    'A radiation pattern comes as two polar plots: one for the '
                        'azimuth plane, one for the elevation plane. Always check '
                        'which one you are looking at. The same antenna looks like '
                        'two different objects in the two views. A simple dipole '
                        'is a near-perfect circle in azimuth and a pinched peanut, '
                        'a figure-eight, in elevation. Same antenna. Two slices.',
                    'Now read the chart, feature by feature.',
                  ],
                  bullets: const <_Bullet>[
                    _Bullet(
                      lead: 'The rings are a dB scale, not distance.',
                      rest: ' The outer edge is the antenna’s own peak. Each '
                          'ring inward is a step down in relative power. The '
                          'pattern line shows how strongly the antenna radiates '
                          'in each direction compared to its own strongest '
                          'direction. It is not a map of how far the signal '
                          'travels in feet.',
                    ),
                    _Bullet(
                      lead: 'Main lobe.',
                      rest: ' The direction of strongest radiation. The biggest '
                          'bulge in the pattern.',
                    ),
                    _Bullet(
                      lead: 'Beamwidth, read at the -3 dB points.',
                      rest: ' Find where the main lobe crosses the -3 dB ring, '
                          'the half-power ring, on each side. The angle between '
                          'those two crossings is the beamwidth. That is the '
                          'honest measure of “how wide does this cover,” '
                          'and you read it separately in azimuth and in elevation.',
                    ),
                    _Bullet(
                      lead: 'Side lobes.',
                      rest: ' The smaller bulges off the sides of the main lobe. '
                          'They radiate real energy in directions you may not have '
                          'wanted to cover. On the thesis, side lobes are coverage '
                          'you did not ask for.',
                    ),
                    _Bullet(
                      lead: 'Nulls.',
                      rest: ' The pinched-in directions between lobes, where the '
                          'antenna radiates almost nothing. Many ceiling antennas '
                          'have a null pointing straight down, which is why the '
                          'client right under the AP can read weaker than one a '
                          'few feet to the side.',
                    ),
                    _Bullet(
                      lead: 'Front-to-back ratio.',
                      rest: ' For a directional antenna, the difference in dB '
                          'between the main lobe in front and the lobe pointing '
                          'backward. A high front-to-back ratio means the antenna '
                          'keeps energy out of the area behind it. This is the '
                          'spec you read when your goal is to NOT cover something.',
                    ),
                  ],
                  closer:
                      'The thesis, lived through this section: a pattern chart is '
                      'a picture of what an antenna covers and what it leaves '
                      'alone. Beamwidth tells you the width you cover. '
                      'Front-to-back ratio and the nulls tell you where you '
                      'successfully avoid covering. Reading the chart is reading '
                      'the answer to one question: does this shape match my room?',
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Section 4 — What antenna to use where ─────────────────
                _Section(
                  number: '4',
                  title: 'What antenna to use where',
                  isDesktop: isDesktop,
                  paragraphs: const <String>[
                    'Antennas run along a line. At one end, “cover '
                        'everything around me, evenly.” At the other end, '
                        '“fire a tight beam at one distant target.” '
                        'Every antenna type is a point on that line. Match the '
                        'point on the line to what you are trying to cover.',
                  ],
                  leadingDiagram: 'g4-pattern-comparison',
                  customAfterLeading: const _TypeTable(),
                  afterMidParagraphs: const <String>[
                    'Those beamwidth numbers are ranges, not single specs. Real '
                        'products land at different points inside each band '
                        'depending on their design. Read the data sheet for the '
                        'antenna in your hand.',
                  ],
                  midDiagram: 'g5-coverage-floorplan',
                  afterCustomParagraphs: const <String>[
                    'Walk the thesis through the table:',
                  ],
                  bullets: const <_Bullet>[
                    _Bullet(
                      lead: 'Open-plan even coverage.',
                      rest: ' Omni. You want everything around you, equally '
                          'weighted. The shape matches the intent.',
                    ),
                    _Bullet(
                      lead: 'Aiming coverage into one area, and keeping it out of '
                          'another.',
                      rest: ' Patch or panel. Mount it on a wall and fire inward. '
                          'Its front-to-back ratio shields the room next door and '
                          'the parking lot beyond it. This is the purest '
                          '“cover what you want, not what you don’t” '
                          'case there is.',
                    ),
                    _Bullet(
                      lead: 'High-ceiling space.',
                      rest: ' Directional, downtilted. Put the energy on the '
                          'floor where the clients are, not on the far wall 40 '
                          'feet up.',
                    ),
                  ],
                  trailingParagraphs: const <String>[
                    'Then the far end of the line: point-to-point. Here you do '
                        'not want coverage at all. You want a beam aimed at '
                        'exactly one other antenna across a gap. A Yagi handles '
                        'the shorter links; a dish handles the long ones. The '
                        'narrow beamwidth is not a side effect, it is the entire '
                        'reason you chose the antenna.',
                  ],
                  aside: const _Aside(
                    title: 'Point-to-point needs real line-of-sight, not just a '
                        'visible path.',
                    body: 'The radio beam needs clearance around the straight '
                        'line between the two antennas, the Fresnel zone, not only '
                        'an unobstructed view. A link that looks clear to the eye '
                        'can still be choked by a rooftop or a tree line sitting '
                        'inside that zone.',
                  ),
                  antiPattern: const _AntiPattern(
                    lead: 'The anti-pattern, said out loud:',
                    body: ' choosing an antenna by its gain number alone. More '
                        'dBi is not more coverage. It is narrower, differently '
                        'shaped coverage. A high-gain omni in a multi-story '
                        'building is the classic self-inflicted wound. It flattens '
                        'the donut, sprays energy into the floors you did not want '
                        'to cover, and thins out the floor you did. Gain is a '
                        'shaping tool, never a volume knob.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Section 5 — The verdict, restated ─────────────────────
                const _Section(
                  number: '5',
                  title: 'The verdict, restated',
                  paragraphs: <String>[
                    'Every antenna in this resource does the same job. It decides '
                        'where your radio’s energy goes.',
                    'The omni covers everything around it. The patch fires into '
                        'one area and shields the rest. The dish ignores the '
                        'entire world except a single target across a gap. None of '
                        'them is “better” than the others. The right one '
                        'is the one whose pattern matches the space you are trying '
                        'to cover.',
                    'Pick the antenna that covers what you want covered, and stops '
                        'where you want it to stop. Read the pattern chart before '
                        'you mount. Mount the antenna the way its pattern was '
                        'designed to hang. Point the energy at the clients, and '
                        'match the polarization to the devices you serve. Do that, '
                        'and you have shaped your coverage on purpose instead of '
                        'by accident.',
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Deployment quick-map ──────────────────────────────────
                const _QuickMap(),

                ToolHelpFooter(toolId: kAntennaFundamentalsToolId),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data shapes for the verbatim copy — small immutable records that let the
// section widget render paragraphs, bullets, subsections, asides, and diagrams
// in the right order without hand-rolling each section.
// ─────────────────────────────────────────────────────────────────────────────

/// A bullet with an optional bold lead-in run and the rest of the sentence.
@immutable
class _Bullet {
  const _Bullet({this.lead, required this.rest});

  /// Bold lead-in run (e.g. "Main lobe."). Null for a plain bullet.
  final String? lead;

  /// The remainder of the bullet text.
  final String rest;
}

/// A flagged editorial aside (the italic "Read the spec, don't derive it." /
/// Fresnel notes). Carries the GL-005 honesty labels verbatim.
@immutable
class _Aside {
  const _Aside({required this.title, required this.body});

  final String title;
  final String body;
}

/// The "anti-pattern, said out loud" callout — a bold lead-in + body, rendered
/// in the §8.13 warning register (text-bearing, never color-only).
@immutable
class _AntiPattern {
  const _AntiPattern({required this.lead, required this.body});

  final String lead;
  final String body;
}

/// A within-section subsection (Section 2's Polarization / wall-clock / tilt).
@immutable
class _Subsection {
  const _Subsection({
    required this.title,
    this.paragraphs = const <String>[],
    this.bullets = const <_Bullet>[],
    this.trailingParagraphs = const <String>[],
    this.leadingDiagram,
    this.midDiagram,
    this.afterMidParagraphs = const <String>[],
    this.warning,
    this.isDesktop = false,
  });

  final String title;
  final List<String> paragraphs;
  final List<_Bullet> bullets;
  final List<String> trailingParagraphs;
  final String? leadingDiagram;
  final String? midDiagram;
  final List<String> afterMidParagraphs;

  /// A §8.13 warning band (the "Never mount an AP on a wall like a clock.").
  final String? warning;
  final bool isDesktop;
}

// ─────────────────────────────────────────────────────────────────────────────
// The through-line thesis pull-quote (stated at the top, §0).
// ─────────────────────────────────────────────────────────────────────────────

class _Thesis extends StatelessWidget {
  const _Thesis();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      // The thesis is the screen's framing claim — announce it as one node.
      label:
          'Use the antenna that covers what you want covered, without covering '
          'areas you don’t want.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Lime accent rail — a FILLED area, valid in both themes
              // (§8.20.2). Reinforced by the text, never color-only.
              Container(width: colors.isLight ? 4 : 3, color: colors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'Use the antenna that covers what you want covered, without '
                    'covering areas you don’t want.',
                    style: (text.titleMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// A teaching section: numbered header, prose, bullets, optional diagrams at
// their markers, optional subsections, aside, and closer line.
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    this.introParagraphs = const <String>[],
    this.paragraphs = const <String>[],
    this.bullets = const <_Bullet>[],
    this.trailingParagraphs = const <String>[],
    this.subsections = const <_Subsection>[],
    this.leadingDiagram,
    this.midDiagram,
    this.afterMidParagraphs = const <String>[],
    this.customAfterLeading,
    this.afterCustomParagraphs = const <String>[],
    this.aside,
    this.antiPattern,
    this.closer,
    this.isDesktop = false,
  });

  final String number;
  final String title;

  /// Paragraphs rendered BEFORE the leading diagram (the §3 "This is the
  /// literacy section…" framing line that precedes the [G3] marker).
  final List<String> introParagraphs;

  /// Lead paragraphs, rendered right after the header (and after a leading
  /// diagram if one is set).
  final List<String> paragraphs;
  final List<_Bullet> bullets;

  /// Paragraphs after the bullets.
  final List<String> trailingParagraphs;
  final List<_Subsection> subsections;

  /// Diagram slug rendered at the TOP of the section (after the header), per the
  /// teaching-copy placement markers.
  final String? leadingDiagram;

  /// Diagram slug rendered partway through (after [trailingParagraphs] / the
  /// custom block), per the placement markers.
  final String? midDiagram;

  /// Paragraphs rendered after [midDiagram].
  final List<String> afterMidParagraphs;

  /// A bespoke widget (e.g. the directional-type table) rendered right after the
  /// leading diagram.
  final Widget? customAfterLeading;

  /// Paragraphs rendered after the custom block + mid diagram (e.g. the "Walk
  /// the thesis through the table:" lead-in before the bullets in §4).
  final List<String> afterCustomParagraphs;

  final _Aside? aside;
  final _AntiPattern? antiPattern;

  /// The "The thesis, lived through this section:" closer line.
  final String? closer;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    // The section renders its slots in a single fixed sequence that matches the
    // teaching copy's marker order. A section populates only the slots it uses;
    // every slot is optional, so the same widget serves all six sections:
    //   header → leadingDiagram → paragraphs → custom (the §4 type table) →
    //   afterMid (the §4 muted range note) → midDiagram → afterCustom →
    //   bullets → trailingParagraphs → subsections → aside → antiPattern →
    //   closer.
    // §1 uses paragraphs/bullets/midDiagram/afterMid; §4 uses custom/afterMid/
    // midDiagram/afterCustom/bullets/trailing — the order below honors both.
    final List<Widget> children = <Widget>[
      _SectionHeader(number: number, title: title),
      const SizedBox(height: AppSpacing.sm),
    ];

    void diagram(String slug) {
      children
        ..add(_AntennaDiagramBand(slug: slug, isDesktop: isDesktop))
        ..add(const SizedBox(height: AppSpacing.md));
    }

    void prose(Iterable<String> ps, {bool muted = false}) {
      for (final String p in ps) {
        children
          ..add(_Para(text: p, muted: muted))
          ..add(const SizedBox(height: AppSpacing.sm));
      }
    }

    prose(introParagraphs);
    if (leadingDiagram != null) diagram(leadingDiagram!);
    prose(paragraphs);

    if (customAfterLeading != null) {
      children
        ..add(customAfterLeading!)
        ..add(const SizedBox(height: AppSpacing.sm));
      // §4: the "these are ranges, not single specs" honesty note (muted), then
      // the floor-plan diagram, then the "walk the thesis" lead-in.
      prose(afterMidParagraphs, muted: true);
      if (midDiagram != null) diagram(midDiagram!);
      prose(afterCustomParagraphs);
    }

    if (bullets.isNotEmpty) {
      children
        ..add(_BulletList(bullets: bullets))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (customAfterLeading == null) {
      // §1 / §3: trailing prose, then (for §1) the mid diagram + its afterMid.
      prose(trailingParagraphs);
      if (midDiagram != null) {
        diagram(midDiagram!);
        prose(afterMidParagraphs);
      }
    } else {
      // §4: the point-to-point trailing paragraph follows the bullets.
      prose(trailingParagraphs);
    }

    for (final _Subsection s in subsections) {
      children
        ..add(const SizedBox(height: AppSpacing.xs))
        ..add(_SubsectionView(subsection: s))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (aside != null) {
      children
        ..add(_AsideView(aside: aside!))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (antiPattern != null) {
      children
        ..add(_AntiPatternView(antiPattern: antiPattern!))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (closer != null) {
      children.add(_Closer(text: closer!));
    } else if (children.isNotEmpty && children.last is SizedBox) {
      // Trim the trailing spacer the last prose/widget added, so the section's
      // own bottom gap (added by the caller) is the only one.
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// A numbered section header: the lime section number badge + title, marked as a
/// landmark header for screen readers.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: 'Section $number. $title',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
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
              number,
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: (text.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A body paragraph (§8.2 body register). [muted] renders the GL-005 "these are
/// ranges" note in the secondary register; default is primary body text.
class _Para extends StatelessWidget {
  const _Para({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: muted ? colors.textSecondary : colors.textPrimary,
        height: 1.5,
        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

/// A bulleted list with an optional bold lead-in run per item (the §3 feature
/// list, the §4 walk-the-thesis list, the §2 wall-clock list).
class _BulletList extends StatelessWidget {
  const _BulletList({required this.bullets});

  final List<_Bullet> bullets;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle base = (t.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < bullets.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '•  ',
                  style: base.copyWith(color: colors.textAccent),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (bullets[i].lead != null)
                        TextSpan(
                          text: bullets[i].lead,
                          style: base.copyWith(fontWeight: FontWeight.w700),
                        ),
                      TextSpan(text: bullets[i].rest),
                    ],
                  ),
                  style: base,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A within-section subsection: a quiet uppercase title + its prose / bullets /
/// diagram / optional warning band.
class _SubsectionView extends StatelessWidget {
  const _SubsectionView({required this.subsection});

  final _Subsection subsection;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final _Subsection s = subsection;

    final List<Widget> children = <Widget>[
      Semantics(
        header: true,
        child: Text(
          s.title,
          style: (t.titleSmall ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
    ];

    if (s.leadingDiagram != null) {
      children
        ..add(_AntennaDiagramBand(slug: s.leadingDiagram!, isDesktop: s.isDesktop))
        ..add(const SizedBox(height: AppSpacing.md));
    }

    for (final String p in s.paragraphs) {
      children
        ..add(_Para(text: p))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (s.bullets.isNotEmpty) {
      children
        ..add(_BulletList(bullets: s.bullets))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    for (final String p in s.trailingParagraphs) {
      children
        ..add(_Para(text: p))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (s.warning != null) {
      children
        ..add(_WarningBand(text: s.warning!))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (s.midDiagram != null) {
      children
        ..add(_AntennaDiagramBand(slug: s.midDiagram!, isDesktop: s.isDesktop))
        ..add(const SizedBox(height: AppSpacing.md));
    }

    for (final String p in s.afterMidParagraphs) {
      children
        ..add(_Para(text: p))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Drop the trailing spacer the last child added.
    if (children.isNotEmpty && children.last is SizedBox) {
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// A §8.13 warning band — the mounting "never do this" rule. Filled warning
/// surface accent + a warning glyph + the rule text, so the cue is never
/// color-only (GL-003 §8.13).
class _WarningBand extends StatelessWidget {
  const _WarningBand({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final double accentWidth = colors.isLight ? 4 : 3;
    return Semantics(
      label: 'Warning. $text',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: accentWidth, color: colors.statusWarning),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: colors.statusWarning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          text,
                          style: (t.bodyMedium ?? const TextStyle()).copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
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

/// A flagged editorial aside (italic title + body), rendered in a recessed
/// surface-2 card so it reads as a sidebar note distinct from the body flow.
/// Carries the GL-005 honesty labels verbatim.
class _AsideView extends StatelessWidget {
  const _AsideView({required this.aside});

  final _Aside aside;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: aside.title,
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
            TextSpan(
              text: ' ${aside.body}',
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "anti-pattern, said out loud" callout — bold lead-in + body in the §8.13
/// warning register (left rail + warning-toned lead-in), text-bearing so the
/// meaning is never color-only.
class _AntiPatternView extends StatelessWidget {
  const _AntiPatternView({required this.antiPattern});

  final _AntiPattern antiPattern;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final double accentWidth = colors.isLight ? 4 : 3;
    final TextStyle base = (t.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      height: 1.5,
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: accentWidth, color: colors.statusWarning),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: antiPattern.lead,
                        style: base.copyWith(
                          color: colors.statusWarning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: antiPattern.body),
                    ],
                  ),
                  style: base,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "The thesis, lived through this section:" closer line — a quiet
/// secondary-register italic that echoes the through-line at each section close.
class _Closer extends StatelessWidget {
  const _Closer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textSecondary,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The directional-type comparison table (Section 4).
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _TypeRow {
  const _TypeRow({
    required this.type,
    required this.beamwidth,
    required this.covers,
    required this.leavesOut,
    required this.reachWhen,
  });

  final String type;
  final String beamwidth;
  final String covers;
  final String leavesOut;
  final String reachWhen;
}

/// Section 4's antenna-type table, rendered as a stack of cards (one per type)
/// rather than a wide grid — a 320px phone cannot show six columns legibly, so
/// each type is a labeled card with its fields, matching the reference-card
/// idiom. Verbatim from the teaching copy.
class _TypeTable extends StatelessWidget {
  const _TypeTable();

  static const List<_TypeRow> _rows = <_TypeRow>[
    _TypeRow(
      type: 'Omni',
      beamwidth: '360° azimuth, narrow elevation',
      covers: 'everything around it, evenly',
      leavesOut: 'above and below, the donut hole',
      reachWhen: 'open-plan even coverage, ceiling-mounting an office or '
          'warehouse floor',
    ),
    _TypeRow(
      type: 'Patch / panel',
      beamwidth: '~30 to 120°',
      covers: 'a broad area in front',
      leavesOut: 'everything behind it',
      reachWhen: 'firing into one room, covering one side of a space, keeping '
          'energy out of the next room',
    ),
    _TypeRow(
      type: 'Sector',
      beamwidth: '~60 to 120°',
      covers: 'a defined slice of a large area',
      leavesOut: 'the other sectors',
      reachWhen: 'large outdoor areas, stadium bowls, campus quads, splitting a '
          'big space into controlled wedges',
    ),
    _TypeRow(
      type: 'Yagi',
      beamwidth: '~15 to 40°',
      covers: 'a focused corridor toward a target',
      leavesOut: 'nearly everything off-axis',
      reachWhen: 'aiming down a long narrow space, short to medium '
          'building-to-building links',
    ),
    _TypeRow(
      type: 'Dish / parabolic',
      beamwidth: '~3 to 25°',
      covers: 'one distant target',
      leavesOut: 'everything else',
      reachWhen: 'long point-to-point links, building-to-building backhaul over '
          'open line of sight',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < _rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _TypeCard(row: _rows[i]),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.row});

  final _TypeRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: '${row.type}. Typical beamwidth ${row.beamwidth}. '
          'Covers ${row.covers}. Leaves out ${row.leavesOut}. '
          'Reach for it when ${row.reachWhen}.',
      excludeSemantics: true,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.type,
                    style: (t.titleSmall ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _BeamwidthChip(label: row.beamwidth),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _TypeField(label: 'Covers', value: row.covers),
            _TypeField(label: 'Leaves out', value: row.leavesOut),
            _TypeField(label: 'Reach for it when', value: row.reachWhen),
          ],
        ),
      ),
    );
  }
}

/// The typical-azimuth-beamwidth range chip — a neutral outlined pill (the value
/// is a RANGE, GL-005-labeled in the note beneath the table).
class _BeamwidthChip extends StatelessWidget {
  const _BeamwidthChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: (t.labelSmall ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
          fontFamily: 'DM Mono',
        ),
      ),
    );
  }
}

/// A labeled field row inside a type card — fixed-width caption + wrapping value.
class _TypeField extends StatelessWidget {
  const _TypeField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: (t.labelMedium ?? const TextStyle()).copyWith(
                color: colors.textTertiary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The deployment quick-map (closing lookup list).
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _QuickMapRow {
  const _QuickMapRow({required this.scenario, required this.recommendation});

  final String scenario;
  final String recommendation;
}

class _QuickMap extends StatelessWidget {
  const _QuickMap();

  static const List<_QuickMapRow> _rows = <_QuickMapRow>[
    _QuickMapRow(
      scenario: 'Open office, normal ceiling:',
      recommendation: ' ceiling omni, modest gain. Even floor coverage.',
    ),
    _QuickMapRow(
      scenario: 'Warehouse, high flat ceiling, long aisles:',
      recommendation: ' higher-gain omni or a downtilted directional. Reach the '
          'floor down the aisles.',
    ),
    _QuickMapRow(
      scenario: 'Single room you want covered without bleeding into the next '
          'room:',
      recommendation: ' wall-mounted patch firing inward. The front-to-back '
          'ratio does the shielding.',
    ),
    _QuickMapRow(
      scenario: 'Outdoor courtyard or stadium bowl:',
      recommendation: ' sectors, each covering one controlled wedge.',
    ),
    _QuickMapRow(
      scenario: 'Long hallway or narrow corridor:',
      recommendation: ' a patch or directional aimed down the axis. Never a '
          'hallway omni that wastes half its pattern into the side walls.',
    ),
    _QuickMapRow(
      scenario: 'Building-to-building link:',
      recommendation: ' Yagi for the shorter hop, dish for the longer one, both '
          'aimed, both with real line-of-sight clearance through the Fresnel '
          'zone.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle base = (t.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      height: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader(number: '→', title: 'Deployment quick-map'),
        const SizedBox(height: AppSpacing.sm),
        _Para(
          text: 'A fast lookup for the common cases. Each one is the thesis '
              'applied to a real space.',
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < _rows.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '•  ',
                        style: base.copyWith(color: colors.textAccent),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: _rows[i].scenario,
                              style: base.copyWith(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: _rows[i].recommendation),
                          ],
                        ),
                        style: base,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The diagram band — renders a Charta teaching diagram at its intrinsic aspect
// ratio inside a card, recolored for light via the §8.20.7 swap.
// ─────────────────────────────────────────────────────────────────────────────

/// Renders one Antenna Fundamentals diagram (by graphics-plan slug) at its
/// intrinsic aspect ratio inside a card-styled band. Unlike the §8.6.2 concept
/// header band (a fixed 140/160dp band for a small glyph), these are full
/// teaching diagrams, so the band sizes to the diagram's own aspect ratio and
/// scales to width — never cropped, never distorted.
///
/// LIGHT/DARK (GL-003 §8.20.7): the diagrams are authored DARK-BAKED on the
/// allow-list hexes (#E5E5E5 scaffold / #9C9C9C muted / #A2CC3A lime / #F26E6E
/// danger / the lime wash). DARK renders the asset byte-for-byte; LIGHT loads the
/// source and applies the SAME single-source-of-truth swap the concept graphics
/// use (ConceptGraphicBand.applyLightSwap) before rendering via SvgPicture.string,
/// so no raw lime/scaffold stroke ever hits a light surface. The swapped string
/// is cached per slug so the replace runs once.
///
/// Graceful degradation: if the slug's SVG is not in the bundle (or fails to
/// parse) the band renders nothing — no broken-image box — so the prose still
/// reads end-to-end.
///
/// Accessibility (§8.6.2): decorative — every fact a diagram depicts is in the
/// prose, so it is excluded from the semantics tree (ExcludeSemantics +
/// excludeFromSemantics) and screen readers land on the section copy.
class _AntennaDiagramBand extends StatelessWidget {
  const _AntennaDiagramBand({required this.slug, this.isDesktop = false});

  final String slug;
  final bool isDesktop;

  // Intrinsic aspect ratios (width / height) of the seven diagrams, from each
  // SVG's viewBox. Used so the band reserves the diagram's true shape and the
  // art is never cropped or stretched. Kept here (not parsed at runtime) so the
  // band sizes deterministically before the async source load completes — the
  // light path loads the source string asynchronously, and an AspectRatio
  // computed from a not-yet-loaded SVG would jump the layout. A slug not in the
  // map falls back to a 1.6:1 default (still uncropped via BoxFit.contain).
  static const Map<String, double> _aspect = <String, double>{
    'g1-azimuth-vs-elevation': 760 / 420,
    'g2-omni-donut': 760 / 460,
    'g3-polar-plot-anatomy': 780 / 520,
    'g4-pattern-comparison': 880 / 360,
    'g5-coverage-floorplan': 880 / 560,
    'g6-downtilt': 820 / 440,
    'g7-polarization': 820 / 520,
  };

  // Per-slug cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per diagram, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[slug] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(AntennaFundamentalsDiagrams.path(slug));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[slug] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    if (!AntennaFundamentalsDiagrams.has(slug)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double aspect = _aspect[slug] ?? 1.6;

    final Widget svg = colors.isLight
        ? _LightDiagramSvg(future: _loadSwappedSvg())
        : SvgPicture.asset(
            AntennaFundamentalsDiagrams.path(slug),
            fit: BoxFit.contain,
            width: double.infinity,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: AspectRatio(
          aspectRatio: aspect,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode diagram render: awaits the §8.20.7-swapped SVG source, then draws
/// it with `SvgPicture.string`. Collapses to nothing while loading or on any
/// parse failure — same graceful-degradation contract as the dark asset path, so
/// no broken-image box or layout jump ever appears (the AspectRatio parent has
/// already reserved the space). Mirrors `_LightConceptSvg` in
/// concept_graphic_band.dart.
class _LightDiagramSvg extends StatelessWidget {
  const _LightDiagramSvg({required this.future});

  final Future<String> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
          return const SizedBox.shrink();
        }
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: double.infinity,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }
}
