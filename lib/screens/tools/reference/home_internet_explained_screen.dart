// Home Internet, Explained: a Wi-Fi Classroom Guided Lesson. A read-along
// teaching screen built on the Find My, Explained pattern
// (find_my_explained_screen.dart): numbered landmark sections, verbatim copy,
// and dark-baked line figures recolored for light at runtime.
//
// CONTENT IS REVIEWED AND RENDERED VERBATIM. The literal strings below are the
// text of the print guide
// myPKA/Deliverables/2026-09-27-home-internet-guide/home-internet-guide.html
// (reviewed 2026-09-27; VERDICTS.md beside it records the second-opinion
// review and every edit it caused). Only the STRUCTURE is adapted for a
// scrolling screen:
//  - the print-only parts are dropped: the cover page layout and byline, the
//    table of contents ("What's inside"), page footers, and section eyebrows;
//  - "(page 7)" and "(page 10)" become "(section 6)" and "(section 9)", the
//    numbers on this screen's section badges, and "sourced on page 14"
//    becomes "sourced in the last section";
//  - "Starlink gets a guide of its own" points to the Starlink, Explained
//    Guided Lesson instead, with an Open button resolved from the catalog by
//    id (starlink-explained), so the button appears only once that lesson is
//    in the build; the comparison row's "see its own guide" says "lesson";
//  - the six figures and the cover art are re-drawn dark-baked under
//    assets/tool-diagrams/home-internet/ (tool/home_internet_diagrams.py) with
//    every label string unchanged. The print guide's blue and amber are not on
//    the GL-003 §8.20.7 allow-list, so Figure 5's upload bars are gray and its
//    caption names no color at all: the arrow legend in the figure says which
//    bar is which (Keith, 2026-09-27: "rely on the arrow legend");
//  - tables become stacks of cards so a phone can read them, and the
//    "Before you sign up" printed boxes become real checkboxes (not
//    persisted).
// Inline markup in the copy: **bold**, __italic__, and `web address` (the
// print guide's `.path` spans, rendered in the app's mono style).
//
// States (SOP-007 §5): a static reference screen with no inputs, network or
// async data, so the always-rendered state is success. Each figure degrades
// gracefully: a slug missing from the bundle, or an SVG still loading in light
// mode, renders no figure at all (never a broken-image box) while its caption
// still reads. The Starlink link degrades the same way: no catalog entry, no
// button, and the sentence still reads. The interactive elements are the
// figure zoom buttons, the Open button, the checklist checkboxes (checked /
// unchecked, theme focus ring) and the About this tool footer.
//
// THEME: every color comes from `context.colors`; no raw hex or AppColors.* in
// this file. The figures are dark-baked on the §8.20.7 allow-list and swapped
// for light by ConceptGraphicBand.applyLightSwap, the single source of truth.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark.
// Several figures carry facts the prose does not repeat (Figure 4's latency
// ranges, Figure 3's heights), so they are NOT decorative: each figure's
// caption node announces the caption, then the figure's own labels. The SVG
// itself is excluded at the leaf (GL-003 §8.6.2.2) so the zoom button stays
// reachable. Each table card reads as one sentence per row, column by column.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/home_internet_diagrams.dart';
import '../../../data/tool_catalog.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;
import '../zoomable_graphic.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kHomeInternetExplainedToolId = 'home-internet-explained';

/// The Starlink, Explained Guided Lesson this lesson points to. Resolved from
/// the catalog at build time; built on its own branch (wifi-lab/starlink-lesson)
/// and merged separately, so until it is in the catalog no button renders.
const String kStarlinkLessonToolId = 'starlink-explained';

class HomeInternetExplainedScreen extends StatelessWidget {
  const HomeInternetExplainedScreen({super.key});

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
        title: const Text('Home Internet, Explained'),
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
                ToolHelpFooter(toolId: kHomeInternetExplainedToolId),
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
        'Internet service reaches a house in one of six ways: a strand of '
        'glass, a cable TV line, an old phone line, a radio link to a tower, a '
        'dish pointed at a satellite, or your phone. Every one of them ends at '
        'a box in your house. Your Wi-Fi starts at the router, which is either '
        "a separate box or built into the provider's box.",
      ),
      _Cards(<_CardData>[
        _CardData(
          'Speed',
          'How much data per second, in Mbps (megabits per second). Download '
              'is what comes to you. Upload is what you send: video calls, '
              'photo backups, cameras.',
        ),
        _CardData(
          'Latency',
          'The delay before an answer comes back, in ms (milliseconds, '
              'thousandths of a second). It decides whether a video call or a '
              'game feels smooth.',
        ),
        _CardData(
          'Data limits',
          'How much you can use in a month before the provider slows you down '
              'or lowers your priority. Many "unlimited" plans have one.',
        ),
      ]),
      _Callout(
        title: 'The one idea that explains most of this guide',
        body:
            'The service you pay for stops at the box your provider installs. '
            'When the FCC (the US Federal Communications Commission) measures '
            'home internet across the country, its test box plugs into the '
            "router. The Wi-Fi inside the house isn't part of the number. A "
            'fast plan can still feel slow in the back bedroom, and a bigger '
            "plan won't fix that.",
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            'Your **ISP** (internet service provider) is the company you pay. '
            "The **modem**, **ONT** or **gateway** is the provider's box where "
            'their line ends. The **router** connects your devices to that '
            'box, and in most homes it also makes the Wi-Fi. Many providers '
            'hand you one **gateway** that is modem, router and Wi-Fi in one. '
            '**Gbps** is a thousand Mbps.',
      ),
    ],
  ),

  // ── 2. Six roads to your house ───────────────────────────────────────────
  _Section(
    number: '2',
    title: 'Six roads to your house',
    children: <Widget>[
      _P(
        'Each kind of service arrives a different way, and each ends at a box '
        'from the provider. The router plugs into that box, and the Wi-Fi '
        'starts at the router.',
      ),
      _Figure(
        slug: 'f1-six-roads',
        alt:
            'Fiber: strand of glass. Cable: cable TV line (coax). DSL: old '
            'copper phone line. Fixed wireless: 5G tower or local tower. '
            'Satellite: dish, high or low orbit. Phone hotspot: your cellular '
            "plan. All six run into the house to the Provider's box, then the "
            'Router. Left of the dashed line: the service you pay for. Right of '
            'it: your Wi-Fi starts here.',
        caption:
            '**Figure 1.** Six ways in, one handoff point. Everything left of '
            "the dashed line is the provider's. Everything right of it is "
            'yours. In many homes the two boxes are one combined gateway, and '
            'with a phone hotspot the phone does both jobs. The line between '
            'them stays in the same place.',
      ),
      _Table(
        columns: <String>[
          'Service',
          'How it reaches you',
          'The box in your house',
        ],
        rows: <_Row>[
          _Row('Fiber', <String>[
            'Light through a glass strand, all the way to the house',
            'ONT (optical network terminal), then your router',
          ]),
          _Row('Cable', <String>[
            'Coax from a neighborhood node that runs on fiber',
            'Cable modem, or a modem-router gateway',
          ]),
          _Row('DSL', <String>[
            'The copper phone line; speed falls with distance',
            'DSL modem, then your router',
          ]),
          _Row('Fixed wireless', <String>[
            "Radio to a cell tower (5G home internet) or to a local provider's "
                'tower',
            'A 5G gateway in a window, or a roof antenna',
          ]),
          _Row('Satellite', <String>[
            'A dish talking to satellites overhead',
            'The dish plus a modem or router',
          ]),
          _Row('Phone hotspot', <String>[
            "Your phone's cellular connection, shared over Wi-Fi",
            'Your phone',
          ]),
        ],
      ),
    ],
  ),

  // ── 3. Every road is shared ──────────────────────────────────────────────
  _Section(
    number: '3',
    title: 'Every road is shared',
    children: <Widget>[
      _P(
        'No home gets a private pipe. Every option shares something with the '
        'neighbors, which is why the same plan can feel quick at 10 in the '
        'morning and slow at 8 at night.',
      ),
      _Figure(
        slug: 'f2-every-road-is-shared',
        alt:
            'Fiber: one strand split among a group of homes, at a splitter. '
            'Cable: one coax line shared along the street, from a node. 5G '
            'home: one tower serves phones and homes. Satellite: one beam '
            'covers an area of homes.',
        caption:
            "**Figure 2.** What each option shares. The top of each panel is "
            "the provider's network; the bottom row is the neighborhood.",
      ),
      _Sub('The big numbers are for the neighborhood'),
      _P(
        "You'll see large figures for each technology. They describe the "
        'capacity of the shared network, not what one home buys.',
      ),
      _Table(
        columns: <String>[
          'Network type',
          'Capacity, shared by everyone on it',
        ],
        rows: <_Row>[
          _Row('Fiber, GPON', <String>[
            'About 2.5 Gbps down and 1.2 Gbps up',
          ]),
          _Row('Fiber, XGS-PON', <String>['10 Gbps both ways']),
          _Row('Cable, DOCSIS 3.1', <String>[
            'About 1.5 Gbps of upload capacity',
          ]),
          _Row('Cable, DOCSIS 4.0', <String>[
            'Up to 10 Gbps down and 6 Gbps up',
          ]),
        ],
      ),
      _P(
        'GPON, XGS-PON and DOCSIS are the names of the standards the equipment '
        'follows. Your plan sets the most you can get from that shared '
        "network. It isn't a private lane reserved for you.",
        small: true,
      ),
    ],
  ),

  // ── 4. The wired options ─────────────────────────────────────────────────
  _Section(
    number: '4',
    title: 'The wired options',
    children: <Widget>[
      _P(
        'Three services come in on a physical line. They differ most in upload '
        'speed and in how much the delay rises when the line gets busy.',
      ),
      _Cards(<_CardData>[
        _CardData(
          'Fiber',
          'Light travels through a strand of glass all the way to your house. '
              'The strand usually serves a group of homes through an unpowered '
              'splitter, which is why the industry calls it a PON (passive '
              'optical network). Where the fiber ends, the provider installs an '
              'ONT and your router plugs into it.\n\n'
              '**What stands out:** the lowest delay the FCC measured, and '
              "upload that's often the same as download. Rain doesn't affect "
              'it. The box in the house needs power.',
        ),
      ], maxPerRow: 1),
      _Cards(<_CardData>[
        _CardData(
          'Cable',
          'A coax line, the same kind cable TV uses, runs from your house to a '
              'node in the neighborhood, and the node connects back to the '
              'provider over fiber. Everyone on that stretch of coax shares it. '
              'In the house: a cable modem, or a gateway that combines the '
              'modem and router in one box.\n\n'
              '**What stands out:** fast downloads, and much slower uploads. '
              'Busy evenings are when the neighborhood sharing shows.',
        ),
      ], maxPerRow: 1),
      _Cards(<_CardData>[
        _CardData(
          'DSL',
          'Data over the copper phone line. The farther you are from the phone '
              "company's equipment, the slower it gets.\n\n"
              "**What stands out:** in the FCC's 13th national report (2024), "
              'DSL was the weakest performer. Providers delivered 63% to 72% of '
              "their advertised speed on the FCC's consistency measure, and "
              'delay rose the most when the line was busy.',
        ),
      ], maxPerRow: 1),
      _Callout(
        tone: _Tone.warning,
        title: 'DSL is going away',
        body:
            'AT&T says it has FCC approval to discontinue legacy copper '
            'services at more than 30% of its copper wire centers, effective '
            'in late 2026, and plans to retire most of its copper outside '
            'California by the end of 2029. Timing depends on your address, and '
            'customers get notice first. If DSL is all you have, check the map '
            'for other options now (Appendix, step 1).',
      ),
      _Callout(
        title: 'What the FCC calls broadband',
        body:
            "Since 2024, 100 Mbps down and 20 Mbps up. It's a useful floor when "
            'you compare plans.',
      ),
    ],
  ),

  // ── 5. The wireless options ──────────────────────────────────────────────
  _Section(
    number: '5',
    title: 'The wireless options',
    children: <Widget>[
      _Cards(<_CardData>[
        _CardData(
          '5G home internet',
          'A box in your window talks to the same cell towers your phone uses. '
              'One large carrier, T-Mobile, publishes typical speeds of **133 '
              'to 415 Mbps down and 12 to 55 Mbps up**, and says: __"During '
              'congestion, customers on this plan may notice speeds lower than '
              'other customers and further reduction if using >1.2TB/mo., due '
              'to data prioritization."__ Home plans are for one approved '
              'address; moving the box elsewhere needs a different plan.',
        ),
        _CardData(
          'Local wireless provider',
          'A local company (a WISP, wireless internet service provider) mounts '
              'an antenna on your roof, aimed at its tower. It needs a clear '
              'line of sight to that tower. Speed and delay depend entirely on '
              'the provider, so read its Broadband Facts label.',
        ),
      ], maxPerRow: 2),
      _Cards(<_CardData>[
        _CardData(
          'Satellite, high orbit',
          'A dish aimed at one satellite that stays over the same spot, 35,786 '
              'km (22,236 miles) above the equator. That distance puts a floor '
              'under the delay that no equipment can remove (section 6). Plans '
              'usually give a set amount of priority data each month.',
        ),
        _CardData(
          'Satellite, low orbit',
          '**Starlink** satellites fly about 480 km (300 miles) up. Starlink '
              'says delay is 25 to 60 ms on land and upload is typically 10 to '
              '30 Mbps. Starlink has a Guided Lesson of its own, Starlink, '
              'Explained. **Amazon Leo**, formerly Project Kuiper, is launching '
              'satellites and says home service starts later in 2026. Check '
              'before you wait for it.',
        ),
      ], maxPerRow: 2),
      _LessonLink(toolId: kStarlinkLessonToolId),
      _Cards(<_CardData>[
        _CardData(
          'Phone hotspot',
          "Uses your phone plan's data, with the hotspot allowance and priority "
              'your plan sets. Fine for a trip or a backup; a poor fit for a '
              'whole household.',
        ),
      ], maxPerRow: 1),
      _Figure(
        slug: 'f3-orbit-heights',
        alt:
            "Earth's surface at the left; ticks mark each height. Starlink, "
            'about 480 km (300 miles). '
            'Amazon Leo, 590 to 630 km (370 to 390 miles). GPS, 20,200 km. '
            'High-orbit satellite, 35,786 km (22,236 miles), at the far right.',
        caption:
            '**Figure 3.** Height above the Earth, drawn to scale. The '
            'low-orbit satellites sit so close to the surface that their ticks '
            'almost touch, so their dots are drawn one above the other. GPS is '
            'shown for reference.',
      ),
    ],
  ),

  // ── 6. Latency: why lag is its own number ────────────────────────────────
  _Section(
    number: '6',
    title: 'Latency: why lag is its own number',
    children: <Widget>[
      _P(
        'Speed is how much data arrives per second. Latency is how long each '
        'answer takes to come back. A video call, a game, or a web page that '
        "loads in many small pieces all wait on latency, and a faster plan "
        "doesn't shorten it.",
      ),
      _Figure(
        slug: 'f4-idle-latency',
        alt:
            'Fiber: 7 to 14 ms. Cable: 12 to 24 ms. DSL: 23 to 34 ms. '
            "Low-orbit satellite: 25 to 60 ms (Starlink's figure). High-orbit "
            'satellite: physics alone, about 480 ms; measured, about 680 ms.',
        caption:
            '**Figure 4.** Delay with nothing else running on the line. Wired '
            'figures: FCC measurements from its 2022 test period, published in '
            "2024. Low orbit: Starlink's published range. High orbit: the "
            'speed-of-light floor, and independent measurements from early '
            '2025. The axis breaks between 100 and 400 ms so the high-orbit bar '
            'fits.',
      ),
      _Callout(
        title: "Why a high-orbit satellite can't be quick",
        body:
            'A request goes up to the satellite and down to the provider, and '
            'the answer goes up and down again: four trips of 35,786 km, about '
            '143,000 km in all. At the speed of light that takes about 0.48 '
            "seconds before any equipment adds its own delay. Starlink's "
            'satellites are about 75 times closer, so the same trip takes a '
            'few thousandths of a second.',
      ),
      _Sub('When someone else is using the line'),
      _P(
        'The numbers above are for an idle line. The FCC found that delay '
        'under load is __"significantly higher than idle latency, with a more '
        'pronounced difference for DSL subscribers."__ On its charts, DSL delay '
        'climbed to several hundred milliseconds while a big upload or '
        "download ran. That's why a video call can stutter the moment someone "
        'starts backing up their photos. The FCC notes that some providers '
        'have since added smarter traffic handling, which keeps one big '
        'transfer from making everything else wait.',
      ),
    ],
  ),

  // ── 7. Upload, and data limits ───────────────────────────────────────────
  _Section(
    number: '7',
    title: 'Upload, and data limits',
    children: <Widget>[
      _P(
        'Most plans advertise the download number. Upload matters more than '
        'people expect: every video call sends your camera, every photo backup '
        'sends files up, and every security camera uploads all day.',
      ),
      _Figure(
        slug: 'f5-download-upload',
        alt:
            'Down arrow: download. Up arrow: upload. Widths show the usual '
            'balance, not exact speeds. Fiber: often equal. Cable: upload much '
            'smaller. 5G home: about a tenth. DSL: low both ways.',
        caption:
            '**Figure 5.** Download and upload. The 5G ratio '
            "comes from one carrier's published typical speeds: 133 to 415 "
            'Mbps down, 12 to 55 Mbps up.',
      ),
      _Sub('"Unlimited" usually has a line in it'),
      _Table(
        columns: <String>['Service', "What the providers' own terms say"],
        rows: <_Row>[
          _Row('5G home', <String>[
            'Lower priority than other customers when the tower is busy, and '
                'lower again past 1.2 TB in a month (T-Mobile)',
          ]),
          _Row('High-orbit satellite', <String>[
            'One provider gives a monthly amount of Priority Data, then '
                'unlimited Standard Data that comes second. Another calls its '
                "plan unlimited but may lower your priority if you're trending "
                'past 850 GB in 30 days.',
          ]),
          _Row('Cable', <String>[
            'Varies. Some older plans at one large cable provider still carry '
                "a 1.2 TB monthly cap; its current plans don't.",
          ]),
          _Row('Fiber', <String>['Usually no limit. Check the label.']),
        ],
      ),
      _Callout(
        title: 'The label tells you',
        body:
            'FCC rules require every provider to show a **Broadband Facts** '
            'label where you sign up. It lists the monthly price, fees, data '
            'allowance, and typical download speed, upload speed and latency. '
            'Since 14 September 2026 the page may show a link or icon that '
            'opens the label instead of the label itself. Compare the labels '
            'side by side before you choose.',
      ),
    ],
  ),

  // ── 8. All the options side by side ──────────────────────────────────────
  _Section(
    number: '8',
    title: 'All the options side by side',
    children: <Widget>[
      _P(
        'Figures are sourced in the last section and dated where they change. '
        '"Varies" means no single number holds across providers; the '
        'Broadband Facts label has the one for your address.',
        small: true,
      ),
      _Table(
        columns: <String>[
          'Service',
          'Download',
          'Upload',
          'Delay, idle',
          'Data limits',
          'Watch for',
        ],
        rows: <_Row>[
          _Row('Fiber', <String>[
            'Plans up to 1 Gbps and beyond',
            'Often equal to download',
            '7 to 14 ms (FCC)',
            'Usually none',
            'Not in every area yet',
          ]),
          _Row('Cable', <String>[
            'Hundreds of Mbps to multi-gig',
            'Much lower than download',
            '12 to 24 ms (FCC)',
            'Varies',
            'Neighborhood sharing in the evening',
          ]),
          _Row('DSL', <String>[
            'Low, falls with distance',
            'Lower',
            '23 to 34 ms (FCC)',
            'Varies',
            'Weakest at delivering advertised speed; being retired',
          ]),
          _Row('5G home', <String>[
            '133 to 415 Mbps typical (T-Mobile)',
            '12 to 55 Mbps typical (T-Mobile)',
            'Not published',
            'Lower priority when busy',
            'Tower load; signal at your window',
          ]),
          _Row('Local wireless', <String>[
            'Varies',
            'Varies',
            'Varies',
            'Varies',
            'Needs line of sight to the tower',
          ]),
          _Row('High-orbit satellite', <String>[
            'Varies by plan',
            'Varies by plan',
            'About 0.5 to 0.7 seconds',
            'Priority data, then slower',
            'Video calls and gaming suffer',
          ]),
          _Row('Low-orbit satellite (Starlink)', <String>[
            'Depends on plan',
            '10 to 30 Mbps typical',
            '25 to 60 ms',
            'Depends on plan',
            'Needs open sky; see its own lesson',
          ]),
          _Row('Amazon Leo', <String>[
            'Announced: up to 100 Mbps (Leo Nano) or 400 Mbps (Leo Pro)',
            'Not published',
            'Not published',
            'Not published',
            'Not selling to homes as of July 2026',
          ]),
          _Row('Phone hotspot', <String>[
            'Varies',
            'Lower',
            'Varies',
            "Your plan's hotspot allowance",
            'Phone battery and signal',
          ]),
        ],
      ),
      _Callout(
        title: 'Reading the delay column',
        body:
            "The wired figures are the FCC's own measurements from its 2022 "
            "test period. They're the numbers with nothing else running. In the "
            "FCC's tests, every wired service got much slower to respond when "
            'the line was busy (section 6).',
      ),
    ],
  ),

  // ── 9. Where the FCC measures, and where you do ──────────────────────────
  _Section(
    number: '9',
    title: 'Where the FCC measures, and where you do',
    children: <Widget>[
      _P(
        'The FCC runs a national test of US home internet called Measuring '
        "Broadband America. Volunteers get test boxes that, in the FCC's "
        'words, __"run pre-installed software on off-the-shelf routers."__ The '
        "box plugs in at the router. So the FCC's numbers cover the service "
        'right up to your router, and nothing after it.',
      ),
      _Figure(
        slug: 'f6-where-the-fcc-measures',
        alt:
            "Internet, then the provider's line to the Provider's box, then the "
            'Router, then Wi-Fi, through walls, to your phone, back bedroom. '
            'What the FCC measures: the service, up to the router. What a speed '
            'test on your phone measures: the service plus your Wi-Fi.',
        caption:
            '**Figure 6.** Two different measurements. When they disagree, the '
            'difference is your Wi-Fi.',
      ),
      _Sub('Test the service, then test the Wi-Fi'),
      _Steps(<String>[
        'Plug a laptop into the router with a network cable and run an '
            "internet speed test. That's the service you're paying for.",
        'Take the same laptop, or your phone, to the room where things feel '
            'slow. Run the test again over Wi-Fi.',
        'Compare. If the wired test looks like your plan and the Wi-Fi test '
            "doesn't, the fix is in your house: where the router sits, or "
            'adding Wi-Fi access points (a mesh system is one kind) to cover '
            "the rooms you use. A bigger plan or a second router won't help.",
      ]),
      _Callout(
        tone: _Tone.warning,
        title: 'No network port on your laptop?',
        body:
            'Many new laptops only have USB-C. A USB-C to Ethernet adapter '
            "costs little and makes step 1 possible. If you can't plug in at "
            'all, stand in the same room as the router for the first test. On a '
            'plan faster than 1 Gbps, the laptop, adapter, cable and router '
            'port all need to be faster than 1 Gbps too, or the wired test '
            'stops at 1 Gbps.',
      ),
    ],
  ),

  // ── 10. Which one should I pick? ─────────────────────────────────────────
  _Section(
    number: '10',
    title: 'Which one should I pick?',
    children: <Widget>[
      _P(
        'Look up your address first (Appendix, step 1), then work down this '
        'list. Stop at the first question you can answer yes to.',
      ),
      _Task(
        title: '1. Is fiber available?',
        why:
            'Take it. It has the lowest delay the FCC measured, the best '
            "upload, and weather doesn't touch it.",
      ),
      _Task(
        title: '2. No fiber, but cable?',
        why:
            'Cable is a good choice. If you video call, back up photos or run '
            'cameras, read the upload speed on the Broadband Facts label before '
            'you pick a plan.',
      ),
      _Task(
        title: '3. Only DSL?',
        why:
            'Check the map for 5G home internet and low-orbit satellite first. '
            'High-orbit satellite is slower to respond than most DSL lines. DSL '
            "delivered the least of its advertised speed in the FCC's testing, "
            "and it's being retired.",
      ),
      _Task(
        title: '4. Rural, with a 5G home offer?',
        why:
            'Worth trying. Expect it to slow down when the tower is busy, and '
            "know where your plan's priority line sits.",
      ),
      _Task(
        title: '5. Nothing wired, and open sky?',
        why:
            'Low-orbit satellite, which today means Starlink. Choose high-orbit '
            'satellite only when nothing else is offered: the half-second delay '
            'makes video calls and games poor.',
      ),
      _Task(
        title: '6. RV or travel?',
        why:
            "A travel satellite plan or your phone's hotspot, not a home plan "
            "tied to one address. Check the plan's rules for use while moving.",
      ),
      _Callout(
        title: 'Whatever you pick, the Wi-Fi is its own decision',
        body:
            'The service arrives at one box in one spot. From there, the Wi-Fi '
            'has to reach every room you use. Plan where the router goes before '
            "the installer arrives, and test both ways once it's in (section "
            '9).',
      ),
    ],
  ),

  // ── 11. Six things people get wrong ──────────────────────────────────────
  _Section(
    number: '11',
    title: 'Six things people get wrong',
    children: <Widget>[
      _P('Each of these leads people to pay for the wrong fix.'),
      _Myth(
        myth: 'Slow in the bedroom means a slow internet plan.',
        fact:
            "Often it's the Wi-Fi. The FCC measures at the router. A test on "
            'your phone in the back bedroom measures the service and the Wi-Fi '
            'together.',
      ),
      _Myth(
        myth: 'A faster plan fixes lag.',
        fact:
            'Lag is latency. It rises sharply when someone else is using the '
            "line, most of all on DSL, and more Mbps doesn't lower it.",
      ),
      _Myth(
        myth: 'The FCC map says my address gets 1 Gbps, so it does.',
        fact:
            'The map shows what providers report to the FCC. If a listing is '
            'wrong, you can challenge it.',
      ),
      _Myth(
        myth: "Upload doesn't matter.",
        fact:
            'Video calls, cloud backups and cameras all send data up. On cable '
            'and 5G home internet, upload is a fraction of download.',
      ),
      _Myth(
        myth: "Amazon's satellite internet is here.",
        fact:
            'Amazon Leo, formerly Project Kuiper, had not started home service '
            'as of July 2026. Amazon says it starts later in 2026.',
      ),
      _Myth(
        myth: 'Unlimited means unlimited.',
        fact:
            'Many unlimited 5G home and satellite plans lower your priority past '
            'a monthly amount. The Broadband Facts label says where.',
      ),
    ],
  ),

  // ── Appendix: check, challenge, test ─────────────────────────────────────
  _Section(
    number: 'A',
    spokenNumber: 'Appendix',
    title: 'Check, challenge, test',
    children: <Widget>[
      _Task(
        title: "1. See what's offered at your address",
        why:
            "The FCC's national map lists the providers that report serving "
            'your home.',
        steps: <String>[
          'Go to `broadbandmap.fcc.gov`',
          'Type your address in **Search by Address** and pick it from the '
              'list',
          'Read the **Fixed Broadband** list: providers, technology, and the '
              'speeds they report. Services under 25 Mbps download are hidden '
              'by default; open **Service Filters** to see them',
        ],
      ),
      _Task(
        title: '2. Report a wrong listing',
        why:
            "For a provider that won't actually install service, or a home "
            'missing from the map. Slow speed on a service you already have '
            'counts as a consumer complaint, not a map challenge.',
        steps: <String>[
          'With the **Fixed Broadband** tab selected, choose **Availability '
              'Challenge** below your address, pick the provider and the '
              'reason, add evidence such as a screenshot or email, and submit',
          'If your home is missing or in the wrong place, use the location '
              'challenge link beside the address',
        ],
      ),
      _Task(
        title: '3. Compare the labels',
        why:
            "Every provider's sign-up page has to show a Broadband Facts label, "
            'or a link or icon that opens it.',
        steps: <String>[
          "Find the label on each provider's plan page",
          'Write down typical download, upload and latency, the data '
              'allowance, and every fee',
        ],
      ),
      _Task(
        title: '4. After installation, test both ways',
        why:
            'The one test that tells you whether a problem is the service or '
            'the Wi-Fi.',
        steps: <String>[
          'Wired laptop at the router: run a speed test',
          'Over Wi-Fi in the room that feels slow: run it again and compare '
              '(section 9)',
        ],
      ),
      _Sub('Before you sign up'),
      _Checklist(),
    ],
  ),

  // ── Sources ──────────────────────────────────────────────────────────────
  _Section(
    number: '→',
    spokenNumber: 'Sources',
    title: 'Where these facts come from',
    children: <Widget>[
      _P(
        'Checked on 27 September 2026. Provider plans change often; the '
        'Broadband Facts label is always the current word for your address. '
        'Prices are deliberately left out.',
        small: true,
      ),
      _Sources(),
      _Callout(
        title: 'About this guide',
        body:
            "Written for people who aren't technical and want to choose home "
            'internet with their eyes open. Provider and product names are '
            'trademarks of their owners. This guide is independent and isn\'t '
            'affiliated with or endorsed by any provider named in it.',
      ),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Inline markup: **bold**, __italic__, `web address`.
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
  final TextStyle base = (small ? t.bodySmall : t.bodyMedium) ?? const TextStyle();
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
        // Decorative: the print cover's five lines into one house. Figure 1
        // draws the same idea with its labels.
        const _FigureBand(slug: 'cover-roads-to-the-house', zoomable: false),
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
          'Fiber, cable, DSL, 5G, satellite: how each one reaches your house, '
          'what to check before you sign up, and why your Wi-Fi is a separate '
          'question.',
          style: (t.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Written for US homes · September 2026',
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
  const _Cards(this.cards, {this.maxPerRow = 3});

  final List<_CardData> cards;

  /// The print guide's grid width: three for the short-answer cards, two for
  /// the wireless options, one for a full-width card. More cards than this
  /// stack.
  final int maxPerRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool row =
            cards.length <= maxPerRow &&
            c.maxWidth >= 180.0 * cards.length + AppSpacing.xs;
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

enum _Tone { accent, warning }

/// A titled callout with a filled rail (lime, or §8.13 warning). The title
/// carries the meaning, so the rail color is never the only cue.
class _Callout extends StatelessWidget {
  const _Callout({required this.title, required this.body, this.tone = _Tone.accent});

  final String title;
  final String body;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color rail = tone == _Tone.warning ? colors.statusWarning : colors.primary;
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
                    style: (Theme.of(context).textTheme.labelSmall ??
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

/// One task card: title, optional "why" line, optional numbered steps. The
/// decision list (section 10) uses title and "why" only;
/// the Appendix adds steps.
class _Task extends StatelessWidget {
  const _Task({
    required this.title,
    this.why,
    this.steps = const <String>[],
  });

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
          if (steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _Steps(steps),
          ],
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
              style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
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
// Tables, as one card per row.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Row {
  const _Row(this.title, this.cells);

  /// The row's first column (the service or network type).
  final String title;

  /// The remaining columns, in order.
  final List<String> cells;
}

/// A print table rendered as a stack of cards: the first column is each
/// card's title, the rest are label and value lines. A phone can read it
/// without sideways scrolling, and each card reads as one sentence.
class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows});

  /// Column headings, the first being the title column.
  final List<String> columns;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _RowCard(columns: columns, row: rows[i]),
        ],
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.columns, required this.row});

  final List<String> columns;
  final _Row row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    // A two-column table has one value per row: its heading adds nothing the
    // card title does not, so it is spoken but not drawn.
    final bool labelled = columns.length > 2;
    return Semantics(
      label: <String>[
        '${columns.first}: ${row.title}.',
        for (int i = 0; i < row.cells.length; i++)
          '${columns[i + 1]}: ${row.cells[i]}.',
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
            for (int i = 0; i < row.cells.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: labelled
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 2,
                            child: Text(
                              columns[i + 1],
                              style: (t.bodySmall ?? const TextStyle())
                                  .copyWith(
                                    color: colors.textTertiary,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            flex: 3,
                            child: Text(
                              row.cells[i],
                              style: (t.bodySmall ?? const TextStyle())
                                  .copyWith(
                                    color: colors.textPrimary,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        row.cells[i],
                        style: _body(
                          context,
                          small: true,
                          color: colors.textSecondary,
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
// A link to another lesson, resolved from the catalog by id.
// ─────────────────────────────────────────────────────────────────────────────

/// An Open button for the catalog tool [toolId]. It looks the id up at build
/// time, so it renders only when that tool is in this build (the Starlink
/// lesson is merged on its own branch). No entry, no button: the sentence that
/// names the lesson still reads.
class _LessonLink extends StatelessWidget {
  const _LessonLink({required this.toolId});

  final String toolId;

  static ToolEntry? _find(String id) {
    for (final ToolCategory c in kToolCategories) {
      for (final ToolEntry t in c.tools) {
        if (t.id == id && t.isLive) return t;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ToolEntry? entry = _find(toolId);
    if (entry == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey<String>('home-internet-link-$toolId'),
        onPressed: () => Navigator.of(context).pushNamed(entry.routeName),
        icon: const Icon(Icons.open_in_new),
        label: Text('Open ${entry.title}'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The "Before you sign up" checklist. Real checkboxes, held in memory only.
// ─────────────────────────────────────────────────────────────────────────────

class _Checklist extends StatefulWidget {
  const _Checklist();

  static const List<String> items = <String>[
    'Your address on the FCC map, with every technology listed',
    'Upload speed on the label, if anyone in the house video calls, backs up '
        'photos or runs cameras',
    'Where "unlimited" lowers your priority, in GB or TB per month',
    'Typical latency on the label, if anyone games or works on video calls',
    "Where the provider's box and the router will sit, so the Wi-Fi reaches "
        'the rooms you use',
    'If you need internet in a power cut: which boxes need power, and whether '
        'a battery backup is offered',
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
              title: Text(_Checklist.items[i], style: _body(context)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sources.
// ─────────────────────────────────────────────────────────────────────────────

class _Sources extends StatelessWidget {
  const _Sources();

  static const List<String> _items = <String>[
    'FCC, Thirteenth Measuring Broadband America Fixed Broadband Report, FCC '
        '24-136, Appendix C (2024; test period 2022): idle latency by '
        'technology, latency under load, DSL delivery of advertised speed, '
        'test boxes at the router',
    'FCC Broadband Data Collection and National Broadband Map help pages: what '
        'the map shows, the December 2025 data, availability and location '
        'challenges',
    'FCC Broadband Consumer Labels (fcc.gov/broadbandlabels) and FCC 22-7',
    'FCC 24-27 (2024): the 100/20 Mbps broadband benchmark',
    'ITU-T G.9807.1 (XGS-PON); ITU-T G.984.2 (GPON line rates), as cited by '
        'gpon.com',
    'CableLabs: DOCSIS 4.0 technology page; "Cable broadband from DOCSIS 3.1 '
        'to DOCSIS 4.0"',
    'Broadband Breakfast, 2026-01-13: AT&T approval to discontinue copper '
        'service',
    'T-Mobile Home Internet FAQ and plans pages: typical speeds and data '
        'prioritization',
    'HughesNet plans and FAQ; Viasat FAQ and Broadband Facts label: priority '
        'data terms',
    'Xfinity data usage pages: unlimited current plans, 1.2 TB on some legacy '
        'plans',
    'Starlink Specifications (latency 25 to 60 ms on land; upload typically '
        '10 to 30 Mbps)',
    'Amazon, "What is Amazon Leo" and mission updates (fetched); CNBC, '
        '2026-07-02: 396 satellites, consumer service not yet launched',
    'FCC 20-102: Amazon Leo orbital altitudes of 590, 610 and 630 km',
    'ESA, Types of orbits (35,786 km); GPS.gov, Space Segment (20,200 km)',
    'IEEE ComSoc Technology Blog, 2025-07-18, and Benton Institute: measured '
        'high-orbit satellite latency, early 2025',
    'Speed-of-light arithmetic: 4 × 35,786 km ÷ 299,792 km/s ≈ 0.48 s',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = _body(context, small: true, color: colors.textSecondary);
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
                  child: Text('•  ', style: s.copyWith(color: colors.textAccent)),
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

/// A figure and its caption. The caption always renders (it carries sources
/// and limits the prose does not repeat); the band renders only when the SVG
/// is bundled. The caption's semantics node reads the caption, then the
/// figure's own labels ([alt]), so a screen reader gets what the drawing says.
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
        if (HomeInternetDiagrams.has(slug))
          const SizedBox(height: AppSpacing.xs),
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
  // before the light source finishes loading (no layout jump). Must match
  // tool/home_internet_diagrams.py.
  static const Map<String, double> _aspect = <String, double>{
    'cover-roads-to-the-house': 700 / 250,
    'f1-six-roads': 700 / 330,
    'f2-every-road-is-shared': 700 / 250,
    'f3-orbit-heights': 700 / 170,
    'f4-idle-latency': 700 / 250,
    'f5-download-upload': 700 / 226,
    'f6-where-the-fcc-measures': 700 / 240,
  };

  // Memoized swapped-light sources, so a rebuild reuses one Future per slug
  // and the string replace runs once.
  static final Map<String, Future<String>> _light = <String, Future<String>>{};

  Future<String> _lightSource() => _light.putIfAbsent(
    slug,
    () async => ConceptGraphicBand.applyLightSwap(
      await rootBundle.loadString(HomeInternetDiagrams.path(slug)),
    ),
  );

  Widget _svg(bool light, {double? width, double? height}) {
    if (!light) {
      return SvgPicture.asset(
        HomeInternetDiagrams.path(slug),
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
    if (!HomeInternetDiagrams.has(slug)) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final bool light = colors.isLight;
    final Widget inPage = _svg(light, width: double.infinity);
    return Container(
      key: ValueKey<String>('home-internet-figure-$slug'),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double drawing = c.maxWidth / (_aspect[slug] ?? 1.6);
          if (!zoomable) {
            return SizedBox(height: drawing, child: Center(child: inPage));
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
