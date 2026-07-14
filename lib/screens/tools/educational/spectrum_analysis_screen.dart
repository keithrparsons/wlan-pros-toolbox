// Spectrum Analysis — a read-along teaching / reference MODULE for the
// Educational Resources directory. NOT a live tool: a phone's Wi-Fi chipset is
// a NIC, not a wideband RF capture radio, so the app cannot perform spectrum
// analysis. This module teaches what a spectrum analyzer is, how to read it, and
// how to fingerprint and mitigate interference. The honest "your phone cannot do
// this" scope note leads the module (screen 1) so the teaching framing is never
// mistaken for a working analyzer.
//
// SOURCE: Pax's research brief
// (Deliverables/2026-06-28-spectrum-analysis-toolbox/research-brief.md), with
// Keith's domain corrections already folded in. The teaching prose here is
// CONDENSED by Felix from that brief (conclusion-first, GL-004 voice) and is a
// candidate for a Penn SOP-020 voice polish before public launch.
//
// STRUCTURE (the brief's "Recommended in-app structure"): one hub screen with
// eight navigable topic screens —
//   1. Why a spectrum analyzer?   2. How it works   3. The knobs
//   4. The three views            5. Fingerprinting (the signature gallery)
//   6. Comparing captures         7. The tools      8. Mitigation
// The hub is the single catalog tile (id `spectrum-analysis`, an in-app
// reference in Educational Resources, alongside Antenna Fundamentals); the eight
// topic screens are pushed via MaterialPageRoute, so the module adds exactly one
// catalog tile, one named route, and one help entry. The hub carries the §8.16.1
// ToolHelpFooter for the whole module.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw hex / px — so the module renders in both dark (§8) and
// light (§8.20). The nine signature cards are DARK-BAKED rasters (analyzer
// rainbow in the data area, WLAN Pros green chrome around it, Vera SOP-009 PASS
// 2026-06-28); like the Modulation cards they mount on an ALWAYS-DARK surface in
// both themes via DarkRasterDiagramCard, so they never read inverted on a light
// canvas, and because their text is BAKED into the raster the §8.6.1 tofu-glyph
// rule does not apply (Vera LOW note 2).
//
// ACCESSIBILITY: each topic is a Semantics(header: true) landmark; the signature
// rasters are decorative (DarkRasterDiagramCard excludes them), and each card's
// fingerprint CAPTION is real text below the card, so a screen-reader user hears
// the teaching content (Vera LOW note 1 — alt-text-on-embed, resolved by wiring
// the fingerprint caption as the text equivalent). The hub topic cards are
// labeled buttons with the §8.3 touch target.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kSpectrumAnalysisToolId = 'spectrum-analysis';

/// The existing Wi-Fi Glossary route (AppRouter.wifiGlossary). Held as a literal
/// here so screen 3 ("The knobs") can cross-link the glossary in one tap without
/// the screen importing the router (which would invert the router→screen import
/// direction). The route id `wifi-glossary` is permanent.
const String _kGlossaryRoute = '/tools/wifi-glossary';

/// True aspect ratio (width / height) of the nine signature cards (1920 × 1964).
const double _kSignatureAspect = 1920 / 1964;

// ─────────────────────────────────────────────────────────────────────────────
// Hub screen — the single catalog tile. Intro + the honest scope note + eight
// navigable topic cards + the module help footer.
// ─────────────────────────────────────────────────────────────────────────────

class SpectrumAnalysisScreen extends StatelessWidget {
  const SpectrumAnalysisScreen({super.key});

  /// The eight topics, in the brief's order. Each row carries its number, title,
  /// one-line teaser, and the builder for its teaching screen.
  static final List<_Topic> _topics = <_Topic>[
    _Topic(
      number: 1,
      title: 'Why a spectrum analyzer?',
      teaser: 'It sees RF energy a Wi-Fi adapter is blind to.',
      builder: (_) => const _WhyScreen(),
    ),
    _Topic(
      number: 2,
      title: 'How it works',
      teaser: 'Swept versus real-time, and what the FFT does.',
      builder: (_) => const _HowItWorksScreen(),
    ),
    _Topic(
      number: 3,
      title: 'The knobs',
      teaser: 'Span, RBW, VBW, reference level, dBm, detectors.',
      builder: (_) => const _KnobsScreen(),
    ),
    _Topic(
      number: 4,
      title: 'The three views',
      teaser: 'Live FFT, waterfall, and density / duty cycle.',
      builder: (_) => const _ThreeViewsScreen(),
    ),
    _Topic(
      number: 5,
      title: 'Fingerprinting interferers',
      teaser: 'Nine signatures, one waterfall shape each.',
      builder: (_) => const _FingerprintingScreen(),
    ),
    _Topic(
      number: 6,
      title: 'Comparing captures',
      teaser: 'Max-hold, averaging, baselines, before and after.',
      builder: (_) => const _ComparingScreen(),
    ),
    _Topic(
      number: 7,
      title: 'The tools',
      teaser: 'Current leaders, heritage gear, and budget options.',
      builder: (_) => const _ToolsScreen(),
    ),
    _Topic(
      number: 8,
      title: 'Mitigation',
      teaser: 'Remove, relocate, shield, plan channels, change band.',
      builder: (_) => const _MitigationScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spectrum Analysis'),
        toolbarHeight: 64,
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
                  maxWidth: AppSpacing.contentMaxWidth,
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  children: <Widget>[
                    const _Lead(
                      'A spectrum analyzer measures raw RF energy across a band, '
                      'no matter what protocol made it. That is exactly what a '
                      'Wi-Fi adapter cannot do, and it is why spectrum analysis '
                      'finds the interference a Wi-Fi scanner misses.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _ScopeNote(),
                    const SizedBox(height: AppSpacing.md),
                    for (int i = 0; i < _topics.length; i++) ...<Widget>[
                      _TopicCard(topic: _topics[i]),
                      if (i < _topics.length - 1)
                        const SizedBox(height: AppSpacing.xs),
                    ],
                    ToolHelpFooter(toolId: kSpectrumAnalysisToolId),
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

/// One hub topic: number, title, teaser, and the builder for its screen.
@immutable
class _Topic {
  const _Topic({
    required this.number,
    required this.title,
    required this.teaser,
    required this.builder,
  });

  final int number;
  final String title;
  final String teaser;
  final WidgetBuilder builder;
}

/// A tappable hub row: a lime number badge, the title + teaser, and a chevron.
/// A labeled `Semantics(button: true)` with the §8.3 minimum touch target.
class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final _Topic topic;

  void _open(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: topic.builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${topic.number}. ${topic.title}. ${topic.teaser}',
      excludeSemantics: true,
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _open(context),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: colors.border, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    '${topic.number}',
                    style: (text.labelLarge ?? const TextStyle()).copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        topic.title,
                        style: (text.titleSmall ?? const TextStyle()).copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topic.teaser,
                        style: (text.bodySmall ?? const TextStyle()).copyWith(
                          color: colors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  color: colors.textTertiary,
                  size: AppSpacing.md,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The honest scope note that leads the module: a phone cannot capture RF, so
/// this is teaching content, not a working analyzer. Neutral info treatment
/// (icon + text, no status color — §8.13 reserves the status palette for
/// computed verdicts), so it never reads as a warning or a result.
class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    const String body =
        'Your phone cannot run a spectrum analyzer. Its Wi-Fi chipset is a NIC '
        'that decodes 802.11 frames; spectrum analysis needs dedicated wideband '
        'RF capture hardware the phone does not expose. This module is teaching '
        'content, not a live tool.';
    return Semantics(
      label: 'Scope note. $body',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, size: 20, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                body,
                style: (text.bodySmall ?? const TextStyle()).copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
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
// Shared teaching scaffold + content primitives, reused by all eight screens.
// ─────────────────────────────────────────────────────────────────────────────

/// The shared reading scaffold for a topic screen: an AppBar + a width-capped
/// scroll column. Every topic screen passes its title and its content children.
class _TeachingScreen extends StatelessWidget {
  const _TeachingScreen({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), toolbarHeight: 64),
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
                  maxWidth: AppSpacing.contentMaxWidth,
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  children: children,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The conclusion-first lead claim of a screen — a lime-railed card (the §8.20.2
/// filled accent, valid in both themes; reinforced by the text, never
/// color-only).
class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: text,
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
              Container(
                width: colors.isLight ? 4 : 3,
                color: colors.primary,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    text,
                    style: (t.titleSmall ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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

/// A landmark section header.
class _H extends StatelessWidget {
  const _H(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Text(
        title,
        style: (t.titleMedium ?? const TextStyle()).copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A body paragraph (§8.2 body register).
class _P extends StatelessWidget {
  const _P(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textPrimary,
        height: 1.5,
      ),
    );
  }
}

/// A bullet with an optional bold lead-in run and the rest of the sentence.
@immutable
class _Bullet {
  const _Bullet({this.lead, required this.rest});

  final String? lead;
  final String rest;
}

/// A bulleted list with an optional bold lead-in run per item.
class _Bullets extends StatelessWidget {
  const _Bullets(this.bullets, {this.ordered = false});

  final List<_Bullet> bullets;

  /// When true, render 1./2./3. markers (the mitigation ladder) instead of dots.
  final bool ordered;

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
                  ordered ? '${i + 1}.  ' : '•  ',
                  style: base.copyWith(
                    color: colors.textAccent,
                    fontWeight: ordered ? FontWeight.w700 : FontWeight.w400,
                  ),
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

/// A recessed editorial note (surface-2 card) for an honest caveat or a teaching
/// aside. Neutral, never status-colored.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

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
      child: Text(
        text,
        style: (t.bodySmall ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
          fontStyle: FontStyle.italic,
          height: 1.45,
        ),
      ),
    );
  }
}

/// A simple titled reference card (surface-1) — title + body, used by "The
/// tools" for each instrument.
class _RefCard extends StatelessWidget {
  const _RefCard({required this.title, required this.body, this.chip});

  final String title;
  final String body;

  /// An optional band/role chip rendered beside the title (e.g. "2.4 / 5 / 6 GHz").
  final String? chip;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: (t.titleSmall ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (chip != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _BandChip(chip!),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral outlined pill carrying a short band/role label. Decorative chrome,
/// always paired with text, never color-only.
class _BandChip extends StatelessWidget {
  const _BandChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: (t.labelSmall ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// The screen-3 cross-link into the existing Wi-Fi Glossary, so a knob term
/// resolves in one tap. A labeled button row that pushes the glossary route.
class _GlossaryLink extends StatelessWidget {
  const _GlossaryLink();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Open the Wi-Fi Glossary',
      excludeSemantics: true,
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context).pushNamed(_kGlossaryRoute),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: colors.border, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(Icons.menu_book_outlined,
                    size: 20, color: colors.textAccent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'These terms also live in the Wi-Fi Glossary. Tap to open it.',
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right,
                    color: colors.textTertiary, size: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small spacing helper to keep the topic screens readable.
const SizedBox _gapSm = SizedBox(height: AppSpacing.sm);
const SizedBox _gapMd = SizedBox(height: AppSpacing.md);

// ─────────────────────────────────────────────────────────────────────────────
// 1. Why a spectrum analyzer?
// ─────────────────────────────────────────────────────────────────────────────

class _WhyScreen extends StatelessWidget {
  const _WhyScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'Why a spectrum analyzer?',
      children: const <Widget>[
        _Lead(
          'A spectrum analyzer reveals the non-Wi-Fi interferers a Wi-Fi adapter '
          'is structurally blind to. That difference is the whole reason '
          'spectrum analysis exists in Wi-Fi work.',
        ),
        _gapSm,
        _ScopeNote(),
        _gapMd,
        _H('Two different instruments'),
        _gapSm,
        _P(
          'A Wi-Fi NIC is a protocol decoder. It tunes to an 802.11 channel, '
          'demodulates the frames it can, and reports what it decodes: SSIDs, '
          'BSSIDs, channels in use, data rates, and retries. It only perceives '
          'energy it can interpret as 802.11. Anything else is lumped into a '
          'vague noise bucket, and many adapters do not report it at all.',
        ),
        _gapSm,
        _P(
          'A spectrum analyzer measures raw RF power versus frequency, no matter '
          'the protocol or modulation. It does not care whether the energy is '
          'Wi-Fi, Bluetooth, a microwave oven, or a video camera. It shows the '
          'energy as it exists in the air.',
        ),
        _gapMd,
        _H('The load-bearing point'),
        _gapSm,
        _P(
          'When users report poor performance but a Wi-Fi scanner shows a clean '
          'channel, the missing piece is almost always a non-802.11 energy '
          'source that only a spectrum analyzer can see.',
        ),
        _gapSm,
        _P(
          'A subtler distinction is worth keeping. A NIC’s channel '
          'utilization tells you the airtime is busy. A spectrum analyzer, and '
          'its density / duty-cycle view, tells you how busy a given frequency '
          'is and what the energy looks like, which is what lets you identify '
          'the source.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. How it works
// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorksScreen extends StatelessWidget {
  const _HowItWorksScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'How it works',
      children: const <Widget>[
        _Lead(
          'There are two architectures. The real-time one is what matters for '
          'Wi-Fi, because Wi-Fi interference is bursty and frequency-hopping.',
        ),
        _gapMd,
        _H('Swept-tuned (the classic)'),
        _gapSm,
        _P(
          'A local oscillator sweeps across the span while a narrow filter '
          'passes one slice of spectrum at a time to a detector, building the '
          'trace point by point as it tunes across the band. It is accurate for '
          'stable signals, but because it looks at only one slice at any '
          'instant, it can miss transient or bursty events that happen while the '
          'sweep is elsewhere.',
        ),
        _gapMd,
        _H('Real-time / FFT-based (RTSA)'),
        _gapSm,
        _P(
          'The instrument digitizes a block of the band with a wideband '
          'converter and runs repetitive FFTs continuously, producing spectra '
          'with no gaps. It catches the events a swept analyzer misses. The '
          'figure of merit is probability of intercept: the shortest signal it '
          'is guaranteed to detect at full amplitude.',
        ),
        _gapSm,
        _Note(
          'A swept analyzer is a flashlight scanning a dark field one spot at a '
          'time. An RTSA floods the whole field at once. Hopping and bursty '
          'interferers hide from the flashlight.',
        ),
        _gapMd,
        _H('What the FFT actually does'),
        _gapSm,
        _P(
          'The FFT takes a block of time-domain samples (amplitude versus time) '
          'and converts it into a spectrum (amplitude versus frequency). The '
          'trade to remember: finer frequency resolution needs a longer time '
          'record. You cannot have arbitrarily fine frequency resolution and '
          'arbitrarily fine time resolution at once. That is physics, not a '
          'product limitation.',
        ),
        _gapSm,
        _P(
          'Before each transform the analyzer multiplies the block by a window '
          'function to reduce spectral leakage, the smearing of energy from one '
          'frequency into neighboring FFT bins because the captured block is '
          'finite.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. The knobs (with the glossary cross-link)
// ─────────────────────────────────────────────────────────────────────────────

class _KnobsScreen extends StatelessWidget {
  const _KnobsScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'The knobs',
      children: const <Widget>[
        _Lead(
          'A handful of controls decide what the trace shows. Set them wrong and '
          'you hide the very thing you are hunting.',
        ),
        _gapMd,
        _Bullets(<_Bullet>[
          _Bullet(
            lead: 'Span. ',
            rest: 'The frequency range displayed, between a start and stop. Wide '
                'span gives a whole-band overview; narrow span zooms in on one '
                'signal.',
          ),
          _Bullet(
            lead: 'RBW (resolution bandwidth). ',
            rest: 'The narrowest frequency difference the analyzer can separate. '
                'A narrower RBW separates closely spaced signals and lowers the '
                'noise floor, revealing weaker signals, but it slows the sweep.',
          ),
          _Bullet(
            lead: 'VBW (video bandwidth). ',
            rest: 'A post-detection filter that smooths the displayed trace so a '
                'noisy signal is easier to read. It changes only the displayed '
                'trace, not the underlying signal.',
          ),
          _Bullet(
            lead: 'Reference level. ',
            rest: 'The amplitude at the top of the display. It sets the '
                'analyzer’s gain and attenuation so strong signals are not '
                'clipped and weak ones are not buried.',
          ),
          _Bullet(
            lead: 'Amplitude scale (dBm). ',
            rest: 'The vertical axis, a logarithmic power scale in decibels '
                'relative to one milliwatt. More negative means weaker.',
          ),
          _Bullet(
            lead: 'Detectors. ',
            rest: 'How each displayed point is derived from the many samples '
                'behind it. Peak catches bursts; average or RMS gives true power '
                'for noise-like signals; sample takes one instantaneous value. '
                'The detector changes what the trace means.',
          ),
          _Bullet(
            lead: 'Max-hold and averaging. ',
            rest: 'Trace-processing modes. Max-hold keeps the highest value ever '
                'seen at each frequency; averaging smooths toward the mean. More '
                'on these under Comparing captures.',
          ),
        ]),
        _gapMd,
        _GlossaryLink(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. The three views
// ─────────────────────────────────────────────────────────────────────────────

class _ThreeViewsScreen extends StatelessWidget {
  const _ThreeViewsScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'The three views',
      children: const <Widget>[
        _Lead(
          'Three views answer three different questions. A real diagnosis uses '
          'all three: spot it live, fingerprint it in the waterfall, quantify it '
          'in density.',
        ),
        _gapMd,
        _H('Live FFT: power versus frequency'),
        _gapSm,
        _P(
          'X is frequency, Y is amplitude in dBm, one live trace. Tall peaks are '
          'strong signals; the flat bottom is the noise floor. The width of a '
          'feature tells you its bandwidth, its position tells you its center '
          'frequency. This answers what is transmitting, where, and how strong, '
          'right now.',
        ),
        _gapMd,
        _H('Waterfall / spectrogram: frequency, time, color'),
        _gapSm,
        _P(
          'One axis is frequency, the other is time (usually scrolling), and '
          'color encodes amplitude. The color-to-amplitude mapping is set by the '
          'tool’s palette and scale, so always read the legend rather than '
          'assuming. A steady horizontal band is a continuous transmitter on a '
          'fixed frequency; repeating vertical streaks are periodic bursts; a '
          'signal that wanders across frequencies over time is frequency '
          'hopping. This is the view that exposes the pattern, which is how you '
          'fingerprint an interferer.',
        ),
        _gapMd,
        _H('Density / duty cycle: how often a frequency is occupied'),
        _gapSm,
        _P(
          'X is frequency, Y is amplitude, and color or brightness encodes how '
          'often each point has been occupied over the accumulation window. A '
          'frequency lit brightly across a long window is occupied most of the '
          'time, a high duty cycle and a serious problem for Wi-Fi, which needs '
          'the channel clear to talk. A faint smear is occasional. This is how '
          'you prioritize: a 90 percent duty interferer matters far more than a '
          '2 percent one even when both peak at the same amplitude.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Fingerprinting interferers — the signature gallery
// ─────────────────────────────────────────────────────────────────────────────

/// One signature card: a baked dark-navy raster (analyzer rainbow + WLAN Pros
/// green chrome, Vera SOP-009 PASS) plus its name, band, and the fingerprint
/// caption that doubles as the screen-reader text equivalent.
@immutable
class _Signature {
  const _Signature({
    required this.slug,
    required this.name,
    required this.band,
    required this.fingerprint,
  });

  final String slug;
  final String name;
  final String band;
  final String fingerprint;

  String get assetPath =>
      'assets/tool-diagrams/spectrum-signatures/$slug.png';
}

const List<_Signature> _kSignatures = <_Signature>[
  _Signature(
    slug: 'microwave-oven',
    name: 'Microwave oven',
    band: '2.4 GHz',
    fingerprint:
        'A broad, wandering blob that climbs into the upper 2.4 GHz channels '
        '(worst around channel 9 to 11), pulsing on and off with the mains '
        'cycle. It is never centered on channel 6.',
  ),
  _Signature(
    slug: 'bluetooth-classic',
    name: 'Bluetooth Classic',
    band: '2.4 GHz',
    fingerprint:
        'A dense, fine speckle of thin 1 MHz hops scattered across the whole '
        'band every frame: 79 channels, hopping about 1,600 times per second, '
        'with no fixed home.',
  ),
  _Signature(
    slug: 'analog-video-camera',
    name: 'Analog video camera',
    band: '2.4 GHz',
    fingerprint:
        'Three adjacent continuous carriers on a fixed frequency, the video '
        'carrier flanked by its audio and color subcarriers. It is steady, '
        'never hops, and never stops.',
  ),
  _Signature(
    slug: 'ble',
    name: 'Bluetooth Low Energy (BLE)',
    band: '2.4 GHz',
    fingerprint:
        'Three strong, persistent pickets on the advertising channels 37, 38, '
        'and 39 (2402, 2426, and 2480 MHz), parked in the gaps around Wi-Fi 1, '
        '6, and 11, with faint data-hop speckle behind them.',
  ),
  _Signature(
    slug: 'baby-monitor',
    name: 'Baby monitor (analog)',
    band: '2.4 GHz',
    fingerprint:
        'Often a single continuous fixed carrier like an analog camera, but it '
        'varies by model: some hop, and many newer units are DECT at 1.9 GHz, '
        'which is harmless to Wi-Fi. Read the signature, do not assume.',
  ),
  _Signature(
    slug: 'drone-fpv-downlink',
    name: 'Drone / FPV downlink',
    band: '5 GHz / 5.8 GHz',
    fingerprint:
        'A wide, ragged, frequency-agile block up at 5.8 GHz that jogs over '
        'time. Analog FPV is a continuous carrier; digital systems spread a '
        'wider, adaptive OFDM block. Confidence is lower here and the shape is '
        'model-dependent.',
  ),
  _Signature(
    slug: 'zigbee-802-15-4',
    name: 'ZigBee / 802.15.4',
    band: '2.4 GHz',
    fingerprint:
        'A narrow (about 2 MHz) fixed picket, bursty and low duty cycle, '
        'sitting on a channel chosen to dodge Wi-Fi 1, 6, and 11. Its position '
        'is steady; it does not hop.',
  ),
  _Signature(
    slug: 'cordless-phone-24ghz',
    name: 'Analog cordless phone',
    band: '2.4 GHz',
    fingerprint:
        'A strong carrier that steps slowly across a few channels, leaving a '
        'break in the waterfall at each change. The 2.4 GHz analog kind '
        'interferes; DECT 6.0 at 1.9 GHz does not.',
  ),
  _Signature(
    slug: 'wireless-bridge',
    name: 'Continuous wireless bridge',
    band: '2.4 GHz',
    fingerprint:
        'A constant, wide (about 20 MHz) block at close to 100 percent duty '
        'cycle. It is among the most damaging interferers because it never '
        'yields the channel.',
  ),
];

class _FingerprintingScreen extends StatelessWidget {
  const _FingerprintingScreen();

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      const _Lead(
        'Every interferer has a shape. Learn the nine shapes below and the '
        'waterfall tells you the source. Tap any card to zoom in.',
      ),
      _gapSm,
      const _Note(
        'These are teaching diagrams: an illustrative live-FFT trace plus a '
        'waterfall and a dBm legend, drawn to the canonical signatures. They '
        'are not captures from your environment.',
      ),
      _gapMd,
    ];
    for (int i = 0; i < _kSignatures.length; i++) {
      children.add(_SignatureCard(signature: _kSignatures[i]));
      if (i < _kSignatures.length - 1) {
        children.add(_gapMd);
      }
    }
    return _TeachingScreen(
      title: 'Fingerprinting interferers',
      children: children,
    );
  }
}

/// A name + band header above the baked signature raster, with the fingerprint
/// caption wired as the card’s text equivalent (Vera LOW alt-text note).
class _SignatureCard extends StatelessWidget {
  const _SignatureCard({required this.signature});

  final _Signature signature;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  signature.name,
                  style: (t.titleSmall ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _BandChip(signature.band),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DarkRasterDiagramCard(
          assetPath: signature.assetPath,
          aspectRatio: _kSignatureAspect,
          semanticLabel: '${signature.name} spectrum signature',
          caption: signature.fingerprint,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Comparing captures
// ─────────────────────────────────────────────────────────────────────────────

class _ComparingScreen extends StatelessWidget {
  const _ComparingScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'Comparing captures',
      children: const <Widget>[
        _Lead(
          'Max-hold and averaging answer opposite questions: worst case versus '
          'typical. Compare captures the disciplined way and you can prove an '
          'interferer was the cause and that a fix worked.',
        ),
        _gapMd,
        _Bullets(<_Bullet>[
          _Bullet(
            lead: 'Max-hold. ',
            rest: 'The trace keeps the highest amplitude ever seen at each '
                'frequency. Run it for a while and every transient leaves a '
                'permanent peak, ideal for catching a hopping or bursty '
                'interferer the live trace shows for only an instant.',
          ),
          _Bullet(
            lead: 'Averaging. ',
            rest: 'Smooths toward the mean, pulling steady signals out of the '
                'noise and de-emphasizing rare spikes. Use it to characterize a '
                'continuous interferer’s true level.',
          ),
          _Bullet(
            lead: 'Overlays. ',
            rest: 'Show live, max-hold, and average at once to read '
                'instantaneous, worst case, and typical together.',
          ),
          _Bullet(
            lead: 'Before and after, with a baseline. ',
            rest: 'Record a baseline capture, make one change (remove a '
                'suspected source, change a channel, add an access point), then '
                'capture again and compare.',
          ),
        ]),
        _gapMd,
        _Note(
          'Keep span, RBW, reference level, and dwell identical between the two '
          'captures, or the comparison is invalid.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. The tools
// ─────────────────────────────────────────────────────────────────────────────

class _ToolsScreen extends StatelessWidget {
  const _ToolsScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'The tools',
      children: const <Widget>[
        _Lead(
          'Current leaders first, then the heritage tools a generation of WLAN '
          'pros learned spectrum on, then the budget option.',
        ),
        _gapMd,
        _H('Current leaders'),
        _gapSm,
        _RefCard(
          title: 'Ekahau Sidekick 2',
          chip: '2.4 / 5 / 6 GHz',
          body:
              'A tri-band survey appliance with an integrated real-time spectrum '
              'analyzer, driven from Ekahau survey software. The value is the '
              'integration: spectrum data overlays directly on the survey '
              'heatmap.',
        ),
        _gapSm,
        _RefCard(
          title: 'NetAlly NXT-2000',
          chip: '2.4 / 5 / 6 GHz',
          body:
              'The portable spectrum analyzer accessory that adds tri-band '
              'spectrum to the AirCheck G3 Pro tester, with a Frequency Spectrum '
              'density view and a Spectrogram time view. The base tester is a '
              'NIC-class instrument; spectrum needs the NXT-2000.',
        ),
        _gapSm,
        _RefCard(
          title: 'Oscium Lucid',
          chip: '2.4 / 5 / 6 GHz',
          body:
              'A tri-band USB analyzer (sold as Wi-Spy Lucid and WiPry Clarity) '
              'driven by Chanalyzer software. Oscium now owns MetaGeek, so the '
              'Wi-Spy and Chanalyzer line is one product family.',
        ),
        _gapMd,
        _H('Heritage (no longer shipping)'),
        _gapSm,
        _RefCard(
          title: 'MetaGeek Wi-Spy 2.4i and Wi-Spy DBx',
          body:
              'The USB analyzers a generation of WLAN pros learned spectrum on. '
              'End of life now; worth knowing as heritage, not as a current buy.',
        ),
        _gapSm,
        _RefCard(
          title: 'Cisco Cognio Spectrum Expert',
          body:
              'A landmark early enterprise spectrum analyzer. Cognio’s '
              'technology was acquired by Cisco, and its lineage fed into Cisco '
              'CleanAir.',
        ),
        _gapMd,
        _H('Budget / entry'),
        _gapSm,
        _RefCard(
          title: 'RF Explorer',
          body:
              'A family of low-cost handheld analyzers and an inexpensive entry '
              'point. Resolution and sensitivity sit well below survey grade, '
              'and coverage varies by model, so check the exact model before '
              'relying on it.',
        ),
        _gapMd,
        _Note(
          'Pricing moves and varies by region and reseller, so confirm before '
          'buying. Lab-grade benchtop instruments exist too, but they sit far '
          'beyond Wi-Fi survey needs and are not covered here.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. Mitigation
// ─────────────────────────────────────────────────────────────────────────────

class _MitigationScreen extends StatelessWidget {
  const _MitigationScreen();

  @override
  Widget build(BuildContext context) {
    return _TeachingScreen(
      title: 'Mitigation',
      children: const <Widget>[
        _Lead(
          'Removing the source is the only complete fix for a non-Wi-Fi '
          'interferer. Everything below it routes Wi-Fi around the problem '
          'instead of solving it.',
        ),
        _gapMd,
        _Bullets(
          ordered: true,
          <_Bullet>[
            _Bullet(
              lead: 'Identify and remove the source. ',
              rest: 'Fingerprint it in the waterfall, then physically locate it '
                  'with a directional antenna and a signal-strength hunt, or by '
                  'walking the density reading up as you get closer. Replace a '
                  'failing microwave oven, retire a 2.4 GHz analog cordless '
                  'phone or wireless camera, or power down a rogue bridge.',
            ),
            _Bullet(
              lead: 'Relocate the source or the access point. ',
              rest: 'If you cannot remove it, add physical separation or move '
                  'the access point. Distance and walls attenuate the '
                  'interferer.',
            ),
            _Bullet(
              lead: 'Shield it. ',
              rest: 'Sometimes practical for a fixed, localized emitter, but '
                  'usually a last resort and rarely a clean fix in real '
                  'buildings.',
            ),
            _Bullet(
              lead: 'Plan channels around it (1, 6, 11). ',
              rest: 'Steer Wi-Fi off the occupied frequencies. In 2.4 GHz there '
                  'are only three non-overlapping 20 MHz channels, 1, 6, and 11, '
                  'so a wideband interferer that hits the upper channels can be '
                  'dodged by favoring channel 1. Automatic channel assignment '
                  'can do this, but verify it is reacting to the interferer, not '
                  'just to co-channel Wi-Fi.',
            ),
            _Bullet(
              lead: 'Move critical traffic from 2.4 to 5 to 6 GHz. ',
              rest: 'The single most effective strategic mitigation. Most classic '
                  'interferers (microwaves, old cordless phones, ZigBee, '
                  'Bluetooth, analog cameras) live in 2.4 GHz. The 5 GHz band '
                  'has more channels and fewer of these sources, and 6 GHz is '
                  'currently the cleanest band because few legacy interferers '
                  'live there today. Reserve 2.4 GHz for devices that can only '
                  'use it.',
            ),
          ],
        ),
        _gapMd,
        _Note(
          'Only the first three steps remove the interferer; the last two route '
          'Wi-Fi around it. For a high-duty interferer sitting on the only band '
          'some clients can use, removal is the only real answer. And 6 GHz '
          'being clean is a current condition that will erode as adoption grows.',
        ),
      ],
    );
  }
}
