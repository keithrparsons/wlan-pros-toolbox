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
//   - Items 5/6/8 contact + feedback → the live wlanprofessionals.com/contact
//     form (the working form; the dropped `toolbox@` alias idea is gone).
//   - Item 4 #WLPC → thewlpc.com + the #WLPC Weekly newsletter, NO date.
//   - Item 7 Privacy → "Data not collected."
//   - Item 8 Version → the real shipped value via [AppVersion.display].
//   - Item 9 Credits → two-line version + a "View licenses" entry that opens
//     Flutter's built-in license registry (showLicensePage), not a hand list.
//
// Branding (2026-06-05): the WLAN Pros brand lockup (GL-003 §8.21) anchors the
// top of the screen on a white containment plate (the §8.19 white-tile-on-dark
// pattern), and the official site links now use the wlanprofessionals.com
// domain. Five external links are surfaced (site/resource library, the
// conference, #WLPC Weekly signup, training, contact + feedback).
//
// Tokens: GL-003 §8.1 surface stack, §4 spacing, §8.5 type, §8.3 focus rings
// (inherited via the themed TextButton / IconButton), §8.11 card radius +
// §8.21 logo plate on the header, §8.16 AppCopyAction on the version row.
// External links open via url_launcher (cross-platform: iOS + macOS, the two
// primary targets — the iOS-only Shortcuts bridge cannot serve macOS).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_version.dart';
import '../router/app_router.dart';
import '../services/app_update_service.dart';
import '../services/network/wifi_details_bridge.dart';
import '../services/network/wifi_info_adapter.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_copy_action.dart';
import '../widgets/appearance_control.dart';
import '../widgets/centered_content.dart';
import 'tools/network/install_shortcut_sheet.dart';
import 'tools/network/setup_live_wifi_icon.dart';

/// Main site and resource library — the WLAN Pros home, the official-site link.
const String _kWlanProsUrl = 'https://wlanprofessionals.com';

/// The WLPC conference site. No hardcoded date; thewlpc.com plus the #WLPC
/// Weekly newsletter are the live source (Keith's decision).
const String _kWlpcUrl = 'https://thewlpc.com';

/// #WLPC Weekly newsletter signup — the LeadPages capture form.
const String _kWlpcWeeklyUrl = 'https://wlanpros.lpages.co/wlpcweekly';

/// Training and classes — Keith's Wi-Fi troubleshooting training site.
const String _kTrainingUrl = 'https://wifitroubleshooting.com';

/// Contact and feedback — the live wlanprofessionals.com contact form, the
/// single real destination for both consulting (item 5) and feedback (items 6 &
/// 8). The earlier `toolbox@` alias idea is dropped; this form is the working
/// path.
const String _kContactUrl = 'https://wlanprofessionals.com/contact';

/// Feedback destination — the same live contact form as [_kContactUrl].
const String _kFeedbackUrl = _kContactUrl;

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.updateService});

  /// Injectable update checker. Null in production (the screen builds the real
  /// [AppUpdateService]); tests pass a scripted one to render each verdict
  /// without touching the network.
  final AppUpdateService? updateService;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Runtime build identity, read once via package_info_plus. Null until the
  // PackageInfo Future resolves — the UI shows a brief placeholder in that
  // window (no crash, no flash of a wrong/hardcoded value).
  AppVersionInfo? _version;

  // Update-check outcome. Null until the check resolves (and on a store-managed
  // or web build it stays effectively invisible — see [_UpdateLine]). The check
  // is fire-and-forget and NEVER awaited by build(): the About screen renders
  // fully before any network I/O starts, so a slow or dead network changes
  // nothing about how fast this screen appears.
  AppUpdateResult? _update;

  @override
  void initState() {
    super.initState();
    AppVersion.load().then((AppVersionInfo info) {
      if (!mounted) return;
      setState(() => _version = info);
      _checkForUpdate(info.version);
    });
  }

  /// Ask whether a newer build is published. [AppUpdateService.check] never
  /// throws, so there is no error path to handle here and nothing to show the
  /// user when it cannot answer beyond the honest "could not check" line.
  Future<void> _checkForUpdate(String currentVersion) async {
    final AppUpdateResult result = await (widget.updateService ??
            AppUpdateService())
        .check(currentVersion: currentVersion);
    if (!mounted) return;
    setState(() => _update = result);
  }

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
            textBuilder: () => _aboutPlainText(_version, _update),
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
                  // §8.21 — the WLAN Pros brand lockup on a white containment
                  // plate, centered at the top of the About column. The charcoal
                  // wordmark cannot sit bare on the dark canvas, so the plate
                  // (the §8.19 white-tile-on-dark pattern) carries it.
                  const _LogoHeader(),

                  // Build badge — version + build number read at RUNTIME,
                  // placed directly under the brand lockup so a beta tester can
                  // find and report the EXACT build at a glance. Copyable via
                  // the §8.16 AppCopyAction pattern. The fuller "Version and
                  // Feedback" section (item 8) still lives lower with the
                  // feedback link; both read the same runtime value so they
                  // never disagree.
                  _BuildBadge(info: _version),

                  // 0. Appearance — the §8.20.5 theme toggle (System / Light /
                  // Dark). Placed below the brand lockup as a Settings-style
                  // control on the app-level About surface, the standard
                  // reachable home for it.
                  const _AppearanceSection(),

                  // Set up live Wi-Fi — iOS-only, findable install entry point
                  // for the "WLAN Pros Live" companion Shortcut. iOS users who
                  // never open a live tool (or look here in About) would
                  // otherwise have no way to install it; this row opens the SAME
                  // one-time install sheet the live tools use. Renders nothing
                  // off iOS — macOS reads CoreWLAN natively and has no Shortcut.
                  const _LiveSetupAboutSection(),

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
                    links: <_SectionLink>[
                      _SectionLink(
                        leadIn: 'Want the full story?',
                        label: 'Main site and resource library',
                        url: _kWlanProsUrl,
                      ),
                    ],
                  ),

                  // 4. The #WLPC Conference
                  const _Section(
                    title: 'The #WLPC Conference',
                    paragraphs: <String>[
                      'If you work in Wi-Fi, go to WLPC at least once. It '
                          'changes how engineers think about the craft.',
                      'WLPC is the conference for Wireless LAN Professionals, '
                          'by Wireless LAN Professionals. It is vendor-neutral '
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
                    links: <_SectionLink>[
                      _SectionLink(
                        label: 'The conference',
                        url: _kWlpcUrl,
                      ),
                      _SectionLink(
                        label: '#WLPC Weekly signup',
                        url: _kWlpcWeeklyUrl,
                      ),
                    ],
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
                      'Reach out through the contact form at '
                          'wlanprofessionals.com and tell us what you\'re '
                          'working on.',
                    ],
                    links: <_SectionLink>[
                      _SectionLink(
                        label: 'Training and classes',
                        url: _kTrainingUrl,
                      ),
                      _SectionLink(
                        label: 'Contact and feedback',
                        url: _kContactUrl,
                      ),
                    ],
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
                  // Reads the same runtime build identity as the top badge.
                  _VersionSection(info: _version, update: _update),

                  // 8.5 About the founder — Keith Parsons headshot + approved
                  // short bio. Placed below the app/version info and above the
                  // legal/credits footer, the standard "who built this" slot.
                  const _FounderSection(),

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
/// Takes the runtime [AppVersionInfo] (null before it resolves) so the copied
/// text carries the real shipped version + build number.
/// The copy-text form of the update line, or null when the screen shows none
/// (still checking, store-managed, or web). Kept beside [_UpdateLine] so the two
/// wordings cannot drift apart.
String? _updatePlainText(AppUpdateResult? update) {
  final AppUpdateResult? r = update;
  if (r == null) return null;
  switch (r.status) {
    case AppUpdateStatus.upToDate:
      return 'This is the latest published version.';
    case AppUpdateStatus.unknown:
      return 'Could not check for a newer version.';
    case AppUpdateStatus.updateAvailable:
      return 'Version ${r.latestVersion} is available: '
          '${r.releaseUrl ?? kReleasesPageUrl}';
    case AppUpdateStatus.notApplicable:
      return null;
  }
}

String _aboutPlainText(AppVersionInfo? info, [AppUpdateResult? update]) {
  final AppVersionInfo v = info ?? AppVersion.fallback;
  final StringBuffer b = StringBuffer()
    ..writeln('WLAN Pros Toolbox: About')
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
      'Wireless LAN Professionals, Inc.: design and consulting, training, and '
      'community. Founder and Managing Director: Keith Parsons, CWNE #3. '
      '$_kWlanProsUrl',
    )
    ..writeln()
    ..writeln('The #WLPC Conference')
    ..writeln(
      'Vendor-neutral conference for Wireless LAN Professionals. For the next '
      'event: $_kWlpcUrl. #WLPC Weekly signup: $_kWlpcWeeklyUrl',
    )
    ..writeln()
    ..writeln('Get in touch')
    ..writeln(
      'Design, troubleshooting, or training: $_kContactUrl. '
      'Training and classes: $_kTrainingUrl',
    )
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
    ..writeln(v.display);
  // Carry the update state into the copied text: someone pasting this into a
  // support ticket should not silently lose "a newer version is available", and
  // "could not check" is worth knowing too. Mirrors the on-screen wording so
  // the copy never says more than the screen did.
  final String? updateLine = _updatePlainText(update);
  if (updateLine != null) b.writeln(updateLine);
  b
    ..writeln()
    ..writeln('Credits')
    ..writeln('Built by WLAN Pros.')
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

/// Set up live Wi-Fi — the **iOS-only** discoverable entry point, on the About
/// surface, for installing the "WLAN Pros Live" companion Shortcut.
///
/// Why it exists: on iOS the only paths to the install sheet were *inside* the
/// three live tools (the one-time auto-sheet, or the [LiveSetupCard] /
/// [LiveRfLockedCard] buttons). A beta tester who never opened a live tool, or
/// who looked in About, found no install affordance at all. This row closes
/// that discoverability gap by opening the SAME [showInstallShortcutSheet] —
/// reused, not duplicated — so what About installs can never drift from what
/// the live tools install.
///
/// iOS-only gate: identical to the live tools and the category-screen
/// [LiveSetupCard] banner — it renders only when
/// `WifiInfoSourceResolver.resolve()` is [WifiInfoSource.iosShortcuts]. On
/// macOS (CoreWLAN, no Shortcut), web, and every other platform it returns a
/// zero-height [SizedBox.shrink], so the row never appears there.
///
/// Honesty (GL-005): iOS cannot report whether a Shortcut is already installed,
/// so this is framed strictly as a one-time *setup* action — it never claims or
/// implies "installed". Unlike the in-tool [LiveSetupCard], it does NOT
/// self-hide once a payload has arrived: a findable setup entry stays put in
/// About regardless of install-state (re-running the install is harmless), and
/// querying that state here would add a bridge round-trip for no user benefit.
///
/// [onInstalled] is a deliberate no-op: About owns no live controller to kick,
/// so the sheet simply closes after "I've added it" — starting a live reading
/// from About would be wrong.
///
/// The iOS-only gate reads `defaultTargetPlatform` (web-safe; no `dart:io`),
/// the same signal the live tools use, so a widget test drives it end-to-end
/// via `debugDefaultTargetPlatformOverride` with no test-only constructor seam.
class _LiveSetupAboutSection extends StatefulWidget {
  const _LiveSetupAboutSection();

  @override
  State<_LiveSetupAboutSection> createState() => _LiveSetupAboutSectionState();
}

class _LiveSetupAboutSectionState extends State<_LiveSetupAboutSection> {
  late final bool _isIos;
  WiFiDetailsBridge? _bridge;

  @override
  void initState() {
    super.initState();
    _isIos =
        WifiInfoSourceResolver.resolve() == WifiInfoSource.iosShortcuts;
    // Only construct the native bridge on the iOS path — its channels have no
    // handler elsewhere, and off-iOS this widget renders nothing anyway.
    if (_isIos) {
      _bridge = WiFiDetailsBridge();
    }
  }

  Future<void> _openInstallSheet() async {
    final WiFiDetailsBridge? bridge = _bridge;
    if (bridge == null) return;
    await showInstallShortcutSheet(
      context: context,
      openUrl: bridge.openUrl,
      // No live controller to resume from About — the sheet just closes.
      onInstalled: () async {},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Off iOS (macOS CoreWLAN, web, etc.) there is no Shortcut to install, so
    // the row never renders and takes no vertical space.
    if (!_isIos) return const SizedBox.shrink();

    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Decorative hairline — matches the sibling section cards. The
          // interactive target inside carries its own §8.3 focus ring.
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
                'Set up live Wi-Fi',
                style: text.headlineSmall?.copyWith(
                  // §8.20.3-A section heading bumps to 700 in light.
                  fontWeight:
                      colors.isLight ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add the companion Shortcut for live signal details. iOS reads '
              'live Wi-Fi and cellular details through a small Shortcut, "WLAN '
              'Pros Live". You add it once, and every live tool works from then '
              'on.',
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openInstallSheet,
                // In-app sheet, not an external link → download glyph, mirroring
                // the install button inside the sheet itself.
                icon: const SetupLiveWifiIcon(size: 20),
                label: const Text('Set up live Wi-Fi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// GL-003 §8.21 — the WLAN Pros brand lockup ("wirelessLAN PROFESSIONALS" +
/// the lime #A1CC3A Wi-Fi arc) on a containment plate, centered at the top of
/// the About column.
///
/// Theme-aware plate, mirroring the sibling [_Section] / [_AppearanceSection]
/// cards in this file:
///   - Dark mode: a bare white (#FFFFFF) plate with no border — the deliberate
///     §8.21 light brand inset on the dark canvas (the §8.19 white-tile-on-dark
///     pattern). The charcoal wordmark would compute ~1.1:1 on the #1A1A1A
///     canvas (effectively invisible — the §8.21 broken-brand failure), so the
///     white plate carries it.
///   - Light mode: the plate switches to `surface1` + the §8.20.3-B 1.5px
///     hairline border, so it reads as a normal white card consistent with the
///     sibling section cards (the bare white-on-#F7F6F7 plate was invisible —
///     Vera's MEDIUM finding). The charcoal wordmark reads fine on light
///     surfaces, so no inset is needed.
///
/// The 24px plate padding IS the logo's protected clear-space; the asset is the
/// transparent, tight-bbox-trimmed PNG, rendered at its native aspect ratio
/// (never stretched or recolored).
class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  /// §8.21 About-header lockup width band is 160–200px; 180px sits in the
  /// middle and keeps the plate well under the §8.7 content max-width.
  static const double _lockupWidth = 180;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool isLight = colors.isLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        child: Container(
          // §8.21 plate: §8.11 card radius, §4 --space-md padding that doubles
          // as the protected clear-space. Fill + border are theme-aware:
          //   - Light: surface1 + §8.20.3-B 1.5px hairline (a normal white card,
          //     consistent with the sibling section cards).
          //   - Dark: bare white (#FFFFFF) inset, no border (the §8.21 light
          //     brand plate on the dark canvas).
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isLight ? colors.surface1 : AppColors.neutral0,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: isLight
                ? Border.all(
                    color: colors.border,
                    width: 1.5, // §8.20.3-B card border
                  )
                : null,
          ),
          child: Semantics(
            label: 'WLAN Pros, Wireless LAN Professionals',
            image: true,
            // The raster carries no text layer; the Semantics label above is the
            // accessible name, so the bare Image is hidden from the a11y tree.
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/brand/wlan_pros_logo.png',
                width: _lockupWidth,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled About section rendered as a surface1 card, with zero or more
/// trailing external links. Pure presentation; all copy comes from the parent.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.paragraphs,
    this.links = const <_SectionLink>[],
  });

  final String title;
  final List<String> paragraphs;

  /// External links rendered at the foot of the card, in order. Empty for
  /// sections with no link.
  final List<_SectionLink> links;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Decorative hairline — this card is not an interactive component, so
          // §8.1 decorative `border` is correct (not borderStrong).
          border: Border.all(color: colors.border),
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
                    text.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
            ],
            for (final _SectionLink l in links) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _ExternalLinkButton(
                label: l.label,
                url: l.url,
                leadIn: l.leadIn,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (leadIn != null) ...<Widget>[
          Text(
            leadIn!,
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
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
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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

/// Build badge — the easy-to-find, clearly-labeled version + build line at the
/// top of About, directly under the brand lockup. Reads the runtime
/// [AppVersionInfo] (null until package_info_plus resolves) so a beta tester can
/// find and report the EXACT build at a glance. The line is `SelectableText`
/// (copy on desktop) and carries a §8.16 [AppCopyAction] glyph (copy on touch)
/// so a tester can paste the exact build straight into feedback.
class _BuildBadge extends StatelessWidget {
  const _BuildBadge({required this.info});

  /// Runtime build identity; null until resolved → brief placeholder.
  final AppVersionInfo? info;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool resolved = info != null;
    // Pre-resolve placeholder keeps the row stable and never shows a wrong or
    // hardcoded value while the Future is in flight.
    final String display = resolved ? info!.display : 'Version…';

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Semantics(
                // One labelled node carrying the full identity for AT; the inner
                // mono SelectableText is the visible/desktop-copyable carrier.
                label: resolved
                    ? 'App ${info!.display}'
                    : 'App version loading',
                child: ExcludeSemantics(
                  // §8.5 — a build identifier is a computed/technical value, so
                  // DM Mono. Primary text once resolved; tertiary placeholder
                  // while loading.
                  child: SelectableText(
                    display,
                    style: text.bodyLarge?.copyWith(
                      fontFamily: 'DM Mono',
                      color:
                          resolved ? colors.textPrimary : colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // §8.16 copy affordance — copies JUST the version+build line so a
            // tester can paste the exact build into feedback. Disabled (null
            // builder) until the runtime value resolves, per the §8.16
            // "disabled, not hidden" rule for an eventually-available payload.
            AppCopyAction(
              textBuilder: resolved ? () => info!.display : () => null,
              idleLabel: 'Copy version and build',
              copiedLabel: 'Version copied',
            ),
          ],
        ),
      ),
    );
  }
}

/// Item 8 — Version and Feedback. The version line is selectable + copyable so
/// a support call can read it back exactly; the feedback link reuses the
/// contact form (same destination resolved in item 6). Reads the runtime
/// [AppVersionInfo] (null before it resolves) so the value matches the top
/// build badge and the actual shipped build.
class _VersionSection extends StatelessWidget {
  const _VersionSection({required this.info, this.update});

  /// Runtime build identity; null until package_info_plus resolves.
  final AppVersionInfo? info;

  /// Update-check outcome; null while the check is still in flight.
  final AppUpdateResult? update;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String display = (info ?? AppVersion.fallback).display;
    final bool resolved = info != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text('Version and Feedback', style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Real shipped version + build, read at runtime. Mono per §8.5 (a
            // build identifier reads as a computed/technical value).
            // SelectableText so it can be copied on desktop without a dedicated
            // action. Tertiary placeholder text in the brief pre-resolve window.
            Semantics(
              label: resolved ? 'App $display' : 'App version loading',
              child: SelectableText(
                resolved ? display : 'Version…',
                style: text.bodyLarge?.copyWith(
                  fontFamily: 'DM Mono',
                  color:
                      resolved ? colors.textPrimary : colors.textTertiary,
                ),
              ),
            ),
            // One quiet line about whether a newer build is published. Renders
            // nothing at all while the check is in flight and on builds that do
            // not check (store-managed installs, web), so the section looks
            // exactly as it did before on those platforms.
            _UpdateLine(update: update),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Running into something odd, or have an idea to make this '
              'better? Tell us. The toolbox gets better because the people '
              'using it in the field say what they need.',
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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

/// One line stating whether a newer build is published, plus a link when there
/// is one.
///
/// The three visible states are deliberately distinct, because the dangerous
/// failure here is rendering "we could not check" as if it were "you are up to
/// date". [AppUpdateStatus.unknown] therefore gets its own recessed tertiary
/// register and says plainly that the check did not complete; it never borrows
/// the reassuring wording. That is the same rule the rest of the app follows:
/// do not state a verdict the app could not measure.
///
/// [AppUpdateStatus.notApplicable] (a store-managed install, or web) and the
/// in-flight null case render a zero-size box, so nothing flashes and no build
/// is ever pointed at a download it should not use.
///
/// Tokens: §4 spacing, §8.5 type (body), theme-aware text colors. No hardcoded
/// color or size.
class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.update});

  final AppUpdateResult? update;

  @override
  Widget build(BuildContext context) {
    final AppUpdateResult? r = update;
    if (r == null || r.status == AppUpdateStatus.notApplicable) {
      return const SizedBox.shrink();
    }

    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // The line appears AFTER first paint, when the check resolves, and moves
    // no focus. Without a live region a screen-reader user is never told that
    // an update exists, because nothing announces the insertion (WCAG 2.2
    // SC 4.1.3). One region wraps every state so the announcement fires for
    // "could not check" too, not only the good news.
    return Semantics(
      liveRegion: true,
      child: _line(colors, text, r),
    );
  }

  Widget _line(AppColorScheme colors, TextTheme text, AppUpdateResult r) {
    switch (r.status) {
      case AppUpdateStatus.upToDate:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'This is the latest published version.',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          ),
        );

      case AppUpdateStatus.unknown:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'Could not check for a newer version.',
            style: text.bodyLarge?.copyWith(color: colors.textTertiary),
          ),
        );

      case AppUpdateStatus.updateAvailable:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Version ${r.latestVersion} is available.',
                // textAccent, NOT accent: §8.20.2 makes lime fill-only on
                // light, where bare `accent` on the card surface falls to
                // 3.11:1 and misses WCAG AA. textAccent is lime in dark and
                // darkened lime in light, so both themes clear 4.5:1 with no
                // call-site branching. Same token the sibling TextButton uses.
                style: text.bodyLarge?.copyWith(color: colors.textAccent),
              ),
              _ExternalLinkButton(
                label: 'Get the update',
                url: r.releaseUrl ?? kReleasesPageUrl,
              ),
            ],
          ),
        );

      case AppUpdateStatus.notApplicable:
        return const SizedBox.shrink();
    }
  }
}

/// About the founder — Keith Parsons headshot + the approved short bio.
///
/// Rendered in the same titled `surface1` card register as the sibling
/// [_Section] cards, so it reads as one more About section, not a foreign
/// element. Layout: a centered circular avatar over the name and a "CWNE #3"
/// caption, then the verbatim bio paragraph in the standard secondary body
/// register used by every other section paragraph.
///
/// The avatar is a [ClipOval]-masked [Image.asset] at a fixed 96px display box.
/// The bundled raster is ~288px (a ~3x asset for the 96px box), face-centered,
/// so the circular mask never clips the face and the image stays crisp on a 3x
/// device. Fit is [BoxFit.cover] on a square box, so the square source fills the
/// circle with no distortion.
///
/// Tokens: §8.1 surface1 card + §8.11 card radius + §8.20.3-B theme-aware border
/// (matching the sibling cards), §4 spacing, §8.5 type (H3 name / caption
/// CWNE line / body bio). No hardcoded color, size, or radius.
///
/// Accessibility: the heading carries `Semantics(header: true)` so a screen
/// reader can navigate to it (WCAG 2.2 SC 1.3.1); the headshot is decorative
/// alongside the adjacent visible name, so it is given a `Semantics(image:)`
/// label and its bare [Image] is excluded from the a11y tree (no duplicate
/// announcement of "Keith Parsons").
class _FounderSection extends StatelessWidget {
  const _FounderSection();

  /// Display diameter of the circular avatar. The bundled asset is ~3x this so
  /// the circle stays crisp on a 3x device (§ asset-resolution discipline).
  static const double _avatarDiameter = 96;

  /// Approved short bio (verbatim, SOP-020 register). US spelling, no em dashes.
  static const String _bio =
      'Keith Parsons is CWNE #3 and the founder and host of the Wireless LAN '
      'Professionals Conference (#WLPC). For 25 years he has worked in nothing '
      'but wireless, designing Wi-Fi in 117 countries, from a diamond mine 800 '
      'meters underground to the top of the Empire State Building, and teaching '
      'over 10,000 people to design and troubleshoot it. He built the WLAN Pros '
      'Toolbox to put the tools he reaches for in the field into one place, '
      'free, for everyone who does the work.';

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

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
            // §8.5 — section heading at H3, header for screen-reader navigation.
            Semantics(
              header: true,
              child: Text('About the founder', style: text.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.md),
            // Centered avatar + name + CWNE caption block.
            Center(
              child: Column(
                children: <Widget>[
                  Semantics(
                    label: 'Photo of Keith Parsons',
                    image: true,
                    child: ExcludeSemantics(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/brand/keith-parsons-headshot.png',
                          width: _avatarDiameter,
                          height: _avatarDiameter,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Keith Parsons',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'CWNE #3',
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Verbatim bio in the standard secondary body register.
            Text(
              _bio,
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
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
              'Built by WLAN Pros.',
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This app uses open-source software. Full license attributions '
              'are listed below.',
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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
