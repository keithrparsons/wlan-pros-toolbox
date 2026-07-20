// GuideReaderScreen — the in-app, offline markdown reader for the two bundled
// written guides (help-embed, 2026-06-07).
//
// What it renders:
//   * the app-orientation guide "How this app works" (assets/guides/user-guide.md),
//     reached from a small home-screen entry (the consumer app-map on-ramp); and
//   * the professional "Field Manual" (assets/guides/field-manual.md, ~190 KB),
//     reached from the Educational Resources directory.
//
// Why a native reader (not a flat PDF): GL-003 themed, reflowing text that
// honors light/dark, with jump-to-section navigation. The field manual is far
// too long for a single endless scroll, so the AppBar carries a "Contents"
// action that opens a themed table-of-contents sheet; tapping a heading jumps
// the reader to that section (markdown_widget's TocController + TocWidget).
//
// Package choice: `markdown_widget` (2.3.2+8, on `markdown` 7.3.1) — actively
// maintained, pure-Dart render, with a first-class TocController/TocWidget for
// the jump-to-section requirement and a per-tag MarkdownConfig that maps cleanly
// onto GL-003 type + color tokens. Chosen over the discontinued flutter_markdown
// (no maintained TOC) after a `flutter pub add` build check.
//
// Tokens (GL-003): §8.1 surface stack + §8.20.1 light via `context.colors`,
// §8.5 in-app type sizes/leadings + §3 families (IBM Plex Sans body/headings,
// DM Mono code), §8.2/§8.20.1 text ramp, §8.20.2 lime-as-foreground rule
// (links use `textAccent`, never bare lime on light), §4 spacing, §8.11 radius,
// §8.3 focus rings (inherited globally via the app iconButtonTheme), §8.16
// AppCopyAction. No hardcoded hex / sizes — every value resolves to a token.
//
// States (SOP-007 §5):
//   loading → asset read in flight (one frame, fast): a spinner + AT announce.
//   error   → the bundled asset failed to load (should never happen in a
//             shipped build): an honest message card.
//   success → the themed, scrollable, navigable document.
// There is no empty state — a bundled guide is never empty; there is no
// interactive/disabled input beyond the Contents action (disabled until loaded).
//
// Offline + App-Store-safe: the guides are plain `.md` assets read from the
// bundle via rootBundle — no network, no executable content (90035-safe).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_version.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_copy_action.dart';

/// Asset paths for the two bundled guides. Public so the entry points
/// (home card, Educational Resources row) and the widget tests share one
/// source of truth rather than re-typing the string.
const String kUserGuideAsset = 'assets/guides/user-guide.md';
const String kFieldManualAsset = 'assets/guides/field-manual.md';

/// The placeholder the guide markdown carries where the app's version belongs,
/// e.g. the header line `app v{{app_version}}`. The reader fills it at load time
/// with the ACTUAL running version (from [AppVersion], which reads package
/// metadata at runtime) so the printed version can never drift from the shipped
/// build. Any release that bumps pubspec updates every guide automatically — the
/// literal that used to rot here (a hand-typed `app v1.5.4`) is gone.
///
/// A hardcoded app-version literal in guide/help prose is caught mechanically by
/// scripts/version-guard.sh (wired into `flutter test` via
/// test/consistency/version_consistency_guard_test.dart), so a future edit that
/// reintroduces a baked-in version and lets it drift cannot ship.
const String kAppVersionPlaceholder = '{{app_version}}';

/// Fill guide-content placeholders with runtime values before rendering.
///
/// Pure and synchronous so it is trivially unit-testable and so the widget-test
/// override path shares the exact substitution the production load path uses.
/// Today it fills only [kAppVersionPlaceholder]; add future runtime tokens here.
String applyGuidePlaceholders(String raw, String appVersion) =>
    raw.replaceAll(kAppVersionPlaceholder, appVersion);

/// Deep-link anchor (the exact chapter heading text) for the user guide's
/// "Wi-Fi vs Cellular vs Internet" explainer. Shared with the Test My Connection
/// "What's the difference?" aside so both sides agree on ONE target string
/// (SSOT) — pass it to [GuideReaderScreen.initialHeadingAnchor] to open the
/// reader scrolled to that chapter. Must match the `##` heading verbatim in
/// assets/guides/user-guide.md.
const String kWifiCellularInternetChapter =
    "Wi-Fi vs Cellular vs Internet: what's the difference?";

/// A bundled markdown guide rendered natively in a themed, navigable reader.
///
/// [assetPath] is the bundled `.md` to read; [title] is the AppBar title. An
/// optional [markdownOverride] injects content in widget tests so they do not
/// depend on the live asset bundle.
class GuideReaderScreen extends StatefulWidget {
  const GuideReaderScreen({
    required this.assetPath,
    required this.title,
    this.markdownOverride,
    this.initialHeadingAnchor,
    super.key,
  });

  /// Bundled `.md` asset to render (e.g. [kUserGuideAsset]).
  final String assetPath;

  /// AppBar title for this guide.
  final String title;

  /// Test seam: when non-null, this markdown string is rendered instead of
  /// reading [assetPath] from the bundle. Production never sets it.
  final String? markdownOverride;

  /// Optional deep-link: the exact heading text of a section to scroll to once
  /// the document has loaded (e.g. [kWifiCellularInternetChapter] from the Test
  /// My Connection "What's the difference?" aside). Null (the default) opens the
  /// guide at the top, unchanged. A value that matches no heading is a no-op —
  /// the reader simply stays at the top rather than failing.
  final String? initialHeadingAnchor;

  @override
  State<GuideReaderScreen> createState() => _GuideReaderScreenState();
}

class _GuideReaderScreenState extends State<GuideReaderScreen> {
  /// Drives jump-to-section: the AppBar "Contents" sheet (a [TocWidget]) and the
  /// [MarkdownWidget] share this controller, so tapping a heading scrolls the
  /// document to it.
  final TocController _tocController = TocController();

  String? _markdown;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final String? override = widget.markdownOverride;
    if (override != null) {
      // Test seam: fill placeholders synchronously with the const fallback
      // version so widget tests exercise the same substituted output the
      // production path renders, without binding the PackageInfo channel.
      _markdown =
          applyGuidePlaceholders(override, AppVersion.fallback.version);
      _scheduleInitialJump();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _tocController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final String raw = await rootBundle.loadString(widget.assetPath);
      // Runtime version fill: read the ACTUAL running build's version (falls
      // back to the pubspec-mirrored const if the platform channel is
      // unavailable) so the guide's `app v…` line always matches the build the
      // user is running. Never a hand-typed literal that can drift.
      final AppVersionInfo version = await AppVersion.load();
      if (!mounted) return;
      setState(() =>
          _markdown = applyGuidePlaceholders(raw, version.version));
      _scheduleInitialJump();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load this guide: $e');
    }
  }

  /// Deep-link: after the document renders, scroll to the section whose heading
  /// matches [GuideReaderScreen.initialHeadingAnchor]. No-op when no anchor was
  /// requested or none matches.
  ///
  /// Timing: [MarkdownWidget] populates [TocController.tocList] and registers its
  /// jump callback synchronously in its own `initState` (which runs while this
  /// build renders it), so the first post-frame callback after the markdown is
  /// set has a fully-populated TOC to look up and a live scroll target. The jump
  /// (scroll_to_index under the hood) progressively scrolls to an off-screen
  /// heading, so a chapter far down the guide still lands correctly.
  void _scheduleInitialJump() {
    final String? anchor = widget.initialHeadingAnchor;
    if (anchor == null) return;
    final String target = anchor.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final Toc toc in _tocController.tocList) {
        if (_headingText(toc.node).trim() == target) {
          _tocController.jumpToIndex(toc.widgetIndex);
          return;
        }
      }
    });
  }

  /// Open a link in the system browser. The guides are largely self-contained,
  /// but any external URL opens via url_launcher (the app-wide external-link
  /// path) rather than navigating inside the reader.
  Future<void> _openLink(String href) async {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// The full guide text, for the §8.16 copy affordance. Null until loaded
  /// (→ the copy action renders disabled and drops from focus traversal).
  String? _copyText() => _markdown;

  @override
  Widget build(BuildContext context) {
    final bool ready = _markdown != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        toolbarHeight: 64,
        actions: <Widget>[
          // §8.16 order: copy leading, then the Contents (TOC) action trailing.
          AppCopyAction(
            textBuilder: _copyText,
            idleLabel: 'Copy guide text',
            copiedLabel: 'Guide text copied',
          ),
          // Explicit accessible name (WCAG 2.2 AA SC 4.1.2, GL-003 §8.16):
          // `tooltip:` maps to AXHelp, not AXTitle, so an icon-only button reads
          // as `label="" button=true` without this. `enabled:` tracks `ready`
          // so AT hears the same disabled state the null onPressed encodes.
          Semantics(
            button: true,
            enabled: ready,
            label: 'Open table of contents',
            child: IconButton(
              icon: const Icon(Icons.list_alt_outlined),
              tooltip: 'Contents',
              // Disabled until the document (and thus its TOC) is loaded; a null
              // onPressed drops it from focus traversal and exposes the disabled
              // state to AT (§8.16 empty/no-results rule applied to the action).
              onPressed: ready ? _openContents : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final AppColorScheme colors = context.colors;

    if (_loadError != null) {
      return _GuideMessage(
        icon: Icons.error_outline,
        title: 'Guide unavailable',
        body: _loadError!,
      );
    }

    final String? md = _markdown;
    if (md == null) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Semantics(
            label: 'Loading ${widget.title}',
            liveRegion: true,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textAccent,
            ),
          ),
        ),
      );
    }

    // Cap the reading column at the shared content width (§ contentMaxWidth) so
    // long-line prose does not sprawl edge-to-edge on tablet/desktop, matching
    // every other app surface (CenteredContent contract).
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double edge = constraints.maxWidth >= 720
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: MarkdownWidget(
              data: md,
              tocController: _tocController,
              selectable: true,
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.md,
                edge,
                edge + AppSpacing.md,
              ),
              config: _markdownConfig(colors),
            ),
          ),
        );
      },
    );
  }

  /// Open the themed table-of-contents as a bottom sheet. Tapping a heading
  /// jumps the reader to that section and dismisses the sheet.
  void _openContents() {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface2,
      barrierColor: colors.scrim,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            // Cap the sheet height so a long TOC scrolls inside the sheet
            // rather than covering the whole screen.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Contents',
                      style: text.headlineSmall?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: TocWidget(
                    controller: _tocController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    tocTextStyle: text.bodyLarge!.copyWith(
                      color: colors.textSecondary,
                    ),
                    currentTocTextStyle: text.bodyLarge!.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                    itemBuilder: (TocItemBuilderData data) =>
                        _tocItem(data, colors, text, sheetContext),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One themed TOC row. Indents by heading depth, renders the heading text in
  /// GL-003 tokens, and on tap jumps the reader to the section then closes the
  /// sheet. Carries a proper button semantic for AT.
  Widget _tocItem(
    TocItemBuilderData data,
    AppColorScheme colors,
    TextTheme text,
    BuildContext sheetContext,
  ) {
    final Toc toc = data.toc;
    final String tag = toc.node.headingConfig.tag; // 'h1'..'h6'
    final int level = headingTag2Level[tag] ?? 1;
    final bool isCurrent = data.index == data.currentIndex;
    // The heading node's build() wraps its content in a WidgetSpan (divider +
    // padding), so toPlainText() yields only the object-replacement glyph. Walk
    // the node's child TextNodes instead to recover the heading words.
    final String label = _headingText(toc.node);

    return Semantics(
      button: true,
      selected: isCurrent,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          _tocController.jumpToIndex(toc.widgetIndex);
          data.refreshIndexCallback(data.index);
          Navigator.of(sheetContext).pop();
        },
        // Guarantee the WCAG 2.2 / GL-003 §8.3 44pt minimum touch target on the
        // TOC rows (the most-tapped control in the longest document).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md + AppSpacing.sm * (level - 1),
                right: AppSpacing.md,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                label,
                style: (isCurrent ? text.bodyLarge : text.bodyMedium)?.copyWith(
                  color: isCurrent ? colors.textAccent : colors.textSecondary,
                  fontWeight: level == 1
                      ? FontWeight.w600
                      : (isCurrent ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Recover a heading's plain text by walking the node tree's [TextNode]s.
  /// (HeadingNode.build() wraps content in a WidgetSpan, so toPlainText() on it
  /// returns only the object-replacement character.)
  String _headingText(SpanNode node) {
    final StringBuffer buffer = StringBuffer();
    void walk(SpanNode n) {
      if (n is TextNode) {
        buffer.write(n.text);
      } else if (n is ElementNode) {
        for (final SpanNode child in n.children) {
          walk(child);
        }
      }
    }

    walk(node);
    return buffer.toString().trim();
  }

  /// GL-003-themed markdown config: every tag mapped to a token.
  MarkdownConfig _markdownConfig(AppColorScheme colors) {
    final TextTheme text = Theme.of(context).textTheme;

    // Headings — §8.5 in-app scale: h1 → display-ish screen-major (h1/36),
    // h2 → section (h2/28), h3 → subsection (h3/22). The guides use # for parts,
    // ## / ### for sections, so this ladder reads as the doc structure intends.
    final TextStyle h1 = text.displaySmall!.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle h2 = text.headlineMedium!.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle h3 = text.headlineSmall!.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    final TextStyle h4 = text.titleMedium!.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );

    // Body prose — §8.5 body (16 / 1.45), primary-ish reading ink.
    final TextStyle body = text.bodyLarge!.copyWith(
      color: colors.textSecondary,
    );

    // Inline code / fenced code — DM Mono on a recessed input-fill surface,
    // bounded for legibility. §8.5 inline-code register.
    final TextStyle codeStyle = text.bodyLarge!.copyWith(
      fontFamily: 'DM Mono',
      color: colors.textPrimary,
      backgroundColor: colors.inputFill,
    );
    final TextStyle preTextStyle = text.bodyMedium!.copyWith(
      fontFamily: 'DM Mono',
      color: colors.textPrimary,
    );

    // Links — §8.20.2: lime as a FOREGROUND must use `textAccent` (darkened-lime
    // on light, brand lime on dark), never bare lime on light. Underlined so the
    // link is not color-only (SC 1.4.1).
    final TextStyle link = body.copyWith(
      color: colors.textAccent,
      decoration: TextDecoration.underline,
      decorationColor: colors.textAccent,
    );

    return MarkdownConfig(
      configs: <WidgetConfig>[
        H1Config(style: h1),
        H2Config(style: h2),
        H3Config(style: h3),
        H4Config(style: h4),
        PConfig(textStyle: body),
        LinkConfig(style: link, onTap: _openLink),
        ListConfig(marker: _bulletMarker),
        BlockquoteConfig(
          sideColor: colors.borderStrong,
          textColor: colors.textTertiary,
        ),
        // Figures — bundled asset images (e.g. the signal-meters diagram in the
        // "Wi-Fi vs Cellular vs Internet" chapter). markdown_widget's default
        // ImageNode renders `Image.asset` at the image's INTRINSIC pixel size
        // inside a WidgetSpan, so a 3200px-wide diagram would overflow every
        // phone width; this builder caps the figure to the reading column, gives
        // it a GL-003 hairline + card radius, an accessible alt-text label, and
        // an honest error card if the asset ever fails to decode.
        ImgConfig(builder: _figureBuilder),
        CodeConfig(style: codeStyle),
        PreConfig(
          textStyle: preTextStyle,
          decoration: BoxDecoration(
            color: colors.inputFill,
            border: Border.all(color: colors.border, width: 1),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
        ),
        HrConfig(color: colors.border),
      ],
    );
  }

  /// Themed figure for a bundled asset image (`![alt](assets/...)`).
  ///
  /// Caps the width to the reading column (screen width, edge-inset, then the
  /// shared §contentMaxWidth), preserving aspect ratio, and frames it with the
  /// §8.1 hairline + §8.11 card radius. `alt` becomes the AT image label (SC
  /// 1.1.1); a decode failure renders that same alt as an honest caption rather
  /// than a broken-image glyph. Network images are not used by the bundled
  /// guides, so this handles the asset case only.
  Widget _figureBuilder(String url, Map<String, String> attributes) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String alt = attributes['alt'] ?? '';
    final Size size = MediaQuery.of(context).size;
    final double edge = size.width >= 720
        ? AppSpacing.screenEdgeDesktop
        : AppSpacing.screenEdgeMobile;
    final double maxWidth =
        math.min(size.width, AppSpacing.contentMaxWidth) - edge * 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        image: true,
        label: alt.isEmpty ? null : alt,
        child: Container(
          constraints: BoxConstraints(maxWidth: math.max(maxWidth, 0)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            url,
            width: math.max(maxWidth, 0),
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  alt.isEmpty ? 'Figure unavailable' : alt,
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Diameter of the unordered-list bullet dot. A glyph dimension (not a §4
  /// spacing gap), so GL-003 has no token for it; composed from existing tokens
  /// (`xxs` 4 + 2) per Vera's 2026-06-07 gate LOW so no bare literal remains in
  /// an otherwise fully tokenized file. Swap to a marker-size token if Iris adds
  /// one.
  static const double _bulletDotSize = AppSpacing.xxs + 2;

  /// Themed list bullet — a small lime-foreground dot, sized to the body line.
  Widget _bulletMarker(bool isOrdered, int depth, int index) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    if (isOrdered) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: Text(
          '${index + 1}.',
          style: text.bodyLarge?.copyWith(color: colors.textTertiary),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        right: AppSpacing.xs,
        left: AppSpacing.xxs,
      ),
      child: Container(
        width: _bulletDotSize,
        height: _bulletDotSize,
        decoration: BoxDecoration(
          color: colors.textAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// An honest error/message card matching the reference-screen message register.
class _GuideMessage extends StatelessWidget {
  const _GuideMessage({
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Container(
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
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
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
