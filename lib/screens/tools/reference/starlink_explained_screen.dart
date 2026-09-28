// Starlink, Explained: a Wi-Fi Classroom Guided Lesson. A read-along teaching
// screen built on the same pattern as Find My, Explained
// (find_my_explained_screen.dart): numbered landmark sections, verbatim copy,
// and dark-baked line figures recolored for light at runtime.
//
// CONTENT IS REVIEWED AND RENDERED VERBATIM. The literal strings below are the
// text of the print guide
// myPKA/Deliverables/2026-09-27-starlink-guide/starlink-guide.html (reviewed
// 2026-09-27; every review finding and its verdict is in VERDICTS.md beside
// it). Plan names, Roam rules and other dated facts keep their dates. Only the
// STRUCTURE is adapted for a scrolling screen:
//  - the print-only parts are dropped: the cover page layout, the table of
//    contents ("What's inside"), page footers, and the section eyebrows;
//  - every "page N" cross-reference now names the section instead ("the
//    section Trees, snow and rain"), as Find My's did;
//  - the nine figures and the cover art are re-drawn dark-baked under
//    assets/tool-diagrams/starlink/ (tool/starlink_diagrams.py) with every
//    label string unchanged;
//  - tables become stacks of cards so a phone can read them, and the Appendix
//    B checklist's printed boxes become real checkboxes (not persisted).
// Inline markup in the copy: **bold**, __italic__, and `menu path` (the print
// guide's `.path` spans, rendered in the app's mono style).
//
// States (SOP-007 §5): a static reference screen with no inputs, network or
// async data, so the always-rendered state is success. Each figure degrades
// gracefully: a slug missing from the bundle, or an SVG still loading in light
// mode, renders no figure at all (never a broken-image box) while its caption
// still reads. The interactive elements are the figure zoom buttons, the
// checklist checkboxes (checked / unchecked, theme focus ring) and the
// About this tool footer.
//
// THEME: every color comes from `context.colors`; no raw hex or AppColors.* in
// this file. The figures are dark-baked on the §8.20.7 allow-list and swapped
// for light by ConceptGraphicBand.applyLightSwap, the single source of truth.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark.
// Several figures carry facts the prose does not repeat (Figure 2's heights
// for Iridium, Amazon Leo and OneWeb, Figure 6's sizes and weights), so they
// are NOT decorative: each figure's caption node announces the figure's own
// labels first, then the caption. The SVG itself is excluded at the leaf
// (GL-003 §8.6.2.2) so the zoom button stays reachable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/starlink_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;
import '../zoomable_graphic.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kStarlinkExplainedToolId = 'starlink-explained';

class StarlinkExplainedScreen extends StatelessWidget {
  const StarlinkExplainedScreen({super.key});

  /// Test-only: drops the memoized light-mode figure sources. Each widget test
  /// runs in its own fake-async zone, and a Future created in an earlier
  /// test's zone never delivers to a later one, so tests that render light
  /// mode more than once clear this first. The running app has one zone and
  /// never needs it.
  @visibleForTesting
  static void debugClearFigureCache() => _FigureBand._light.clear();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starlink, Explained'),
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
                const _Hero(),
                const SizedBox(height: AppSpacing.lg),
                ..._sections,
                ToolHelpFooter(toolId: kStarlinkExplainedToolId),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The lesson body, section by section, in the print guide's order. Each
/// section is one list child so the ListView builds it lazily.
const List<Widget> _sections = <Widget>[
  // ── 1. The short answer ──────────────────────────────────────────────────
  _Section(
    number: '1',
    title: 'The short answer',
    children: <Widget>[
      _P(
        'Starlink is internet service from satellites that fly low, with the '
        'main group about 480 km (300 miles) up. A flat dish on your roof or '
        'RV talks to whichever satellite is overhead. That satellite passes '
        'your data down to a Starlink ground station, called a gateway, and '
        'from there it travels over ordinary fiber to the rest of the '
        'internet.',
      ),
      _Cards(<_CardData>[
        _CardData(
          "Low, so it's quick",
          'The old kind of satellite internet uses satellites 75 times farther '
              "away. Starlink's are close enough that a video call feels "
              'normal.',
        ),
        _CardData(
          'Shared, so it varies',
          'Everyone nearby shares the same satellite capacity. Busy evenings '
              'are slower than quiet mornings, and your plan decides who goes '
              'first.',
        ),
        _CardData(
          'Two links, not one',
          "Dish to satellite is one link. Starlink's router to your phone is a "
              'second one, your Wi-Fi. A slow back bedroom is often the second '
              'one.',
        ),
      ]),
      _Callout(
        title: 'The one idea that explains most of this guide',
        body:
            'Your speed depends on three things in a row: the sky the dish can '
            'see, how many neighbors share the satellites above you, and the '
            "Wi-Fi between Starlink's router and your device. When something "
            'feels slow, check them in reverse order, starting with the Wi-Fi.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            '**Low Earth orbit** means a few hundred kilometers up, close by '
            'space standards. **Geostationary** satellites sit much higher, '
            'over the equator, and seem to hang still in the sky; satellite TV '
            'uses them. **Latency** is the delay for a message to get there '
            'and back, counted in milliseconds (ms), thousandths of a second. '
            '**A gateway** is a Starlink ground station that connects the '
            'satellites to the internet.',
      ),
    ],
  ),

  // ── 2. How high the satellites fly ───────────────────────────────────────
  _Section(
    number: '2',
    title: 'How high the satellites fly',
    children: <Widget>[
      _P(
        "Starlink's main shell of satellites is about 480 km (300 miles) up. "
        'During 2026 SpaceX has been lowering about 4,400 satellites from '
        'around 550 km to that height, for space-safety reasons. The FCC, the '
        'US regulator, has approved shells from 340 km to 535 km. There were '
        'more than 9,000 Starlink satellites in orbit in early 2026, and the '
        'number changes every week.',
      ),
      _Figure(
        slug: 'f1-orbits-to-scale',
        alt:
            'Earth. Low Earth orbit: Space Station, Hubble, Starlink and '
            'others, all inside this thin line. GPS: 20,200 km. Geostationary: '
            '35,786 km, satellite TV and older satellite internet.',
        caption:
            '**Figure 1. Earth and its satellites, to scale.** Earth and every '
            'orbit are drawn at the same scale. Everything in low Earth orbit '
            'is a hairline hugging the planet; GPS and geostationary '
            'satellites sit far out.',
      ),
      _Figure(
        slug: 'f2-first-1300-km',
        alt:
            'A line from 0 km to 1,300 km. Space Station, 400 to 420 km. '
            'Starlink: 340 to 535 km, main shell 480 km. Hubble, 483 km (NASA, '
            'June 2026). Amazon Leo, 590 to 630 km. Iridium, 780 km. OneWeb, '
            '1,200 km.',
        caption:
            '**Figure 2. The first 1,300 km, stretched out.** The thin line in '
            'Figure 1, opened up so the low satellites can be labeled. The '
            'green band is every height the FCC has approved for Starlink; the '
            'dark tick is the main shell.',
      ),
      _Callout(
        title: 'Two surprises',
        body:
            'Starlink is approved to fly some satellites __lower__ than the '
            'International Space Station: the FCC approved shells at 340 to '
            '365 km, and the Station operates at 370 to 460 km. And Hubble now '
            "sits at about the same height as Starlink's main shell, around "
            '480 km. Hubble got there by slowly sinking; Starlink got there by '
            'being lowered on purpose.',
      ),
    ],
  ),

  // ── 3. The path your data takes ──────────────────────────────────────────
  _Section(
    number: '3',
    title: 'The path your data takes',
    children: <Widget>[
      _P(
        'At a house, your data usually makes one trip up and one trip down: '
        'from your dish to a satellite, then from that satellite to a Starlink '
        "gateway on the ground. From the gateway it rides fiber to the "
        "internet like everyone else's.",
      ),
      _Figure(
        slug: 'f3-data-path',
        alt:
            'Satellite, about 480 km up. 1. Up to the satellite, from your '
            'dish. 2. Down to a gateway, the Starlink gateway. 3. Fiber, to '
            'the PoP, the Point of Presence, and on to the Internet.',
        caption:
            '**Figure 3. The usual path from a house.** Dish to satellite to '
            'gateway, then fiber to a Point of Presence, where Starlink\'s '
            'network meets the rest of the internet. The same path runs in '
            'reverse for everything you download.',
      ),
      _Sub('What the pieces do'),
      _RowCards(<_Row>[
        _Row('Your dish', <_Pair>[
          _Pair(
            'What it does',
            'Sends and receives radio signals to whichever satellite is best '
                'placed overhead, switching satellites as they move across the '
                'sky.',
          ),
        ]),
        _Row('The satellite', <_Pair>[
          _Pair(
            'What it does',
            'Relays your signal between your dish and a gateway. Satellites '
                'keep moving across the sky, so the dish keeps handing off from '
                'one to the next.',
          ),
        ]),
        _Row('The gateway', <_Pair>[
          _Pair(
            'What it does',
            'A Starlink ground station with its own dishes. It connects the '
                'satellites to fiber.',
          ),
        ]),
        _Row('Point of Presence', <_Pair>[
          _Pair(
            'What it does',
            "The building where Starlink's network hands your traffic to the "
                'internet. SpaceX says traffic is encrypted all the way from '
                'your dish to here.',
          ),
        ]),
      ]),
      _Callout(
        tone: _Tone.warning,
        title: 'Far from any gateway',
        body:
            'At sea, over the poles, or in remote places, no gateway may be in '
            'view. There, satellites can pass your traffic to each other by '
            'laser before sending it down. SpaceX says this adds some delay, '
            'so at home it is the exception rather than the rule.',
      ),
    ],
  ),

  // ── 4. Where the milliseconds go ─────────────────────────────────────────
  _Section(
    number: '4',
    title: 'Where the milliseconds go',
    children: <Widget>[
      _P(
        'Latency is what makes a video call feel natural or awkward. '
        "Starlink's measured median in the US was about 25 ms at peak hours "
        'in June 2025. Geostationary satellite internet runs at about 600 to '
        '700 ms, more than half a second, because of how far the signal has '
        'to travel.',
      ),
      _Figure(
        slug: 'f4-latency',
        alt:
            'Starlink: about 25 ms typical, 25 to 60 ms range. Geostationary: '
            "about 600 to 700 ms. Zoomed in: inside Starlink's 25 ms (not to "
            'the scale above). Radio trip, under 10 ms. Ground network, '
            'scheduling, waiting in line. SpaceX: each leg between dish, '
            'satellite and gateway takes 1.8 to 3.6 ms at the speed of light, '
            'usually under 10 ms for the whole round trip. The rest is spent '
            'on the ground and in queues.',
        caption:
            '**Figure 4. Latency, Starlink against geostationary satellite.** '
            "Starlink's 25 ms bar is a sliver next to geostationary's. "
            "Starlink's published range is 25 to 60 ms on land, and 100 ms or "
            'more in some remote places.',
      ),
      _Sub('Why distance matters so much'),
      _P(
        'A radio signal travels at the speed of light, about 300,000 km every '
        'second. Straight up to a Starlink satellite at 480 km takes about 1.6 '
        'ms. Straight up to a geostationary satellite takes about 119 ms, and '
        'a round trip has to go up and down twice, so geostationary internet '
        'can never get below about half a second, whatever the provider does.',
      ),
      _P(
        'SpaceX says fewer than 1% of its US measurements exceed 55 ms, and '
        'its stated goal is a steady 20 ms median.',
      ),
      _Callout(
        title: 'What you notice',
        body:
            'At 25 ms, video calls and online games feel normal. At 600 ms, '
            'people talk over each other on calls, because each person hears '
            'the other more than half a second late.',
      ),
    ],
  ),

  // ── 5. A flat antenna that aims without moving ───────────────────────────
  _Section(
    number: '5',
    title: 'A flat antenna that aims without moving',
    children: <Widget>[
      _P(
        'Every current Starlink dish is a **phased array**: many small '
        'antennas under a flat cover. By timing each little antenna slightly '
        'differently, the dish points its beam at a satellite without moving '
        'at all. You set the angle once when you install it, with the app '
        'guiding you, and after that nothing inside moves.',
      ),
      _Figure(
        slug: 'f5-phased-array',
        alt:
            'The beam swings from satellite to satellite electronically. 110° '
            'field of view: the part of the sky the dish can use. Many small '
            'antennas, one flat panel. The panel stays still.',
        caption:
            '**Figure 5. A phased array.** The beam moves to follow satellites '
            'across the sky; the dish does not. Older rectangular Starlink '
            'dishes had a built-in motor, so "no moving parts" is true of '
            'current kits only.',
      ),
      _Sub('Which kit is which'),
      _Figure(
        slug: 'f6-dishes-to-scale',
        alt:
            'Standard 4 X and Standard 4: 59 x 38 cm, 2.9 kg. Starlink V5: 38 '
            'x 31 cm, 1.1 kg. Mini: 30 x 26 cm, 1.1 kg. A 20 cm scale bar.',
        caption:
            '**Figure 6. The current dishes, drawn to scale.** Sizes and '
            "weights from Starlink's spec sheets.",
      ),
      _RowCards(<_Row>[
        _Row('Standard 4 X', <_Pair>[
          _Pair('Average power', '75 to 100 W'),
          _Pair('Snow melt', 'up to 40 mm/h'),
          _Pair('Wi-Fi', 'Router 3'),
        ]),
        _Row('Standard 4', <_Pair>[
          _Pair('Average power', '75 to 100 W'),
          _Pair('Snow melt', 'up to 40 mm/h'),
          _Pair('Wi-Fi', 'Router Mini'),
        ]),
        _Row('Starlink V5', <_Pair>[
          _Pair('Average power', '35 to 50 W'),
          _Pair('Snow melt', 'up to 40 mm/h'),
          _Pair('Wi-Fi', 'Router Mini'),
        ]),
        _Row('Mini', <_Pair>[
          _Pair('Average power', '25 to 40 W'),
          _Pair('Snow melt', 'up to 25 mm/h'),
          _Pair('Wi-Fi', 'Built into the dish'),
        ]),
      ]),
    ],
  ),

  // ── 6. Why speeds change ─────────────────────────────────────────────────
  _Section(
    number: '6',
    title: 'Why speeds change',
    children: <Widget>[
      _P(
        'The satellites above your area have a fixed amount of capacity, and '
        'everyone nearby shares it. That is why the same dish can be fast at '
        '10 in the morning and slower at 8 at night.',
      ),
      _Figure(
        slug: 'f7-shared-capacity',
        alt:
            'Quiet morning: 2 homes online share the capacity, and each home '
            'gets a long bar. Busy evening: 6 homes online share the same '
            'capacity, and each home gets a bar a third as long.',
        caption:
            '**Figure 7. Neighbors share the capacity overhead.** An '
            'illustration, not measured speeds. Starlink marks areas where '
            'residential service is at capacity on its availability map, and '
            'in some busy areas new customers have paid a one-time congestion '
            'charge.',
      ),
      _Sub("Your plan affects who goes first when it's busy"),
      _RowCards(<_Row>[
        _Row('Residential Max', <_Pair>[
          _Pair(
            'What Starlink says about busy times',
            'Gets "top Residential network priority".',
          ),
        ]),
        _Row('Residential 200 Mbps', <_Pair>[
          _Pair(
            'What Starlink says about busy times',
            '"More likely to experience Service degradation and slower speeds '
                'during network congestion" than Residential Max.',
          ),
        ]),
        _Row('Roam', <_Pair>[
          _Pair(
            'What Starlink says about busy times',
            '"Typically deprioritized" compared with other plans, which '
                'Starlink says means slower speeds in congested areas and '
                'during peak hours.',
          ),
        ]),
      ]),
      _Sub('The six things that move your speed'),
      _Bullets(<String>[
        'How many neighbors share your area',
        'Time of day, with evenings busiest',
        "Your plan's priority",
        "Trees or buildings in the dish's view (the section Trees, snow and "
            'rain)',
        'Heavy rain or snow (the section Trees, snow and rain)',
        '**Your own Wi-Fi** (the section The Wi-Fi inside)',
      ]),
      _P(
        "Starlink's specification lists upload speeds of typically 10 to 30 "
        'Mbps. Download speed depends on the plan.',
        small: true,
      ),
    ],
  ),

  // ── 7. Plans for homes and RVs ───────────────────────────────────────────
  _Section(
    number: '7',
    title: 'Plans for homes and RVs',
    children: <Widget>[
      _P(
        'US plan names and rules as of 27 September 2026, from Starlink\'s own '
        'pages. Prices are left out on purpose: they change often and differ '
        'by country. Check starlink.com before you buy.',
      ),
      _RowCards(<_Row>[
        _Row('Residential Max', <_Pair>[
          _Pair(
            "What it's for",
            'A home at one address. Formerly called Residential. Maximum '
                'available speeds and top priority.',
          ),
        ]),
        _Row('Residential 200 Mbps', <_Pair>[
          _Pair(
            "What it's for",
            'A home at one address, only in some areas. Formerly Residential '
                'Lite. Starlink says downloads are capped at 200 Mbps, with '
                'unlimited data.',
          ),
        ]),
        _Row('Residential 100 Mbps', <_Pair>[
          _Pair("What it's for", 'A home at one address, only in some areas.'),
        ]),
        _Row('Roam 100GB and 300GB', <_Pair>[
          _Pair(
            "What it's for",
            'Travel within your home country, or its grouped region where '
                'Starlink offers one (the US and Canada count as one region; so '
                'does Europe), with a monthly allowance. Roam 100GB was '
                'formerly Roam 50GB in most markets. After the allowance, speed '
                'drops to a low rate that still handles email, calls and texts.',
          ),
        ]),
        _Row('Roam Unlimited', <_Pair>[
          _Pair(
            "What it's for",
            'Travel at home and abroad, up to 30 days at a time in another '
                "country. Complete Starlink's Travel Registration before you "
                'use it outside your home country.',
          ),
        ]),
      ]),
      _Sub('Using it while driving'),
      _Callout(
        tone: _Tone.danger,
        title: 'Residential plans are for parked use at the home address',
        body:
            'In-motion use is not permitted on any Residential plan. Since '
            'about March 2026, Standby Mode, the low-cost pause, no longer '
            'allows in-motion use either.',
      ),
      _P(
        'Roam, Local Priority and Global Priority plans allow use in motion up '
        'to 160 km/h (100 mph) in places where it is authorized. Land use in '
        'motion is not allowed in Indonesia, Malaysia, Japan, Jordan or '
        'Mexico. Starlink does not recommend its older motorized dishes for '
        'use in motion.',
      ),
      _Callout(
        title: 'The RV bottom line',
        body:
            'Parked at a campsite: Roam. Driving with the dish on: Roam, not '
            'Residential and not Standby, on a dish Starlink lists as supported '
            'for in-motion use, mounted securely. A Residential plan belongs to '
            'its home address. Residential Max customers are eligible for an '
            'optional Mini kit for travel, with a discounted Roam plan, as long '
            'as they keep Residential Max.',
      ),
    ],
  ),

  // ── 8. Trees, snow and rain ──────────────────────────────────────────────
  _Section(
    number: '8',
    title: 'Trees, snow and rain',
    children: <Widget>[
      _P(
        'The dish needs a clear view of the sky. Because the satellites keep '
        'moving, one tree branch in the wrong place does not cut you off all '
        'the time. It cuts you off for a moment, every time a satellite '
        'passes behind it.',
      ),
      _Figure(
        slug: 'f8-tree-drops',
        alt:
            'Clear sky the dish can use, above your dish. A tree hides part of '
            'it, and a satellite is blocked here. Service: a timeline with '
            'short drops.',
        caption:
            '**Figure 8. One tree, repeated short drops.** The gray wedge is '
            'sky the tree hides. Each satellite that crosses the wedge causes a '
            'brief interruption, then the next satellite takes over.',
      ),
      _Sub('Check before you mount'),
      _P(
        'The Starlink app has an obstruction check. You point your phone\'s '
        'camera at the sky from where the dish will go, and the app draws a '
        "map of what is clear and what is blocked. Starlink's simplest fix is "
        'the obvious one: move the dish to a spot the check shows as clear. '
        'That usually means higher, or away from trees. If that means a '
        'ladder, a roof or cutting branches, use an installer unless you can '
        'do it safely.',
      ),
      _Sub('Weather'),
      _RowCards(<_Row>[
        _Row('Heavy rain, snow or hail', <_Pair>[
          _Pair(
            'What Starlink says',
            'Can cause momentary dropouts and slower speeds. Rain and snow '
                'weaken the radio signal on its way through.',
          ),
        ]),
        _Row('Snow on the dish', <_Pair>[
          _Pair(
            'What Starlink says',
            'The dish heats itself using its own power. Rated to melt up to 40 '
                'mm of snow per hour (Standard and V5), 25 mm per hour (Mini). '
                'Snow falling faster than that piles up.',
          ),
        ]),
        _Row('A cover to keep snow off', <_Pair>[
          _Pair(
            'What Starlink says',
            "Don't. Starlink strongly recommends against extra protective "
                'covers, because they degrade performance.',
          ),
        ]),
      ]),
    ],
  ),

  // ── 9. The Wi-Fi inside ──────────────────────────────────────────────────
  _Section(
    number: '9',
    title: 'The Wi-Fi inside',
    children: <Widget>[
      _P(
        'An ordinary speed-test app on your phone measures two links at once: '
        "the satellite link and your Wi-Fi. (The Starlink app's default speed "
        'test is different: it measures from the router to the internet and '
        'leaves your Wi-Fi out.) When the back bedroom or the far end of the '
        'RV is slow, the satellite is often fine and the Wi-Fi is the '
        'problem.',
      ),
      _Figure(
        slug: 'f9-two-links',
        alt:
            'Link 1: the Starlink link, dish to satellite and back. Link 2: '
            'your Wi-Fi, from the Starlink router to a phone in the back room, '
            "router to phone, through walls, cabinets, or an RV's metal body.",
        caption:
            "**Figure 9. Two networks in one house.** Your phone's speed is the "
            'slower of the two links. A test next to the router, on a wired '
            "laptop, or the Starlink app's default test shows the Starlink link "
            'alone.',
      ),
      _Sub("Starlink's routers"),
      _RowCards(<_Row>[
        _Row('Router 3', <_Pair>[
          _Pair('Comes with', 'Standard 4 X'),
          _Pair('Wi-Fi', 'Wi-Fi 6, which Starlink calls tri band'),
          _Pair('Security', 'WPA2'),
          _Pair("Coverage (Starlink's figure)", 'up to 297 m²'),
        ]),
        _Row('Router Mini', <_Pair>[
          _Pair('Comes with', 'Standard 4, V5'),
          _Pair('Wi-Fi', 'Wi-Fi 6, dual band'),
          _Pair('Security', 'WPA2'),
          _Pair("Coverage (Starlink's figure)", 'up to 204 m²'),
        ]),
        // The print table spans the last two columns in this row.
        _Row('Mini dish', <_Pair>[
          _Pair('Comes with', 'Mini'),
          _Pair('Wi-Fi', '802.11a/b/g/n/ac (Wi-Fi 5), built in'),
          _Pair(
            "Security and coverage (Starlink's figure)",
            "per Starlink's Mini spec sheet",
          ),
        ]),
      ]),
      _P(
        'Neither router lists the 6 GHz band (Wi-Fi 6E or Wi-Fi 7) or WPA3 '
        "security. Both are listed as not compatible with other brands' mesh "
        'systems; Router 3 works with up to three Starlink mesh nodes. One '
        'thing Starlink gets right: SpaceX says its router manages its traffic '
        "queue so one big download does not swamp someone else's video call.",
        small: true,
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'Using your own router: bypass mode',
        body:
            "Bypass mode turns the Starlink router's Wi-Fi off completely and "
            'hands everything to a router you connect. It is the right choice '
            'if you want your own mesh system. Know this first: turning bypass '
            'mode off again takes a factory reset of the Starlink router. On '
            'Router 3, a violet light means bypass mode is on.',
      ),
      _P(
        "**Wi-Fi Calling on Starlink.** T-Mobile's Wi-Fi Calling page says "
        '"Satellite Internet and cell phone hotspot are not supported." That '
        "is T-Mobile's rule; check your own carrier's page.",
        small: true,
      ),
    ],
  ),

  // ── 10. Six things people get wrong ──────────────────────────────────────
  _Section(
    number: '10',
    title: 'Six things people get wrong',
    children: <Widget>[
      _P(
        // Print: "The right-hand column says what is true, and the page where
        // the guide explains why." On screen the fact sits under the myth,
        // and the pointer names a section, so the sentence follows the screen.
        'Each of these comes up again and again. The Fact part says what is '
        'true, and the section where the guide explains why.',
      ),
      _Myth(
        myth: 'Satellite internet is too slow for video calls.',
        fact:
            "That's true of geostationary satellites, 35,786 km up, at about "
            "600 to 700 ms. Starlink's are about 480 km up, at about 25 ms "
            'typical. See the section Where the milliseconds go.',
      ),
      _Myth(
        myth: 'The dish tracks the satellites by turning.',
        fact:
            'Current dishes steer their beam electronically and never move. '
            'Only the older rectangular dish had a motor. See the section A '
            'flat antenna that aims without moving.',
      ),
      _Myth(
        myth: 'My Residential plan works in the RV while I drive.',
        fact:
            'In-motion use is not permitted on any Residential plan, or on '
            'Standby Mode since about March 2026. Use Roam. See the section '
            'Plans for homes and RVs.',
      ),
      _Myth(
        myth:
            'Starlink is slow in the back bedroom, so the satellites must be '
            'overloaded.',
        fact:
            "Often it's the Wi-Fi: distance, walls, metal RV bodies, and a "
            'Wi-Fi 6 router with no 6 GHz. Test next to the router first. See '
            'the section The Wi-Fi inside.',
      ),
      _Myth(
        myth: "I'll put a cover on the dish for the snow.",
        fact:
            'Starlink says covers degrade performance. The dish melts snow by '
            'itself, up to its rated rate. See the section Trees, snow and '
            'rain.',
      ),
      _Myth(
        myth: "I can add my own mesh system and keep Starlink's Wi-Fi too.",
        fact:
            "Starlink's routers don't join other brands' mesh. Bypass mode "
            "hands Wi-Fi to your router and turns Starlink's off; undoing it "
            'takes a factory reset. See the section The Wi-Fi inside.',
      ),
    ],
  ),

  // ── Appendix A: step by step in the Starlink app ─────────────────────────
  _Section(
    number: 'A',
    spokenNumber: 'Appendix A',
    title: 'Step by step in the Starlink app',
    children: <Widget>[
      _P(
        "These paths come from Starlink's help pages. Starlink's own pages "
        'word some buttons differently, so your app may use slightly different '
        'labels. The steps are in the same order either way.',
        small: true,
      ),
      _Task(
        title: '1. Check for obstructions before you mount',
        why:
            "Finds trees and roof edges in the dish's view before you drill "
            'any holes.',
        steps: <String>[
          'Open the Starlink app and tap `Check for Obstructions`. Some '
              'versions show `Find an Install Location` on the home screen '
              'instead.',
          'Choose your Starlink kit when the app asks, so it scans the right '
              'field of view.',
          'Hold your phone exactly where the dish will go, at the height it '
              'will be mounted, and follow the on-screen sky scan.',
          'If the map shows blocked areas, move to a clearer spot and scan '
              'again.',
        ],
      ),
      _Task(
        title: '2. Split the 2.4 GHz and 5 GHz networks',
        why:
            'Helps older gadgets that only use 2.4 GHz, such as some smart '
            'plugs and cameras, join reliably.',
        steps: <String>[
          'Open the Starlink app and tap `Settings`.',
          'Tap your network name.',
          'Turn on `Split 2.4/5 GHz networks`, give each band its own name if '
              'asked, and tap Save. Let the router restart if the app asks.',
          'Join the older gadget to the 2.4 GHz network.',
        ],
      ),
      _Task(
        title: "3. See each device's Wi-Fi signal",
        why: 'Shows whether a slow device has a weak Wi-Fi signal.',
        steps: <String>[
          'Open the Starlink app and tap the `Network` tab.',
          'Find the slow device in the list and look at its signal.',
        ],
      ),
      _Task(
        title: '4. Use your own router (bypass mode)',
        why:
            'For a mesh system or router you already own. Read the warning in '
            'the section The Wi-Fi inside first.',
        steps: <String>[
          "Connect your router's internet (WAN) port to the Starlink router, "
              "or to the Mini's Ethernet adapter.",
          'In the Starlink app, open `Settings` and choose bypass mode.',
          "Confirm. Starlink's Wi-Fi turns off; only a factory reset turns it "
              'back on.',
        ],
      ),
    ],
  ),

  // ── Appendix B: before you blame Starlink ────────────────────────────────
  _Section(
    number: 'B',
    spokenNumber: 'Appendix B',
    title: 'Before you blame Starlink',
    children: <Widget>[
      _P(
        'Work down this list when something feels slow. It starts with the '
        'link you control, your Wi-Fi, and ends with the satellites.',
      ),
      _Checklist(),
      _Callout(
        title: 'For RVs especially',
        body:
            'The router usually sits inside a metal body, and metal blocks '
            'Wi-Fi far better than wood or drywall. A device at the other end '
            'of the RV, or outside at the picnic table, may be on a weak Wi-Fi '
            'signal while the dish on the roof is doing fine. Also check the '
            'dish cable where it passes through a window, door or slide-out: '
            "Starlink's troubleshooting starts with damage, kinks and loose "
            'connections, and recommends only official Starlink cables.',
      ),
      _Callout(
        title: 'Power in an RV',
        body:
            "Average draw, from Starlink's spec sheets: Mini 25 to 40 W, "
            'Starlink V5 35 to 50 W, Standard 75 to 100 W. Snow melt draws '
            'more, so winter use runs above these averages. The Mini runs on 12 '
            'to 48 V DC (rated 60 W). Powering it from USB-C needs a 100 W '
            "supply, 20 V at 5 A minimum, with Starlink's USB-C to barrel "
            'cable. Starlink also sells a DC power supply for the Standard '
            'dish, so an RV can run it without an inverter.',
      ),
    ],
  ),

  // ── Sources ──────────────────────────────────────────────────────────────
  _Section(
    number: '→',
    spokenNumber: 'Sources',
    title: 'Where these facts come from',
    children: <Widget>[
      _P(
        "Checked on 27 September 2026. Starlink's plans, names and rules "
        'change often; the dates below are part of each fact. Figures '
        'Starlink does not publish, such as how far away your gateway is, are '
        'left out on purpose.',
        small: true,
      ),
      _Sources(),
      _Callout(
        title: 'About this guide',
        body:
            "Written for people who aren't technical and want to know how "
            "Starlink works before they buy, install or troubleshoot it. "
            'Starlink is a trademark of SpaceX. This guide is independent and '
            'is not endorsed by SpaceX.',
      ),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Inline markup: **bold**, __italic__, `menu path`.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _markup = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`(.+?)`');

/// Parses the copy's inline markup into spans over [base]. Mono runs use the
/// app's inline-code face (DM Mono, GL-003 §8.5) on the recessed input fill,
/// the in-app equivalent of the print guide's `.path` chip.
List<InlineSpan> _spans(BuildContext context, String source, TextStyle base) {
  final AppColorScheme colors = context.colors;
  final TextStyle mono =
      (Theme.of(context).extension<AppMonoText>()?.inlineCode ??
              const TextStyle(fontFamily: 'DM Mono'))
          .copyWith(
            fontSize: (base.fontSize ?? AppTextSize.body) * 0.92,
            color: base.color,
            height: base.height,
            backgroundColor: colors.inputFill,
          );
  final List<InlineSpan> out = <InlineSpan>[];
  int at = 0;
  for (final RegExpMatch m in _markup.allMatches(source)) {
    if (m.start > at) out.add(TextSpan(text: source.substring(at, m.start)));
    if (m.group(1) != null) {
      out.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (m.group(2) != null) {
      out.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      out.add(TextSpan(text: m.group(3), style: mono));
    }
    at = m.end;
  }
  if (at < source.length) out.add(TextSpan(text: source.substring(at)));
  return out;
}

/// The copy with its markup removed: what a screen reader should say, and
/// what the tests look up.
String _plain(String source) => source.replaceAllMapped(
  _markup,
  (Match m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '',
);

/// Rich text over [source]'s markup. Semantics carry the plain string so a
/// screen reader never meets a stray marker.
class _Rich extends StatelessWidget {
  const _Rich(this.source, {required this.style});

  final String source;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans(context, source, style)),
      style: style,
      semanticsLabel: _plain(source),
    );
  }
}

TextStyle _body(BuildContext context, {bool small = false, Color? color}) {
  final TextTheme t = Theme.of(context).textTheme;
  final TextStyle base =
      (small ? t.bodySmall : t.bodyMedium) ?? const TextStyle();
  return base.copyWith(
    color: color ?? context.colors.textPrimary,
    height: small ? 1.45 : 1.5,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The hero: the guide's cover art, tagline and subtitle.
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Decorative: its three labels (your dish, a gateway, about 480 km
        // up) are all said by section 1's first paragraph.
        const _FigureBand(
          slug: 'cover-dish-satellite-gateway',
          zoomable: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'A plain-English guide',
          style: (t.labelMedium ?? const TextStyle()).copyWith(
            color: colors.textAccent,
            fontFamily: 'DM Mono',
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'How internet from space reaches your house or RV, how high the '
          'satellites are, and why the Wi-Fi inside matters as much as the sky '
          'above.',
          style: (t.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Current as of September 2026',
          style: _body(context, small: true, color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section scaffolding.
// ─────────────────────────────────────────────────────────────────────────────

/// A numbered section: landmark header, then its blocks with even spacing.
class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.children,
    this.spokenNumber,
  });

  final String number;
  final String title;
  final List<Widget> children;

  /// What a screen reader says for the badge, when the glyph alone would not
  /// read well ("Appendix A" rather than "A", "Sources" rather than an arrow).
  final String? spokenNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            number: number,
            title: title,
            spoken: spokenNumber ?? 'Section $number',
          ),
          for (final Widget c in children) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            c,
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.number,
    required this.title,
    required this.spoken,
  });

  final String number;
  final String title;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$spoken. $title',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              number,
              textAlign: TextAlign.center,
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
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

/// A subheading inside a section (the print guide's h3).
class _Sub extends StatelessWidget {
  const _Sub(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: (t.titleSmall ?? const TextStyle()).copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A body paragraph. [small] is the print guide's small-type register (notes
/// and source lines), rendered in secondary text.
class _P extends StatelessWidget {
  const _P(this.source, {this.small = false});

  final String source;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return _Rich(
      source,
      style: _body(
        context,
        small: small,
        color: small ? context.colors.textSecondary : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards and callouts.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _CardData {
  const _CardData(this.title, this.body);

  final String title;
  final String body;
}

/// Side-by-side cards on a wide screen, stacked on a narrow one.
class _Cards extends StatelessWidget {
  const _Cards(this.cards);

  final List<_CardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool row = c.maxWidth >= 180.0 * cards.length + AppSpacing.xs;
        final List<Widget> tiles = <Widget>[
          for (final _CardData d in cards) _Card(data: d),
        ];
        if (!row) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.data});

  final _CardData data;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              data.title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _Rich(
            data.body,
            style: _body(context, small: true, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

enum _Tone { accent, warning, danger }

/// A titled callout with a filled rail (lime, §8.13 warning, or §8.13 danger
/// for the print guide's red "stop" callout). The title
/// carries the meaning, so the rail color is never the only cue.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.title,
    required this.body,
    this.tone = _Tone.accent,
  });

  final String title;
  final String body;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color rail = switch (tone) {
      _Tone.accent => colors.primary,
      _Tone.warning => colors.statusWarning,
      _Tone.danger => colors.statusDanger,
    };
    final TextStyle base = _body(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: colors.isLight ? 4 : 3, color: rail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: base.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    _Rich(body, style: base),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numbered steps, task cards, myth/fact pairs.
// ─────────────────────────────────────────────────────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = _body(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style:
                        (Theme.of(context).textTheme.labelSmall ??
                                const TextStyle())
                            .copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  label: 'Step ${i + 1}.',
                  child: _Rich(steps[i], style: base),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One Appendix A task: title, optional "why" line, numbered steps.
class _Task extends StatelessWidget {
  const _Task({required this.title, required this.steps, this.why});

  final String title;
  final String? why;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (why != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              why!,
              style: _body(context, small: true, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          _Steps(steps),
        ],
      ),
    );
  }
}

class _Myth extends StatelessWidget {
  const _Myth({required this.myth, required this.fact});

  final String myth;
  final String fact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    Widget half(String label, Color labelColor, String body, Color fill) {
      return Container(
        color: fill,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style:
                  (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                        color: labelColor,
                        fontFamily: 'DM Mono',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.0,
                      ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            _Rich(body, style: _body(context)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          half('Myth', colors.statusDanger, myth, colors.statusDangerFill),
          half('Fact', colors.textAccent, fact, colors.surface1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bullets (the print guide's two-column list in section 6).
// ─────────────────────────────────────────────────────────────────────────────

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = _body(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Text(
                    '•  ',
                    style: base.copyWith(color: colors.textAccent),
                  ),
                ),
                Expanded(child: _Rich(item, style: base)),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tables, as one card per row. The first column is the card's title; every
// other column is a labeled line, so the column heading travels with its
// value on a phone (Find My's devices table, generalized).
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Pair {
  const _Pair(this.label, this.value);

  final String label;
  final String value;
}

@immutable
class _Row {
  const _Row(this.title, this.pairs);

  final String title;
  final List<_Pair> pairs;
}

class _RowCards extends StatelessWidget {
  const _RowCards(this.rows);

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _RowCard(row: rows[i]),
        ],
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    // A single-column row reads as title + body; its column heading
    // ("What it does") is redundant on a card and is spoken, not shown.
    final bool single = row.pairs.length == 1;
    return Semantics(
      label: <String>[
        '${row.title}.',
        for (final _Pair p in row.pairs) '${p.label}: ${_plain(p.value)}.',
      ].join(' '),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              row.title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (single) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              _Rich(
                row.pairs.single.value,
                style: _body(context, small: true, color: colors.textSecondary),
              ),
            ] else
              for (final _Pair p in row.pairs)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: Text(
                          p.label,
                          style: (t.bodySmall ?? const TextStyle()).copyWith(
                            color: colors.textTertiary,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        flex: 3,
                        child: _Rich(
                          p.value,
                          style: (t.bodySmall ?? const TextStyle()).copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appendix B: before you blame Starlink. Real checkboxes, held in memory only.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Check {
  const _Check(this.check, this.see);

  final String check;

  /// The print guide's "See" column: a section name or an Appendix A task.
  final String see;
}

class _Checklist extends StatefulWidget {
  const _Checklist();

  static const List<_Check> items = <_Check>[
    _Check(
      'Run one speed test standing next to the Starlink router, or on a '
          'laptop plugged in by cable. Use an ordinary speed-test app, or the '
          "Starlink app's Advanced speed test; its default test leaves your "
          'Wi-Fi out.',
      'The Wi-Fi inside',
    ),
    _Check(
      'Run a second test, the same way, in the room where it feels slow. If '
          "the first was fine and the second is not, it's the Wi-Fi.",
      'The Wi-Fi inside',
    ),
    _Check(
      "Look at the slow device's signal in the app's Network tab.",
      'Appendix A, 3',
    ),
    _Check(
      "If an older gadget won't connect, split the 2.4 GHz and 5 GHz "
          'networks.',
      'Appendix A, 2',
    ),
    _Check(
      'Run the obstruction check again. Trees grow, and an RV parks somewhere '
          'new every night.',
      'Trees, snow and rain',
    ),
    _Check(
      'Notice the time. Evenings are the busiest hours in most areas.',
      'Why speeds change',
    ),
    _Check(
      'Check the weather. Heavy rain or fast snow can cause short dropouts.',
      'Trees, snow and rain',
    ),
    _Check(
      "On Roam 100GB or 300GB, check whether you've used your monthly "
          'allowance.',
      'Plans for homes and RVs',
    ),
    _Check(
      'Driving? Make sure your plan allows use in motion, and your dish is '
          'one Starlink supports for it.',
      'Plans for homes and RVs',
    ),
  ];

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late final List<bool> _done = List<bool>.filled(
    _Checklist.items.length,
    false,
  );

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle see = _body(
      context,
      small: true,
      color: colors.textSecondary,
    );
    // A Material, not a decorated Container, so each row's pressed and hover
    // ink paints on the card instead of underneath it.
    return Material(
      color: colors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _Checklist.items.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: colors.border),
            CheckboxListTile(
              value: _done[i],
              onChanged: (bool? v) => setState(() => _done[i] = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: colors.primary,
              checkColor: colors.onPrimary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
              ),
              title: Text(_Checklist.items[i].check, style: _body(context)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text('See: ${_Checklist.items[i].see}', style: see),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sources, verbatim from the print guide's last page.
// ─────────────────────────────────────────────────────────────────────────────

class _Sources extends StatelessWidget {
  const _Sources();

  static const List<String> _items = <String>[
    'FCC DA 26-36 (2026-01-09): Starlink Gen2 grant, orbital shells 340 to '
        '485 km, continued operation at 525 to 535 km',
    'Reuters, SpaceNews, Space.com (2026-01-01): about 4,400 satellites '
        'lowered from about 550 km to about 480 km during 2026',
    'SpaceNews (January 2026): satellite count',
    'SpaceX, "Improving Starlink\'s Latency" (March 2024): the path through '
        'gateways and Points of Presence, laser links, 1.8 to 3.6 ms per leg, '
        'queue management in the router',
    'Starlink Specifications, DOC-1470-99699-90: latency 25 to 60 ms on '
        'land, upload typically 10 to 30 Mbps',
    'Starlink Network Update: 25.7 ms median peak-hour latency in the US '
        '(June 2025); fewer than 1% over 55 ms',
    'Starlink spec sheets: Standard 4 X, Standard 4, Starlink V5, Mini '
        '(size, weight, power, snow melt, field of view, routers, WPA2, mesh '
        'compatibility)',
    'Starlink help: kit types, obstructions, weather, snow and ice, power '
        'options, bypass mode, Wi-Fi troubleshooting',
    'Starlink Service Plans and Service Plan Descriptions, '
        'DOC-1728-44881-79; Fair Use Policy; Roam and in-motion help articles',
    'NASA: International Space Station (370 to 460 km); Hubble FAQs (about '
        '483 km, updated 2026-06-15)',
    'GPS.gov, Space Segment (20,200 km); ESA, Types of orbits (35,786 km)',
    'FCC 20-102 (Amazon Leo, 590 to 630 km); Thales Alenia Space (Iridium, '
        '780 km); Eutelsat (OneWeb, 1,200 km)',
    'Ookla, via IEEE ComSoc (July 2025): measured geostationary latency, '
        'about 680 ms median',
    'T-Mobile, Wi-Fi Calling from T-Mobile '
        '(t-mobile.com/support/coverage/wi-fi-calling-from-t-mobile): '
        'satellite internet not supported',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = _body(
      context,
      small: true,
      color: colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Text(
                    '•  ',
                    style: s.copyWith(color: colors.textAccent),
                  ),
                ),
                Expanded(child: Text(item, style: s)),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Figures: the band (gated on the manifest, recolored for light, tap to zoom)
// and its caption.
// ─────────────────────────────────────────────────────────────────────────────

/// A figure and its caption. The caption always renders (it carries limits
/// the prose does not repeat); the band renders only when the SVG is bundled.
/// The caption's semantics node reads the figure's own labels ([alt]) first,
/// so a screen reader gets what the drawing says.
class _Figure extends StatelessWidget {
  const _Figure({required this.slug, required this.alt, required this.caption});

  final String slug;
  final String alt;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FigureBand(slug: slug),
        if (StarlinkDiagrams.has(slug)) const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: '${_plain(caption)} The figure shows: $alt',
          excludeSemantics: true,
          child: _Rich(
            caption,
            style: _body(context, small: true, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Renders one figure at its intrinsic aspect ratio inside a card-styled band.
/// Dark renders the asset as authored; light loads the source and applies the
/// §8.20.7 swap (ConceptGraphicBand.applyLightSwap). A slug missing from the
/// bundle renders nothing.
class _FigureBand extends StatelessWidget {
  const _FigureBand({required this.slug, this.zoomable = true});

  final String slug;
  final bool zoomable;

  // viewBox width / height of each figure, so the band reserves the true shape
  // before the light source finishes loading (no layout jump). Kept in step
  // with tool/starlink_diagrams.py; the screen test checks every entry
  // against the SVG's own viewBox.
  static const Map<String, double> aspect = <String, double>{
    'cover-dish-satellite-gateway': 700 / 250,
    'f1-orbits-to-scale': 740 / 300,
    'f2-first-1300-km': 700 / 228,
    'f3-data-path': 700 / 270,
    'f4-latency': 700 / 268,
    'f5-phased-array': 700 / 240,
    'f6-dishes-to-scale': 700 / 180,
    'f7-shared-capacity': 700 / 248,
    'f8-tree-drops': 700 / 272,
    'f9-two-links': 700 / 210,
  };

  // Memoized swapped-light sources, so a rebuild reuses one Future per slug
  // and the string replace runs once.
  static final Map<String, Future<String>> _light = <String, Future<String>>{};

  Future<String> _lightSource() => _light.putIfAbsent(
    slug,
    () async => ConceptGraphicBand.applyLightSwap(
      await rootBundle.loadString(StarlinkDiagrams.path(slug)),
    ),
  );

  Widget _svg(bool light, {double? width, double? height}) {
    if (!light) {
      return SvgPicture.asset(
        StarlinkDiagrams.path(slug),
        fit: BoxFit.contain,
        width: width,
        height: height,
        excludeFromSemantics: true,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      );
    }
    return FutureBuilder<String>(
      future: _lightSource(),
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: width,
          height: height,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!StarlinkDiagrams.has(slug)) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final bool light = colors.isLight;
    final Widget inPage = _svg(light, width: double.infinity);
    return Container(
      key: ValueKey<String>('starlink-figure-$slug'),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double drawing = c.maxWidth / (aspect[slug] ?? 1.6);
          if (!zoomable) {
            return SizedBox(
              height: drawing,
              child: Center(child: inPage),
            );
          }
          // The zoom badge sits in the bottom-right corner of its child. A
          // clear strip under the drawing keeps it off the figure's labels.
          return SizedBox(
            height: drawing + AppSpacing.lg,
            child: ZoomableGraphic(
              semanticLabel: 'Zoom figure',
              svgBuilder: (BuildContext _, Size canvas) =>
                  _svg(light, width: canvas.width, height: canvas.height),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: inPage,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Test-only: the aspect table the band reserves space with, so a test can
/// check it against each SVG's own viewBox.
@visibleForTesting
Map<String, double> get debugStarlinkFigureAspects => _FigureBand.aspect;
