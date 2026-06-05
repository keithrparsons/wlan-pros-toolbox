// AboutScreen — the app-level "About" surface (SOP-020-approved copy).
//
// Information architecture: "About" is NOT a tool in the tool-catalog sense
// (it carries no RF/network data), so it is deliberately NOT a fifth home-grid
// category — the 4-category map is locked (tool_catalog.dart header). Instead it
// is an app-level affordance reached from an info IconButton in the HomeScreen
// AppBar, the standard place for app-level "About" in a utility app. One
// scrollable screen, each copy item rendered as a titled section card on
// surface1, matching the visual register of the reference screens.
//
// Copy is verbatim from the SOP-020-approved draft
// (Deliverables/2026-06-03-toolbox-about-content/about-draft.md, items 1-9).
// Placeholders resolved per Keith's finalized decisions:
//   - Items 5/6/8 contact + feedback → the live wlanpros.com contact form (one
//     real destination). A `toolbox@` feedback alias can replace it later (see
//     [_kFeedbackUrl]).
//   - Item 4 #WLPC → thewlpc.com + the #WLPC Weekly newsletter, NO date.
//   - Item 7 Privacy → "Data not collected."
//   - Item 8 Version → the real shipped value via [AppVersion.display].
//   - Item 9 Credits → two-line version + a "View licenses" entry that opens
//     Flutter's built-in license registry (showLicensePage), not a hand list.
//
// Tokens: GL-003 §8.1 surface stack, §4 spacing, §8.5 type, §8.3 focus rings
// (inherited via the themed TextButton / IconButton), §8.16 AppCopyAction on
// the version row. External links open via url_launcher (cross-platform: iOS +
// macOS, the two primary targets — the iOS-only Shortcuts bridge cannot serve
// macOS).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_version.dart';
import '../router/app_router.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_copy_action.dart';
import '../widgets/appearance_control.dart';
import '../widgets/centered_content.dart';

/// The WLAN Pros contact form — the single real destination for both consulting
/// (item 5) and feedback (items 6 & 8) per Keith's decision (2026-06-03).
const String _kContactUrl = 'https://www.wlanpros.com/contact/';

/// Feedback destination. Today this is the same live contact form as
/// [_kContactUrl]. When a dedicated `toolbox@wlanpros.com` (or `support@`) alias
/// goes live, point this at `mailto:toolbox@wlanpros.com` and the feedback links
/// in items 6 & 8 follow automatically — no other change needed.
const String _kFeedbackUrl = _kContactUrl;

/// WLAN Pros home — item 3 ("Visit wlanpros.com").
const String _kWlanProsUrl = 'https://www.wlanpros.com/';

/// The WLPC conference site — item 4. No hardcoded date; thewlpc.com plus the
/// #WLPC Weekly newsletter are the live source (Keith's decision).
const String _kWlpcUrl = 'https://thewlpc.com/';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        toolbarHeight: 64,
        actions: <Widget>[
          // §8.16 — copy the full About text. textBuilder is non-null always
          // (the copy is static), so the action renders enabled.
          AppCopyAction(
            textBuilder: () => _aboutPlainText(),
            idleLabel: 'Copy About text',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return CenteredContent(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                children: <Widget>[
                  // 0. Appearance — the §8.20.5 theme toggle (System / Light /
                  // Dark). Placed first as a Settings-style control on the
                  // app-level About surface, the standard reachable home for it.
                  const _AppearanceSection(),

                  // 1. Why this toolbox
                  const _Section(
                    title: 'Why this toolbox',
                    paragraphs: <String>[
                      'Every number in this app is a real measurement. Nothing '
                          'is faked, padded, or rounded to look better than it '
                          'is.',
                      'That sounds obvious. It is not. Plenty of Wi-Fi tools '
                          'hand you a confident number when they have no '
                          'business being confident, or fill a gap with a guess '
                          'and never tell you. We built this toolbox the other '
                          'way. When a value can be measured on your device, '
                          'you get the measurement. When the platform won\'t '
                          'give it to us, the app says so instead of inventing '
                          'one.',
                      'The toolbox is a working set of calculators, reference '
                          'tables, and live network checks for the engineers '
                          'who actually deploy and troubleshoot Wi-Fi. Use it '
                          'on a survey, on a support call, or to settle a '
                          'question in the field. It\'s built for pros, and '
                          'it\'s useful to anyone who wants the truth about '
                          'their connection.',
                    ],
                  ),

                  // 2. Why Gratis
                  const _Section(
                    title: 'Why Gratis',
                    paragraphs: <String>[
                      'This toolbox is free. No trial, no upgrade nag, no '
                          'account to create. Gratis.',
                      'WLAN Pros has had the same mission for years: the free '
                          'sharing of knowledge, so that better technicians, '
                          'engineers, VARs, and vendors build better networks '
                          'around the world. A free, honest toolbox is that '
                          'mission in your pocket. When more people measure '
                          'correctly, Wi-Fi gets better everywhere, and that is '
                          'the whole point.',
                      'There\'s no catch. If the app helps you do better work, '
                          'that\'s the return.',
                    ],
                  ),

                  // 3. Who is WLAN Pros
                  const _Section(
                    title: 'Who is WLAN Pros',
                    paragraphs: <String>[
                      'WLAN Pros is the company behind this toolbox. The full '
                          'name is Wireless LAN Professionals, Inc. We do three '
                          'things: design and consulting for Wi-Fi networks '
                          'around the world, hands-on training for the '
                          'engineers who run them, and community, through '
                          'articles, videos, a weekly newsletter, and the WLPC '
                          'conference series.',
                      'The founder and Managing Director is Keith Parsons, '
                          'CWNE #3, one of the first three people in the world '
                          'to earn the Certified Wireless Network Expert '
                          'credential. He has spent more than 25 years '
                          'building, breaking, and teaching Wi-Fi.',
                    ],
                    link: _SectionLink(
                      leadIn: 'Want the full story?',
                      label: 'Visit wlanpros.com',
                      url: _kWlanProsUrl,
                    ),
                  ),

                  // 4. The #WLPC Conference
                  const _Section(
                    title: 'The #WLPC Conference',
                    paragraphs: <String>[
                      'If you work in Wi-Fi, go to WLPC at least once. It '
                          'changes how engineers think about the craft.',
                      'WLPC is the conference for Wireless LAN professionals, '
                          'by Wireless LAN professionals. It is vendor-neutral '
                          'and free of sales pitches. The talks come from '
                          'working engineers sharing what they actually found '
                          'in the field, not marketing departments reading '
                          'slides. You get hands-on Boot Camps and Deep Dives, '
                          'real skill-building and cert prep, alongside '
                          'community-driven presentations. More than 30 events '
                          'across a dozen cities over roughly 14 years, and the '
                          'relationships you build there outlast any single '
                          'session.',
                      'Dates and locations change. For the next event and to '
                          'never miss one, go to thewlpc.com and sign up for '
                          'the #WLPC Weekly newsletter.',
                    ],
                    link: _SectionLink(
                      label: 'Open thewlpc.com',
                      url: _kWlpcUrl,
                    ),
                  ),

                  // 5. Get in touch
                  const _Section(
                    title: 'Get in touch',
                    paragraphs: <String>[
                      'Need help with a Wi-Fi design, a troubleshooting '
                          'problem, or training for your team? That\'s the day '
                          'job at WLAN Pros. We do design and consulting for '
                          'networks around the world, and we teach the '
                          'engineers who run them.',
                      'Reach out through the contact form at wlanpros.com and '
                          'tell us what you\'re working on.',
                    ],
                    link: _SectionLink(
                      label: 'Open the contact form',
                      url: _kContactUrl,
                    ),
                  ),

                  // 6. Help and Documentation — verbatim honesty/methodology
                  // copy, plus a "Browse tool help" action into the per-tool
                  // help browse screen and the feedback link.
                  const _HelpDocsSection(),

                  // 7. Privacy
                  const _Section(
                    title: 'Privacy',
                    paragraphs: <String>[
                      'We don\'t collect your data.',
                      'This app measures your network on your device. It isn\'t '
                          'built to track you, profile you, or ship your '
                          'information off somewhere. Data not collected, '
                          'exactly as stated on the App Store listing.',
                    ],
                  ),

                  // 8. Version and Feedback — version row is interactive
                  // (copyable) and the feedback link reuses the contact form.
                  const _VersionSection(),

                  // 9. Credits
                  const _CreditsSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A copy-friendly plain-text rendering of the whole About screen, for the
/// §8.16 AppCopyAction in the AppBar. Mirrors the on-screen sections in order.
String _aboutPlainText() {
  final StringBuffer b = StringBuffer()
    ..writeln('WLAN Pros Toolbox — About')
    ..writeln()
    ..writeln('Why this toolbox')
    ..writeln(
      'Every number in this app is a real measurement. When a value can be '
      'measured on your device, you get the measurement; when the platform '
      'won\'t give it, the app says so instead of inventing one.',
    )
    ..writeln()
    ..writeln('Why Gratis')
    ..writeln(
      'This toolbox is free. No trial, no upgrade nag, no account. WLAN Pros\' '
      'mission is the free sharing of knowledge so better networks get built '
      'around the world.',
    )
    ..writeln()
    ..writeln('Who is WLAN Pros')
    ..writeln(
      'Wireless LAN Professionals, Inc. — design and consulting, training, and '
      'community. Founder and Managing Director: Keith Parsons, CWNE #3. '
      '$_kWlanProsUrl',
    )
    ..writeln()
    ..writeln('The #WLPC Conference')
    ..writeln(
      'Vendor-neutral conference for Wireless LAN professionals. For the next '
      'event and the #WLPC Weekly newsletter: $_kWlpcUrl',
    )
    ..writeln()
    ..writeln('Get in touch')
    ..writeln('Design, troubleshooting, or training: $_kContactUrl')
    ..writeln()
    ..writeln('Help and Documentation')
    ..writeln(
      'Each tool does one job. The app measures what it can and says so when it '
      'can\'t. Every tool carries its own help (purpose, how to use, inputs, '
      'field notes); browse it all from the Help & Documentation screen or the '
      'help icon inside a tool. Feedback: $_kFeedbackUrl',
    )
    ..writeln()
    ..writeln('Privacy')
    ..writeln('Data not collected.')
    ..writeln()
    ..writeln('Version and Feedback')
    ..writeln('Version ${AppVersion.display}')
    ..writeln()
    ..writeln('Credits')
    ..writeln('Built by the team at WLAN Pros.')
    ..writeln('This app uses open-source software. See the in-app licenses.');
  return b.toString();
}

/// Appearance section — wraps the §8.20.5 [AppearanceControl] in the same
/// titled surface1 card register as the other About sections. Reads
/// `context.colors` so the card itself switches with the theme it controls.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: colors.border,
            width: colors.isLight ? 1.5 : 1, // §8.20.3-B card border
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                'Appearance',
                style: text.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  // §8.20.3-A section heading bumps to 700 in light.
                  fontWeight:
                      colors.isLight ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const AppearanceControl(),
          ],
        ),
      ),
    );
  }
}

/// A titled About section rendered as a surface1 card, with optional trailing
/// external link. Pure presentation; all copy comes from the parent.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.paragraphs,
    this.link,
  });

  final String title;
  final List<String> paragraphs;
  final _SectionLink? link;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Decorative hairline — this card is not an interactive component, so
          // §8.1 decorative `border` is correct (not borderStrong).
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // §8.5 — section heading at H3 / IBM Plex Sans 600.
            // Semantics(header: true) so a screen reader can navigate the
            // sections by heading (WCAG 2.2 SC 1.3.1).
            Semantics(
              header: true,
              child: Text(title, style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < paragraphs.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              Text(
                paragraphs[i],
                style:
                    text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (link != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _ExternalLinkButton(
                label: link!.label,
                url: link!.url,
                leadIn: link!.leadIn,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Declarative description of a section's external link.
class _SectionLink {
  const _SectionLink({required this.label, required this.url, this.leadIn});

  final String label;
  final String url;

  /// Optional sentence shown above the link button (e.g. "Want the full
  /// story?"), kept as body copy so the verbatim sentence survives.
  final String? leadIn;
}

/// A TextButton that opens an external URL via url_launcher. Inherits the §8.3
/// focus ring and lime foreground from the app's textButtonTheme; shows an
/// honest SnackBar if the platform cannot open the link (GL-005: never claim a
/// success that didn't happen).
class _ExternalLinkButton extends StatelessWidget {
  const _ExternalLinkButton({
    required this.label,
    required this.url,
    this.leadIn,
  });

  final String label;
  final String url;
  final String? leadIn;

  Future<void> _open(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Uri uri = Uri.parse(url);
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (leadIn != null) ...<Widget>[
          Text(
            leadIn!,
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.open_in_new, size: 20),
            label: Text(label),
          ),
        ),
      ],
    );
  }
}

/// Item 6 — Help and Documentation. Keeps the verbatim honesty/methodology copy
/// and the feedback link, and adds a "Browse tool help" action that navigates to
/// the per-tool [HelpBrowseScreen] (AppRouter.helpBrowse). Promoted from a const
/// [_Section] to its own widget so it can carry an in-app navigation action
/// (which is not const) alongside the external feedback link.
class _HelpDocsSection extends StatelessWidget {
  const _HelpDocsSection();

  static const List<String> _paragraphs = <String>[
    'Each tool does one job. Open a calculator and enter your values. Open a '
        'reference table to look something up. Open a live check to measure '
        'what\'s actually happening on your connection right now. The result '
        'screens are built to be read and copied, not decoded.',
    'How we measure. This matters more than any single feature. When a value '
        'can be measured on your device, the app measures it and shows you the '
        'real number. When the platform will not expose a value, or a '
        'measurement can\'t be trusted, the app says so. It does not guess and '
        'dress the guess up as data. That\'s the deal, and it\'s why you can '
        'trust what you see here on a job.',
    'Every tool carries its own help: what it does, why it\'s here, how to use '
        'it, the inputs it takes, and the honest field notes. Browse it all '
        'below, or tap the help icon inside a tool.',
    'Found a problem, or have an idea? Tell us. Good feedback from working '
        'engineers is how this toolbox gets better.',
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Help and Documentation', style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < _paragraphs.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              Text(
                _paragraphs[i],
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // In-app navigation into the per-tool help browse screen. Uses the
            // open_in_full glyph (not open_in_new, which means "leaves the app")
            // so the affordance reads as an in-app jump, not an external link.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.helpBrowse),
                icon: const Icon(Icons.menu_book_outlined, size: 20),
                label: const Text('Browse tool help'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ExternalLinkButton(
              label: 'Send feedback',
              url: _kFeedbackUrl,
            ),
          ],
        ),
      ),
    );
  }
}

/// Item 8 — Version and Feedback. The version line is selectable + copyable so
/// a support call can read it back exactly; the feedback link reuses the
/// contact form (same destination resolved in item 6).
class _VersionSection extends StatelessWidget {
  const _VersionSection();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Version and Feedback', style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Real shipped version. Mono per §8.5 (a build identifier reads as a
            // computed/technical value). SelectableText so it can be copied on
            // desktop without a dedicated action.
            Semantics(
              label: 'App version ${AppVersion.display}',
              child: SelectableText(
                'Version ${AppVersion.display}',
                style: text.bodyLarge?.copyWith(
                  fontFamily: 'DM Mono',
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Running into something odd, or have an idea to make this '
              'better? Tell us. The toolbox gets better because the people '
              'using it in the field say what they need.',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ExternalLinkButton(
              label: 'Send feedback',
              url: _kFeedbackUrl,
            ),
          ],
        ),
      ),
    );
  }
}

/// Item 9 — Credits. Two-line version per the draft, plus a "View licenses"
/// entry that opens Flutter's built-in license registry (showLicensePage)
/// rather than a hand-maintained attribution list.
class _CreditsSection extends StatelessWidget {
  const _CreditsSection();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Credits', style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Built by the team at WLAN Pros.',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This app uses open-source software. Full license attributions '
              'are listed below.',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'WLAN Pros Toolbox',
                  applicationVersion: AppVersion.display,
                ),
                icon: const Icon(Icons.description_outlined, size: 20),
                label: const Text('View licenses'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
