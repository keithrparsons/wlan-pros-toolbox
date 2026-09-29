// One Talker per Channel. A Wi-Fi Classroom Guided Lesson for beginners and
// the book audience, on the pattern of Why the TV and the Printer Vanish on
// Guest Wi-Fi: numbered landmark sections from lesson_parts.dart, one
// interactive stage, a sources section and the About this tool footer. It
// adds the Present button (as box-vs-hand does): the presenter layout shows
// the same stage and controls over the SAME controller.
//
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 48-one-talker.md. Plan: Deliverables/2026-09-29-classroom-eight-features/
// PLAN.md, Feature 3 and Keith's rulings of 2026-09-29.
//
// CLEAN ROOM: the copy rests on IEEE Std 802.11-2024 (10.2.2, 10.2.3.2,
// 10.3.2.1, 10.23.2). The analogy is Keith's choice (2026-09-29): a
// walkie-talkie. The rule is always scoped to one channel; OFDMA and MU-MIMO
// are named as later exceptions and not taught. No outside lab is credited
// or followed.
//
// Model: lib/services/wifi_lab/one_talker_model.dart. Controller, stage,
// controls and parts: one_talker_{controller,stage,controls,parts}.dart.
//
// States (SOP-007 §5): no network or async data; the copy and the model are
// compiled in, so the rendered state is success. Disabled and interactive
// states are in the controls; the one-device state is drawn in words.
//
// THEME: every color comes from `context.colors` (and the Classroom client
// palette in the stage).
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark;
// the stage's headline is a live region; the illustration has one label.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/lesson/lesson_blocks.dart'
    show LessonNumbered, LessonToolLinkView;
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'lesson_parts.dart';
import 'one_talker_controller.dart';
import 'one_talker_controls.dart';
import 'one_talker_parts.dart';
import 'one_talker_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kOneTalkerToolId = 'one-talker';

/// The screen and catalog title.
const String kOneTalkerTitle = 'One Talker per Channel';

/// MU-MIMO with a non-breaking hyphen (U+2011, in IBM Plex Sans), so it
/// never splits across two lines on a phone. Written as an escape to keep
/// the source ASCII.
const String kMuMimo = 'MU\u2011MIMO';

/// The rule, scoped to one channel (Keith, 2026-09-29).
const String kOneTalkerRule =
    'On the same channel, only one device can transmit at a time.';

class OneTalkerScreen extends StatefulWidget {
  const OneTalkerScreen({super.key});

  @override
  State<OneTalkerScreen> createState() => _OneTalkerScreenState();
}

class _OneTalkerScreenState extends State<OneTalkerScreen> {
  final OneTalkerController _controller = OneTalkerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: kOneTalkerTitle,
    stage: OneTalkerStage(controller: _controller),
    controls: OneTalkerControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kOneTalkerTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.oneTalker, builder: _presenter),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double edge = constraints.maxWidth >= 720
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
                    const LessonHero(
                      eyebrow: 'A plain-English lesson',
                      promise:
                          'Why Wi-Fi slows down when everyone is home: on '
                          'one channel, devices take turns.',
                    ),
                    ..._before,
                    _TryIt(controller: _controller),
                    ..._after,
                    const ToolHelpFooter(toolId: kOneTalkerToolId),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sections 1 and 2.
const List<Widget> _before = <Widget>[
  // ── 1. The short answer ──────────────────────────────────────────────────
  LessonSection(
    number: '1',
    title: 'The short answer',
    children: <Widget>[
      LessonP(
        'Wi-Fi devices take turns. **$kOneTalkerRule** Every other device '
        'on that channel waits until the air is quiet.',
      ),
      LessonP(
        'So the time on a channel is shared. If 4 devices all have something '
        'to send, each gets about a quarter of the time. With 12, each gets '
        'about a twelfth. The access point did not get slower. The line of '
        'devices waiting for a turn got longer.',
      ),
      // Accent, not warning: GL-003 §12.2-0 keeps warm hues for a real
      // caution.
      LessonCallout(
        title: 'A word on the words',
        body:
            'An **access point** is the box that sends and receives Wi-Fi. A '
            '**channel** is the slice of radio frequencies an access point '
            'and its devices use. To **transmit** is to send by radio. A '
            'device **associates** with an access point when it connects to '
            'it. **Airtime** is the time a device spends transmitting.',
      ),
    ],
  ),

  // ── 2. Like a walkie-talkie ──────────────────────────────────────────────
  // Larry's wording of Keith's walkie-talkie choice (2026-09-29), for Keith
  // to review. Spec 48, "The analogy".
  LessonSection(
    number: '2',
    title: 'Like a walkie-talkie',
    children: <Widget>[
      WalkieTalkiePair(),
      LessonP(
        'Think of a pair of walkie-talkies. Only one person can talk at a '
        'time. You hold the button, say what you need to say, then say '
        '"over" so the other person knows it is their turn.',
      ),
      LessonP(
        'Wi-Fi works the same way. **$kOneTalkerRule** Every device listens '
        'first and talks only when the air is quiet. When one finishes, the '
        'air goes quiet again, and that quiet is the "over": another device '
        'can take its turn.',
      ),
      LessonP(
        'Later lessons show two exceptions, OFDMA and $kMuMimo, where one '
        'access point sends to several devices in the same moment. This '
        'lesson leaves them out.',
        small: true,
      ),
    ],
  ),
];

/// Section 3: the interactive stage.
class _TryIt extends StatelessWidget {
  const _TryIt({required this.controller});

  final OneTalkerController controller;

  @override
  Widget build(BuildContext context) {
    return LessonSection(
      number: '3',
      title: 'Try it: add devices',
      children: <Widget>[
        const LessonP(
          'Add devices and watch every bar shrink. Press {{Next turn}} to pass '
          'the turn around the room: on one channel, only one device talks '
          'at a time.',
        ),
        LessonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const LessonLabel('Try it'),
              const SizedBox(height: AppSpacing.xs),
              OneTalkerControls(controller: controller),
              const SizedBox(height: AppSpacing.md),
              OneTalkerStage(controller: controller),
            ],
          ),
        ),
        const LessonP(
          'A simplified picture: every device always has something to send, '
          'turns are shared evenly, nothing collides, and the two channels do '
          'not leak into each other.',
          small: true,
        ),
      ],
    );
  }
}

/// Sections 4 to 7 and the sources.
const List<Widget> _after = <Widget>[
  // ── 4. Two access points ─────────────────────────────────────────────────
  LessonSection(
    number: '4',
    title: 'Two access points: one channel or two',
    children: <Widget>[
      LessonP(
        'For the second access point, pick {{Same}}, then {{Other}}, and '
        'compare.',
      ),
      _Card(
        title: 'Same channel: one waiting line',
        body:
            'Two access points on the same channel share one channel of '
            'time. All of their devices take turns together, so with 4 on '
            'one and 3 on the other, each gets 1/7. The second access point '
            'added no time to share.',
      ),
      _Card(
        title: 'Different channels: two waiting lines',
        body:
            'On different channels, each access point has its own time. Its '
            'devices share only that, 1/4 each on one and 1/3 each on the '
            'other, and one device on each channel can transmit at the same '
            'moment.',
      ),
      LessonP(
        "A neighbor's access point on your channel, close enough for your "
        'devices to hear, is in your waiting line too. This is why Wi-Fi '
        'pros plan channels.',
      ),
    ],
  ),

  // ── 5. One slow talker ───────────────────────────────────────────────────
  LessonSection(
    number: '5',
    title: 'One slow talker',
    children: <Widget>[
      LessonP(
        'Turns are not all the same length. A device far from the access '
        'point sends slowly, so it takes longer to say the same thing. Turn '
        'on {{Make device A slow}}: with 4 devices, A still gets 1/4 of the '
        'turns, but its turns use 57% of the time, and everyone else gets '
        'less.',
      ),
      LessonP(
        'Some access points offer **airtime fairness**, which shares out '
        'time instead of turns. The Airtime Fairness simulator shows how it '
        'works.',
      ),
      LessonToolLinkView('airtime-fairness'),
    ],
  ),

  // ── 6. What to do ────────────────────────────────────────────────────────
  LessonSection(
    number: '6',
    title: 'What you can do about it',
    children: <Widget>[
      LessonNumbered(<String>[
        'Plug in what you can. A TV, a game console or a desktop on a cable '
            'takes no turns on Wi-Fi.',
        'Put access points that can hear each other on different channels, '
            'so each has its own waiting line.',
        'Help the slowest devices. Move them closer to an access point, or '
            'add one near them, so their turns are shorter.',
      ]),
    ],
  ),

  // ── 7. Next ──────────────────────────────────────────────────────────────
  LessonSection(
    number: '7',
    title: 'Next',
    children: <Widget>[
      LessonP(
        'Channel Planner puts access points on a floor and shows which ones '
        'share a channel. Medium Access Simulator shows how devices decide '
        'whose turn it is, slot by slot.',
      ),
      LessonToolLinkView('channel-planner'),
      LessonToolLinkView('medium-access-simulator'),
    ],
  ),

  // ── Sources ──────────────────────────────────────────────────────────────
  LessonSection(
    number: '→',
    spokenNumber: 'Sources',
    title: 'Where these facts come from',
    children: <Widget>[
      LessonP(
        'Read on 29 September 2026. The even split and the slow device, 4 '
        'times slower, are teaching choices, not numbers from the standard.',
        small: true,
      ),
      LessonSources(<String>[
        'IEEE Std 802.11-2024 (IEEE): 10.2.2, DCF, page 1875, a device '
            'senses the medium before it transmits and waits while it is '
            'busy; 10.2.3.2, EDCA, page 1876, the same rule with priorities; '
            '10.3.2.1, the carrier sense mechanism, page 1885; 10.23.2, the '
            'full EDCA procedure.',
      ]),
    ],
  ),
];

/// A titled card, stacked on every width.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return LessonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          LessonRich(body, style: lessonBody(context)),
        ],
      ),
    );
  }
}
