// Apple Wi-Fi Support Tips — a data-driven reference distilling Apple's own
// Wi-Fi support documentation into four sections:
//   A. Recommended router / Wi-Fi settings for Apple devices.
//   B. Run Wireless Diagnostics on a Mac (steps + the Window-menu tools).
//   C. The Option-click Wi-Fi menu (links to the macOS Menu-Bar Wi-Fi companion).
//   D. iOS / iPadOS Wi-Fi troubleshooting steps.
//
// Source of truth: lib/data/apple_wifi_tips_data.dart (compile-time const,
// footnoted to Apple support URLs). Each section carries a tappable link chip to
// the Apple article it came from (url_launcher, the established pattern from the
// Speed Test Services / Regulatory Domains screens).
//
// States (SOP-007 §5):
//  - success → the four sections always render (const data; no fetch, so no
//    loading/error path on the data itself).
//  - error → only the url-launch can fail; an honest "Could not open the link"
//    card appears with the URL spelled out so the user can copy it.
//  - empty → not applicable (the reference is never empty; const content).
//  - interactive → the AppBar §8.16 copy action, the per-section "Open Apple
//    article" link chips, and the "Open macOS Menu-Bar Wi-Fi" navigation chip,
//    all keyboard-focusable (the global §8.3 focus ring paints on focus).
//  - disabled → the copy action is always enabled (const content always present).
//
// HONESTY (GL-005, load-bearing): Apple's silence on transmit power and the
// single-Apple-source flag for the iOS steps are carried as real on-screen
// caveats, never hidden. Keith's domain note is attributed to Keith, not Apple.
//
// THEME: every color comes from context.colors (the AppColorScheme
// ThemeExtension) so the screen renders correctly in dark (§8) and light
// (§8.20). No new tokens introduced.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Wi-Fi" casing throughout.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/apple_wifi_tips_data.dart';
import '../../../data/tool_assets.dart';
import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kAppleWifiTipsToolId = 'apple-wifi-tips';

class AppleWifiTipsScreen extends StatefulWidget {
  const AppleWifiTipsScreen({super.key, this.launcher, this.onOpenMenuBarWifi});

  /// Injectable URL opener for tests. Defaults to [launchUrl].
  final Future<bool> Function(Uri url)? launcher;

  /// Navigation hook to the companion macOS Menu-Bar Wi-Fi screen. Injectable
  /// for tests; defaults to a named-route push when null.
  final VoidCallback? onOpenMenuBarWifi;

  @override
  State<AppleWifiTipsScreen> createState() => _AppleWifiTipsScreenState();
}

class _AppleWifiTipsScreenState extends State<AppleWifiTipsScreen> {
  String? _launchError;

  Future<void> _openUrl(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _showLaunchError(url);
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError(url);
        return;
      }
      if (!mounted) return;
      setState(() => _launchError = null);
    } on Object {
      _showLaunchError(url);
    }
  }

  void _showLaunchError(String url) {
    if (!mounted) return;
    setState(() => _launchError = 'Could not open the browser. The link is $url');
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  void _openMenuBarWifi() {
    final VoidCallback? hook = widget.onOpenMenuBarWifi;
    if (hook != null) {
      hook();
      return;
    }
    Navigator.of(context).pushNamed(AppRouter.macosMenubarWifi);
  }

  /// §8.16 plain-text payload — every section in order so nothing on-screen
  /// survives only as layout. Source URLs included.
  static String _copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Apple Wi-Fi Support Tips')
      ..writeln()
      ..writeln('A. Recommended router / Wi-Fi settings for Apple devices')
      ..writeln(kAppleSettingsIntro);
    for (final AppleSettingRow r in kAppleSettings) {
      b.writeln('  ${r.setting}: ${r.recommendation}');
    }
    b
      ..writeln(kAppleSettingsSilenceNote)
      ..writeln(kAppleSettingsKeithNote)
      ..writeln('  Source: ${kAppleSources['settings']!.url}')
      ..writeln()
      ..writeln('B. Run Wireless Diagnostics on a Mac')
      ..writeln(kAppleDiagIntro);
    for (int i = 0; i < kAppleDiagSteps.length; i++) {
      b.writeln('  ${i + 1}. ${kAppleDiagSteps[i].body}');
    }
    b.writeln(kAppleDiagWindowIntro);
    for (final DiagUtility u in kAppleDiagUtilities) {
      b.writeln('  ${u.name}: ${u.what}');
    }
    b
      ..writeln('  Source: ${kAppleSources['diag']!.url}')
      ..writeln()
      ..writeln('C. The Option-click Wi-Fi menu')
      ..writeln(kAppleOptionClickBody)
      ..writeln(kAppleOptionClickLinkNote)
      ..writeln()
      ..writeln('D. iOS / iPadOS Wi-Fi troubleshooting steps')
      ..writeln(kAppleIosIntro);
    for (int i = 0; i < kAppleIosSteps.length; i++) {
      b.writeln('  ${i + 1}. ${kAppleIosSteps[i].body}');
    }
    b
      ..writeln(kAppleIosSingleSourceNote)
      ..writeln('  Source: ${kAppleSources['ios']!.url}');
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple Wi-Fi Support Tips'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
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
                  ConceptGraphicBand(
                    toolId: kAppleWifiTipsToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kAppleWifiTipsToolId))
                    const SizedBox(height: AppSpacing.md),
                  _IntroCard(),
                  const SizedBox(height: AppSpacing.md),
                  // A. Settings.
                  _SectionCard(
                    label: 'A. Recommended router / Wi-Fi settings',
                    intro: kAppleSettingsIntro,
                    sourceId: 'settings',
                    onOpen: _openUrl,
                    children: <Widget>[
                      for (final AppleSettingRow r in kAppleSettings)
                        _LabeledRow(label: r.setting, value: r.recommendation),
                      const SizedBox(height: AppSpacing.xs),
                      _CaveatLine(
                        icon: Icons.info_outline,
                        text: kAppleSettingsSilenceNote,
                      ),
                      _CaveatLine(
                        icon: Icons.lightbulb_outline,
                        text: kAppleSettingsKeithNote,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // B. Wireless Diagnostics.
                  _SectionCard(
                    label: 'B. Run Wireless Diagnostics on a Mac',
                    intro: kAppleDiagIntro,
                    sourceId: 'diag',
                    onOpen: _openUrl,
                    children: <Widget>[
                      for (int i = 0; i < kAppleDiagSteps.length; i++)
                        _StepRow(number: i + 1, body: kAppleDiagSteps[i].body),
                      const SizedBox(height: AppSpacing.xs),
                      _SubHeading(text: kAppleDiagWindowIntro),
                      for (final DiagUtility u in kAppleDiagUtilities)
                        _LabeledRow(label: u.name, value: u.what),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // C. Option-click menu → links to the companion screen.
                  _SectionCard(
                    label: 'C. The Option-click Wi-Fi menu',
                    intro: kAppleOptionClickBody,
                    children: <Widget>[
                      _CaveatLine(
                        icon: Icons.open_in_full,
                        text: kAppleOptionClickLinkNote,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _LinkChip(
                        icon: Icons.arrow_forward,
                        label: 'Open macOS Menu-Bar Wi-Fi',
                        semanticLabel:
                            'Open the macOS Menu-Bar Wi-Fi reference for what each field means',
                        onTap: _openMenuBarWifi,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // D. iOS troubleshooting.
                  _SectionCard(
                    label: 'D. iOS / iPadOS Wi-Fi troubleshooting',
                    intro: kAppleIosIntro,
                    sourceId: 'ios',
                    onOpen: _openUrl,
                    children: <Widget>[
                      for (int i = 0; i < kAppleIosSteps.length; i++)
                        _StepRow(number: i + 1, body: kAppleIosSteps[i].body),
                      const SizedBox(height: AppSpacing.xs),
                      _CaveatLine(
                        icon: Icons.fact_check_outlined,
                        text: kAppleIosSingleSourceNote,
                      ),
                    ],
                  ),
                  if (_launchError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _MessageCard(
                      icon: Icons.link_off,
                      title: 'Could not open the link',
                      body: _launchError!,
                    ),
                  ],
                  ToolHelpFooter(toolId: kAppleWifiTipsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The hero/intro band stating these come straight from Apple's own docs.
class _IntroCard extends StatelessWidget {
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
      child: Text(
        "Apple's official Wi-Fi guidance in one place: the router settings "
        'Apple recommends, how to run Wireless Diagnostics on a Mac, how to read '
        'the Option-click Wi-Fi menu, and the iPhone / iPad troubleshooting '
        'steps. Each section links back to the Apple article it came from.',
        style: (t.bodyMedium ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// One A-D section: a heading, an intro line, the section body, and (when it has
/// a source) a tappable "Open Apple article" link chip.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.label,
    required this.intro,
    required this.children,
    this.sourceId,
    this.onOpen,
  });

  final String label;
  final String intro;
  final List<Widget> children;
  final String? sourceId;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppleSource? source =
        sourceId == null ? null : kAppleSources[sourceId];
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
            label,
            style: (t.titleMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            intro,
            style: (t.bodySmall ?? const TextStyle())
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
          if (source != null && onOpen != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _LinkChip(
              icon: Icons.open_in_new,
              label: 'Open Apple article',
              semanticLabel: 'Open the Apple support article: ${source.label}',
              onTap: () => onOpen!(source.url),
            ),
          ],
        ],
      ),
    );
  }
}

/// An inline "Label: value" row, label muted/bold, value in body.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label. $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RichText(
          text: TextSpan(
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
            children: <InlineSpan>[
              TextSpan(
                text: '$label  ',
                style: (t.labelMedium ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      ),
    );
  }
}

/// One numbered step (ordered checklist rows in Sections B and D).
class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.body});

  final int number;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Step $number. $body',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(
                '$number.',
                style: (t.labelMedium ?? const TextStyle()).copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                body,
                style: t.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small sub-heading inside a section (e.g. the Window-menu intro).
class _SubHeading extends StatelessWidget {
  const _SubHeading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: (t.labelMedium ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A caveat / note line: a small leading glyph + tertiary text. Paired with an
/// icon and full text (never color-only, §8.13).
class _CaveatLine extends StatelessWidget {
  const _CaveatLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A keyboard-focusable link-out / navigation chip. The global §8.3 focus theme
/// paints the ring on focus; the outline is the foreground-lime accent.
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: colors.textAccent, width: 1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 16, color: colors.textAccent),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      label,
                      style: (t.labelMedium ?? const TextStyle()).copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error card for a failed url launch — mirrors the speedtest "Could not open
/// the link" surface.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
