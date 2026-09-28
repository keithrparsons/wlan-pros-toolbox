// Why the TV and the Printer Vanish on Guest Wi-Fi. A Wi-Fi Classroom Guided
// Lesson on the pattern of Find My, Explained and Antenna Fundamentals:
// numbered landmark sections, cards and callouts, a sources section and the
// About this tool footer. It adds the one interactive control Pax named in the
// research brief (myPKA Deliverables/2026-09-27-classroom-candidates/
// RESEARCH-BRIEF.md §3, candidate 11): same network / guest network / client
// isolation, with the discovery question shown stopping at the boundary. The
// model is lib/services/wifi_lab/guest_discovery_model.dart; the stage and
// controls are guest_discovery_stage.dart and guest_discovery_controls.dart.
//
// CLEAN ROOM: the copy rests on RFC 6762 (Multicast DNS), read 2026-09-27.
// Larry's brief: no product names in the UI ("the TV", "the printer",
// "screen casting"), sources kept to the RFC, and the mDNS gateway or
// reflector named only generically, with no vendor.
//
// States (SOP-007 §5): no network or async data; the copy and the model are
// compiled in, so the always-rendered state is success. The interactive
// states are in the controls and the stage.
//
// THEME: every color comes from `context.colors`.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark;
// the walk-through's step heading is a live region.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/guest_discovery_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import 'guest_discovery_controls.dart';
import 'guest_discovery_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kGuestDiscoveryToolId = 'guest-discovery';

/// The screen and catalog title.
const String kGuestDiscoveryTitle =
    'Why the TV and the Printer Vanish on Guest Wi-Fi';

class GuestDiscoveryScreen extends StatelessWidget {
  const GuestDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kGuestDiscoveryTitle),
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
                ToolHelpFooter(toolId: kGuestDiscoveryToolId),
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
        'Your phone finds the TV for screen casting, or the printer, by '
        'asking out loud: who here can show my screen? Is there a printer '
        'here? Only devices on the **same network segment** hear that '
        'question.',
      ),
      _P(
        'A guest network is a separate segment. On it, the question never '
        'reaches the TV or the printer, so they never answer, and the phone '
        'shows nothing. The phone still reaches the internet, the TV still '
        'works, and the Wi-Fi is not broken.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            '**DNS**, the Domain Name System, turns names into addresses. '
            '**Multicast DNS**, or mDNS, is the version devices use to find '
            'each other with no server: one question, sent to every device '
            'on the segment at once. A **network segment** (RFC 6762 calls it '
            'the local link) is the set of devices that hear each '
            "other's local traffic directly. A **VLAN**, a virtual local area "
            'network, is one way to split a network into separate segments. '
            '**Client isolation** is an access point setting that stops it '
            'passing traffic from one wireless device to another. An '
            '**RFC**, a Request for Comments, is a published internet '
            'standard.',
      ),
    ],
  ),

  // ── 2. Step through it ───────────────────────────────────────────────────
  _Section(
    number: '2',
    title: 'Step through it',
    children: <Widget>[
      _P(
        'Pick where the phone is, then press Step to send its question and '
        'watch where it goes. Switch at any step to compare.',
      ),
      _Walkthrough(),
      _P(
        'A simplified picture: one access point, one router, one TV and one '
        'printer, all on Wi-Fi.',
        small: true,
      ),
    ],
  ),

  // ── 3. Why the question stays local ──────────────────────────────────────
  _Section(
    number: '3',
    title: 'Why the question stays local',
    children: <Widget>[
      _P(
        'The phone sends its question to one special address, '
        '`224.0.0.251` (or `FF02::FB` for IPv6), on UDP port `5353`. RFC '
        '6762 defines that address as **link-local**: the question is meant '
        'for the local segment and nowhere else.',
      ),
      _P(
        'The standard holds the answers to the same rule. Names ending in '
        '`.local` mean something only on the segment where they started, '
        'and a phone accepts an answer only if it comes from its own segment '
        '(RFC 6762).',
      ),
    ],
  ),

  // ── 4. Guest network or client isolation ─────────────────────────────────
  _Section(
    number: '4',
    title: 'Two ways a network keeps devices apart',
    children: <Widget>[
      _Cards(<_CardData>[
        _CardData(
          'Guest network',
          'A separate segment, for example its own VLAN. The question travels to '
              'every device on the guest network and stops at the router '
              'between the two networks. The TV and the printer on the main '
              'network never hear it.',
        ),
        _CardData(
          'Client isolation',
          'One network and one segment, but the access point will not pass '
              'traffic between wireless devices. The phone and the TV can '
              'sit on the same network and still not see each other.',
        ),
      ]),
      _Callout(
        title: 'Separation is what the guest network is for',
        body:
            'A guest network keeps visitors away from the computers, cameras '
            'and printers on your main network. Hiding the TV and the '
            'printer is part of that job.',
      ),
      _P(
        'Exactly what client isolation blocks is set differently from one '
        'product to the next.',
        small: true,
      ),
    ],
  ),

  // ── 5. What to do ────────────────────────────────────────────────────────
  _Section(
    number: '5',
    title: 'What to do about it',
    children: <Widget>[
      _Steps(<String>[
        'If you are allowed to, join the same network as the TV or the '
            'printer.',
        'If the host wants guests to cast, the TV can join the guest '
            'network instead.',
        'If client isolation is on, the phone and the TV cannot see each '
            'other even on one network. Only the network owner can change '
            'that.',
        'Larger networks can run an **mDNS gateway**, also called a '
            '**reflector**. It repeats discovery questions and answers '
            'between segments, under rules the administrator sets.',
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
        'Read on 27 September 2026. How each kind of device names and shows '
        'what it finds is left out.',
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
  DiscoveryNetwork _mode = DiscoveryNetwork.guest;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    const List<DiscoveryStage> stages = DiscoveryStage.values;
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
          GuestDiscoveryControls(
            mode: _mode,
            onMode: (DiscoveryNetwork m) => setState(() => _mode = m),
            atStart: _index == 0,
            atEnd: _index == stages.length - 1,
            onBack: () => setState(() => _index--),
            onStep: () => setState(() => _index++),
            onReset: () => setState(() => _index = 0),
          ),
          const SizedBox(height: AppSpacing.md),
          GuestDiscoveryStage(
            scenario: discoveryScenario(_mode),
            stage: stages[_index],
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
          'Why the TV and the printer disappear from your phone on a guest '
          'network, when nothing is broken.',
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
    'RFC 6762, Multicast DNS (Internet Engineering Task Force, IETF, '
        'February 2013): the link-local addresses and port (sections 3 and '
        '5) and the local-link check on answers (section 11). '
        'rfc-editor.org/rfc/rfc6762',
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
