// Connected, No Internet: Captive Portals. A Wi-Fi Classroom Guided Lesson.
// A read-along teaching screen on the pattern of Find My, Explained
// (find_my_explained_screen.dart) and Antenna Fundamentals: numbered landmark
// sections, cards and callouts, a sources section and the About this tool
// footer. It adds the one interactive control Pax named in the research brief
// (myPKA Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md §3,
// candidate 2): a step-through of the device's check after association, with
// a switch between a network that announces its portal and one that
// intercepts traffic. The walk-through's model is
// lib/services/wifi_lab/captive_portal_model.dart; its stage and controls are
// captive_portal_stage.dart and captive_portal_controls.dart.
//
// CLEAN ROOM: the copy rests only on Apple Developer's "How to modernize your
// captive network" (2020-06-22) and RFCs 8910, 8908 and 8952, all read
// 2026-09-27. Pax's guard: Android's probe is unsourced, so the lesson teaches
// the generic probe and names no operating system's behavior.
//
// Inline markup in the copy: **bold**, __italic__, and `code` (the app's mono
// style), the same as the Find My lesson.
//
// States (SOP-007 §5): no network or async data; the copy and the model are
// compiled in, so the always-rendered state is success. The interactive
// states (disabled Back on step 1, disabled Step on step 5, the two switch
// positions) are in the controls.
//
// THEME: every color comes from `context.colors`.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark;
// the walk-through's step heading is a live region.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/captive_portal_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import 'captive_portal_controls.dart';
import 'captive_portal_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kCaptivePortalToolId = 'captive-portal';

/// The screen and catalog title.
const String kCaptivePortalTitle = 'Connected, No Internet: Captive Portals';

class CaptivePortalScreen extends StatelessWidget {
  const CaptivePortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kCaptivePortalTitle), toolbarHeight: 64),
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
                ToolHelpFooter(toolId: kCaptivePortalToolId),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The lesson body, section by section.
const List<Widget> _sections = <Widget>[
  // ── 1. The short answer ──────────────────────────────────────────────────
  _Section(
    number: '1',
    title: 'The short answer',
    children: <Widget>[
      _P(
        'Connecting to Wi-Fi and reaching the internet are two separate '
        'steps. The first is **association**: your device and the access '
        'point agree to talk, and the Wi-Fi icon shows full bars. The second '
        'is getting through the network to the rest of the internet.',
      ),
      _P(
        'A hotel, airport or airplane network often stops you between the '
        'two. It lets you reach one thing, its own sign-in page, and holds '
        'everything else until you finish it. That is a **captive network**, '
        'and its sign-in page is the **captive portal**.',
      ),
      _Callout(
        title: 'What the bars measure',
        body:
            'The Wi-Fi bars show how well your device hears the access point. '
            'They say nothing about whether the network will pass your '
            'traffic on to the internet.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            '**DHCP**, the Dynamic Host Configuration Protocol, is how a '
            'network hands your device an IP (Internet Protocol) address. A '
            '**probe** is a small test request your device sends to find out '
            'whether it can reach the internet. An **API**, an '
            'application programming interface, is an address a device can '
            'ask questions of and get machine-readable answers. **HTTPS** is '
            'the encrypted form of the Hypertext Transfer Protocol, the '
            "web's protocol. An **RFC**, a Request for Comments, is a "
            'published internet standard.',
      ),
    ],
  ),

  // ── 2. Step through it ───────────────────────────────────────────────────
  _Section(
    number: '2',
    title: 'Step through it',
    children: <Widget>[
      _P(
        'Press Step to walk a device onto a captive network, from association '
        'to online. Flip the switch at any step to see the other way a '
        'network can ask you to sign in. Both ways take the same five steps.',
      ),
      _Walkthrough(),
      _P(
        'An illustrative sequence. The exact requests, addresses and timing '
        'differ from one device to the next and are left out.',
        small: true,
      ),
    ],
  ),

  // ── 3. Two ways to say sign in first ─────────────────────────────────────
  _Section(
    number: '3',
    title: 'Two ways to say sign in first',
    children: <Widget>[
      _Cards(<_CardData>[
        _CardData(
          'Announces its portal',
          'The network adds a note to the reply that hands out your address: '
              'DHCP option 114, defined in RFC 8910. The note is the secure '
              "address of the network's Captive Portal API. Your device asks "
              'that API whether it is captive and where the sign-in page is, '
              'and gets a straight answer (RFC 8908).',
        ),
        _CardData(
          'Intercepts traffic',
          'The network says nothing. Your device sends a probe, a request '
              'whose answer it already knows. The network intercepts it and '
              'sends back its sign-in page instead. The wrong answer is how '
              'the device learns it is captive.',
        ),
      ]),
      _P(
        'To the person holding the device, the two look the same: a sign-in '
        'sheet opens (Apple Developer, 2020). The difference shows up later. '
        'When a session on an intercepting network runs out, the '
        'interception can get in the way of the pages you open, and a '
        'browser may load the wrong page or show a security warning (Apple '
        'Developer, 2020). An announcing network does not have to intercept '
        'anything to tell the device.',
      ),
      _Callout(
        title: 'Why networks still intercept',
        body:
            'RFC 8910 calls the announcement the preferred way to detect a '
            'captive portal. It also says that, for the foreseeable future, '
            'networks will still intercept for older devices, and devices '
            'will still send probes. So a network that announces its portal '
            'still has to intercept for devices that do not read the '
            'announcement.',
      ),
      _P(
        'The API can also report how much time is left in a session (RFC '
        '8908).',
        small: true,
      ),
    ],
  ),

  // ── 4. Why Wi-Fi Calling waits ───────────────────────────────────────────
  _Section(
    number: '4',
    title: 'Why Wi-Fi Calling waits for the sign-in',
    children: <Widget>[
      _P(
        'Wi-Fi Calling carries your calls over the internet, through a '
        'private tunnel from your phone to your phone company. On a captive '
        'network that tunnel is held back like everything else. A phone can '
        'show full Wi-Fi bars in a hotel room and still not ring over Wi-Fi.',
      ),
      _P(
        '**Finish the sign-in page first.** Only then can the tunnel '
        'connect. In the walk-through, the Wi-Fi Calling line changes at the '
        'sign-in step, in both modes.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'If calls still fail after you sign in',
        body:
            'Some networks also block the tunnel itself, and a crowded '
            'network can break up calls. Ask the front desk or IT, or use '
            'the cell network.',
      ),
    ],
  ),

  // ── 5. On the road ───────────────────────────────────────────────────────
  _Section(
    number: '5',
    title: 'In a hotel, an airport or on a plane',
    children: <Widget>[
      _Steps(<String>[
        'Pick the network and give the sign-in sheet a moment to open by '
            'itself.',
        'If it does not open, open a web browser and look for the '
            "network's sign-in page.",
        'Finish the page: accept the terms, or enter the room number or '
            'access code.',
        'Wait for the Wi-Fi to show as connected before you expect email, '
            'messages or a Wi-Fi call.',
        'If the internet stops partway through a stay, the session may have '
            'run out. Sign in again.',
      ]),
    ],
  ),

  // ── Sources ──────────────────────────────────────────────────────────────
  _Section(
    number: '→',
    spokenNumber: 'Sources',
    title: 'Where these facts come from',
    children: <Widget>[
      _P(
        'Read on 27 September 2026. The lesson teaches the generic probe '
        'every device makes. How often each kind of device probes, and which '
        'test address it asks, is left out.',
        small: true,
      ),
      _Sources(),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// The walk-through: owns the mode and the step; the stage draws, the controls
// drive.
// ─────────────────────────────────────────────────────────────────────────────

class _Walkthrough extends StatefulWidget {
  const _Walkthrough();

  @override
  State<_Walkthrough> createState() => _WalkthroughState();
}

class _WalkthroughState extends State<_Walkthrough> {
  CaptiveMode _mode = CaptiveMode.announced;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final List<CaptiveStep> steps = captiveSteps(_mode);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CaptivePortalControls(
            mode: _mode,
            onMode: (CaptiveMode m) => setState(() => _mode = m),
            atStart: _index == 0,
            atEnd: _index == steps.length - 1,
            onBack: () => setState(() => _index--),
            onStep: () => setState(() => _index++),
            onReset: () => setState(() => _index = 0),
          ),
          const SizedBox(height: AppSpacing.md),
          CaptivePortalStage(
            step: steps[_index],
            index: _index,
            count: steps.length,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The hero.
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
        Text(
          'A plain-English lesson',
          style: (t.labelMedium ?? const TextStyle()).copyWith(
            color: colors.textAccent,
            fontFamily: 'DM Mono',
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Why a hotel, airport or airplane network can show full bars and '
          'still not reach the internet, and how your device finds out it has '
          'to sign in.',
          style: (t.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sources.
// ─────────────────────────────────────────────────────────────────────────────

class _Sources extends StatelessWidget {
  const _Sources();

  static const List<String> _items = <String>[
    'Apple Developer, How to modernize your captive network, 22 June 2020: '
        'developer.apple.com/news/?id=q78sq5rv',
    'RFC 8910, Captive-Portal Identification in DHCP and Router '
        'Advertisements (Internet Engineering Task Force, IETF, September '
        '2020). It replaced RFC 7710, which '
        'used DHCP option 160.',
    'RFC 8908, Captive Portal API (IETF, September 2020)',
    'RFC 8952, Captive Portal Architecture (IETF, November 2020)',
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
// Inline markup: **bold**, __italic__, `code` (same as Find My, Explained).
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _markup = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`(.+?)`');

/// Parses the copy's inline markup into spans over [base]. Mono runs use the
/// app's inline-code face (DM Mono, GL-003 §8.5) on the recessed input fill,
/// as in the Find My lesson.
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
  /// read well ("Sources" rather than an arrow).
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

/// A body paragraph. [small] is the small-type register (notes
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

enum _Tone { accent, warning }

/// A titled callout with a filled rail (lime, or §8.13 warning). The title
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
    final Color rail = tone == _Tone.warning
        ? colors.statusWarning
        : colors.primary;
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
