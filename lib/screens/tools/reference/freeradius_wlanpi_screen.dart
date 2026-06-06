// FreeRADIUS on WLAN Pi — a how-to / guide screen (v1.1).
//
// A standing-up-a-lab-RADIUS-server walkthrough built around Ferney Munoz's
// bundled install script (assets/downloads/install_freeradius.sh.txt — bundled
// under a .txt extension for iOS signing; downloads AS install_freeradius.sh).
// The screen
// renders the approved preview (Deliverables/2026-06-05-freeradius-wlanpi/
// mockup, dark + light):
//   1. concept band (Pi -> RADIUS shield -> 802.1X client)
//   2. one-line intro
//   3. a PROMINENT lab-caveat banner (§8.13/§8.20.4 amber/bronze warning) —
//      never color-only; the word "Lab" + full caveat text carry the meaning
//   4. numbered steps (scp / chmod +x / ./install_freeradius.sh)
//   5. a primary "Download install_freeradius.sh" button (reuses the
//      share/save seam the PDF cards use — shareAsset, §macOS-sandbox-safe)
//   6. the script shown inline in a scrollable mono code block (the REAL
//      bundled bytes, loaded at runtime — not a hand-copied excerpt, so it can
//      never drift from what downloads)
//   7. "Customize it" (change the secret in clients.conf, add users)
//   8. "Useful commands"
//   9. credit: "Guide and install script by Ferney Munoz."
//
// PLATFORM (GL-008): the Toolbox runs no shell — this guide is reference text +
// a file the user copies to their own WLAN Pi and runs THERE. Nothing here is
// executed in-app. The script is bundled VERBATIM and is read-only; the inline
// view and the download hand the user the exact same bytes.
//
// STATES: the script body is a bundled asset loaded once via rootBundle, so the
// code block has explicit loading (spinner while the asset string resolves),
// error (asset failed to load — honest, no retry, a bundled asset that fails
// won't succeed on retry), and success (the script renders). The rest of the
// screen is static reference content (always "success"). The download control
// surfaces its own honest failure path (a screen-reader announcement, no
// crash), mirroring PdfReferenceScreen.
//
// TOKENS (GL-003 §8 / §8.20): context.colors for every color (light + dark via
// AppColorScheme), AppSpacing for gaps, AppRadius for corners, DM Mono for all
// command / code text. No literal hex, no magic spacing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../data/pdf_download.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// The share/download seam this screen calls. Defaults to the real [shareAsset]
/// (native share sheet / web anchor download); widget tests inject a fake so the
/// test never touches a platform channel. Matches the [shareAsset] signature.
typedef AssetShareFn =
    Future<void> Function({
      required String assetPath,
      required String filename,
      required String mimeType,
      ShareOrigin? shareOrigin,
    });

/// Loads the bundled script string. Injected in tests so the code block can be
/// driven to its loading / error / success states without an asset bundle.
typedef ScriptLoader = Future<String> Function();

/// Loading lifecycle for the inline script body. Drives the three explicit
/// states the code block renders.
enum _ScriptState { loading, ready, error }

/// FreeRADIUS on WLAN Pi how-to guide. A scrolling reference screen — the only
/// runtime data it touches is the bundled script asset (shown inline + offered
/// as a download); everything else is const reference content.
class FreeradiusWlanpiScreen extends StatefulWidget {
  const FreeradiusWlanpiScreen({
    this.shareFn = shareAsset,
    this.scriptLoader = _loadBundledScript,
    super.key,
  });

  /// Stable catalog id — backs the route, the §8.6.2 concept graphic
  /// (assets/tool-graphics/freeradius-wlanpi.svg), and the help entry.
  static const String toolId = 'freeradius-wlanpi';

  /// The bundled script asset — shown inline AND downloaded (same bytes).
  /// Bundled under a `.txt` extension so iOS distribution signing does not treat
  /// it as unsigned code (error 90035); the download still hands the user a file
  /// named `install_freeradius.sh` via [scriptFilename].
  static const String scriptAsset = 'assets/downloads/install_freeradius.sh.txt';

  /// The clean filename the download/share offers (the script's real name).
  static const String scriptFilename = 'install_freeradius.sh';

  /// `text/x-shellscript` so the share sheet / browser types it as a shell
  /// script rather than a generic octet-stream.
  static const String scriptMime = 'text/x-shellscript';

  /// Share/download implementation. Defaults to the real [shareAsset]; tests
  /// inject a fake so they never hit the platform channel.
  final AssetShareFn shareFn;

  /// Script-string loader. Defaults to the bundled asset; tests inject a fake to
  /// drive the loading / error / success states deterministically.
  final ScriptLoader scriptLoader;

  static Future<String> _loadBundledScript() =>
      rootBundle.loadString(scriptAsset);

  @override
  State<FreeradiusWlanpiScreen> createState() => _FreeradiusWlanpiScreenState();
}

class _FreeradiusWlanpiScreenState extends State<FreeradiusWlanpiScreen> {
  _ScriptState _state = _ScriptState.loading;
  String _script = '';

  /// Anchors the iPad/macOS share popover to the download button's on-screen
  /// rect (share_plus throws on those platforms without a source rect).
  final GlobalKey _downloadButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadScript();
  }

  Future<void> _loadScript() async {
    try {
      final String raw = await widget.scriptLoader();
      if (!mounted) return;
      setState(() {
        _script = raw;
        _state = _ScriptState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScriptState.error);
    }
  }

  /// Computes the download button's global rect for the share-popover source.
  /// Returns null if the button hasn't been laid out yet (the platform then
  /// falls back to a default anchor).
  ShareOrigin? _downloadButtonOrigin() {
    final RenderObject? box =
        _downloadButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    return ShareOrigin(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
  }

  Future<void> _handleDownload() async {
    try {
      await widget.shareFn(
        assetPath: FreeradiusWlanpiScreen.scriptAsset,
        filename: FreeradiusWlanpiScreen.scriptFilename,
        mimeType: FreeradiusWlanpiScreen.scriptMime,
        shareOrigin: _downloadButtonOrigin(),
      );
    } catch (_) {
      // Honest, quiet failure (GL-005): a screen-reader live-region
      // announcement, no crash and no SnackBar noise. The asset is bundled, so
      // this is the rare load/share-channel fault.
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Could not download the install script.',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('FreeRADIUS on WLAN Pi'),
        toolbarHeight: 64,
        // §8.16 copy action — copies the full script text to the clipboard.
        // Disabled (not focusable) until the script asset has resolved, so the
        // affordance never copies nothing. The global iconButtonTheme paints the
        // §8.3 focus ring.
        actions: <Widget>[
          AppCopyAction(
            idleLabel: 'Copy script',
            copiedLabel: 'Script copied',
            textBuilder: () => _state == _ScriptState.ready ? _script : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? AppSpacing.screenEdgeDesktop
                    : AppSpacing.screenEdgeMobile,
                vertical: AppSpacing.md,
              ),
              child: CenteredContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 1. Concept band (self-omits if the SVG is absent).
                    ConceptGraphicBand(
                      toolId: FreeradiusWlanpiScreen.toolId,
                      isDesktop: isDesktop,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 2. Intro.
                    _Intro(),
                    const SizedBox(height: AppSpacing.lg),

                    // 3. Lab-caveat banner.
                    const _LabCaution(),
                    const SizedBox(height: AppSpacing.lg),

                    // 4. Steps.
                    const _SectionHeading('Steps'),
                    const SizedBox(height: AppSpacing.sm),
                    const _Steps(),
                    const SizedBox(height: AppSpacing.md),

                    // 5. Download button.
                    _DownloadButton(
                      buttonKey: _downloadButtonKey,
                      onPressed: _handleDownload,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const _DownloadMeta(),
                    const SizedBox(height: AppSpacing.lg),

                    // 6. The script, inline + scrollable.
                    const _SectionHeading('The script'),
                    const SizedBox(height: AppSpacing.sm),
                    _ScriptBlock(state: _state, script: _script),
                    const SizedBox(height: AppSpacing.lg),

                    // 7. Customize it.
                    const _SectionHeading('Customize it'),
                    const SizedBox(height: AppSpacing.sm),
                    const _Customize(),
                    const SizedBox(height: AppSpacing.lg),

                    // 8. Useful commands.
                    const _SectionHeading('Useful commands'),
                    const SizedBox(height: AppSpacing.sm),
                    const _UsefulCommands(),

                    // 9. Help footer + credit.
                    const ToolHelpFooter(toolId: FreeradiusWlanpiScreen.toolId),
                    const _Credit(),
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

// ─────────────────────────── Intro ───────────────────────────

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        style: (text.bodyLarge ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
        ),
        children: <InlineSpan>[
          const TextSpan(text: 'Set up a working '),
          TextSpan(
            text: 'RADIUS server on a WLAN Pi',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const TextSpan(text: ' for learning and testing 802.1X.'),
        ],
      ),
    );
  }
}

// ─────────────────────── Lab-caveat banner ───────────────────────

/// The prominent lab/learning warning (GL-003 §8.13 amber in dark / §8.20.4
/// bronze in light). Never color-only — a triangle glyph + the "Lab / learning
/// setup — not production" eyebrow + the full caveat text all carry the meaning
/// (SC 1.4.1). The §8.20.4 filled-pill tint backs it on light; an amber wash on
/// dark; a left accent bar on both for emphasis.
class _LabCaution extends StatelessWidget {
  const _LabCaution();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          // Light: §8.20.4 warning tint fill. Dark: a faint amber wash (the
          // dark scheme resolves statusWarningFill to surface2, so derive the
          // wash from the warning hue directly for the on-dark callout).
          color: colors.isLight
              ? colors.statusWarningFill
              : warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: warn),
            right: BorderSide(color: warn),
            bottom: BorderSide(color: warn),
            left: BorderSide(color: warn, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 24, color: warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'LAB / LEARNING SETUP — NOT PRODUCTION',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: warn,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Test accounts and a shared secret you change before '
                    'anything real. This installs student test logins '
                    '(student01–student10) with cleartext passwords and a '
                    'shared secret named secretwlanpros. Great for learning '
                    'and testing 802.1X — change the secret and use real '
                    'credentials before using it for anything real.',
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
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

// ───────────────────────── Section heading ─────────────────────────

/// A §8.5 H3 section heading with a §8.20.2 lime underline accent bar.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: (text.headlineSmall ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Lime accent underbar — primary FILL (§8.20.2 allows lime as a fill in
        // both themes); decorative, not text, so no contrast minimum.
        Container(
          width: 42,
          height: 3,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Steps ─────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _Step(
          number: 1,
          label: 'Copy the script to the WLAN Pi',
          command: r'scp install_freeradius.sh wlanpi@<your-Pi-IP>:~',
        ),
        SizedBox(height: AppSpacing.sm),
        _Step(
          number: 2,
          label: 'Make it executable',
          command: 'chmod +x install_freeradius.sh',
        ),
        SizedBox(height: AppSpacing.sm),
        _Step(
          number: 3,
          label: 'Run it',
          command: './install_freeradius.sh',
          note: 'Installs and configures FreeRADIUS with PEAP/MSCHAPv2, adds '
              '10 student test accounts, opens UDP 1812, and runs a radtest.',
        ),
      ],
    );
  }
}

/// One numbered step: a lime mono index pill, a label, a mono command line, and
/// an optional muted note.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.label,
    required this.command,
    this.note,
  });

  final int number;
  final String label;
  final String command;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? stepNote = note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Mono index pill — lime FILL with onPrimary dark text.
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontFamily: 'DM Mono',
              fontWeight: FontWeight.w500,
              fontSize: AppTextSize.caption,
              color: colors.onPrimary,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: (text.bodyLarge ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CommandLine(command),
              if (stepNote != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  stepNote,
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Command line ───────────────────────────

/// A single-line mono command in a recessed surface2 box with a lime `$`
/// prompt. Horizontally scrollable so a long command never overflows a phone.
class _CommandLine extends StatelessWidget {
  const _CommandLine(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: 'DM Mono',
              fontSize: AppTextSize.caption,
              height: 1.5,
              color: colors.textPrimary,
            ),
            children: <InlineSpan>[
              TextSpan(
                text: r'$ ',
                style: TextStyle(color: colors.textAccent),
              ),
              TextSpan(text: command),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Download button ───────────────────────────

/// The primary "Download install_freeradius.sh" button (§8.3 primary: lime fill
/// + onPrimary text). Reuses the share/save seam the PDF cards use.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.buttonKey, required this.onPressed});

  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return SizedBox(
      height: AppSpacing.minTouchTarget,
      child: ElevatedButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTextSize.body,
          ),
        ),
        icon: const Icon(Icons.download_rounded, size: 20),
        label: const Text('Download install_freeradius.sh'),
      ),
    );
  }
}

class _DownloadMeta extends StatelessWidget {
  const _DownloadMeta();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Text(
      'shell script · ~2 KB',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'DM Mono',
        fontSize: AppTextSize.caption,
        color: colors.textTertiary,
      ),
    );
  }
}

// ─────────────────────────── Script block ───────────────────────────

/// The inline script viewer: a card with a mono header (filename + "scroll"
/// hint) and a vertically scrollable mono code body. Renders the THREE explicit
/// states of the bundled-asset load: loading (spinner), error (honest copy, no
/// retry), success (the real script bytes). The body itself is horizontally
/// scrollable too so long lines never wrap or overflow.
class _ScriptBlock extends StatefulWidget {
  const _ScriptBlock({required this.state, required this.script});

  final _ScriptState state;
  final String script;

  @override
  State<_ScriptBlock> createState() => _ScriptBlockState();
}

class _ScriptBlockState extends State<_ScriptBlock> {
  // Dedicated controller so the always-visible Scrollbar has a controller to
  // attach to (it cannot borrow the PrimaryScrollController inside a nested
  // scroll view).
  final ScrollController _vScroll = ScrollController();

  @override
  void dispose() {
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final _ScriptState state = widget.state;
    final String script = widget.script;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header bar.
          Container(
            decoration: BoxDecoration(
              color: colors.surface1,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'install_freeradius.sh',
                  style: TextStyle(
                    fontFamily: 'DM Mono',
                    fontSize: AppTextSize.caption,
                    color: colors.textSecondary,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Icon(Icons.swap_vert, size: 14, color: colors.textTertiary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'scroll',
                      style: TextStyle(
                        fontFamily: 'DM Mono',
                        fontSize: AppTextSize.caption,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Body — one of the three states.
          SizedBox(
            height: 240,
            child: switch (state) {
              _ScriptState.loading => Center(
                  child: Semantics(
                    label: 'Loading install script',
                    liveRegion: true,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.textAccent),
                      ),
                    ),
                  ),
                ),
              _ScriptState.error => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Semantics(
                      liveRegion: true,
                      label: 'The install script could not be loaded on this '
                          'device. You can still download it with the button '
                          'above.',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.description_outlined,
                            size: 40,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'The script could not be displayed here.',
                            textAlign: TextAlign.center,
                            style: (text.bodyLarge ?? const TextStyle())
                                .copyWith(color: colors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'You can still download it with the button above.',
                            textAlign: TextAlign.center,
                            style: (text.bodyMedium ?? const TextStyle())
                                .copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              _ScriptState.ready => Scrollbar(
                  controller: _vScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        script,
                        style: TextStyle(
                          fontFamily: 'DM Mono',
                          fontSize: AppTextSize.caption,
                          height: 1.55,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Customize it ───────────────────────────

class _Customize extends StatelessWidget {
  const _Customize();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CustomizeItem(
          lead: 'Change the shared secret.',
          rest: ' Edit it in ',
          path: '/etc/freeradius/3.0/clients.conf',
        ),
        SizedBox(height: AppSpacing.sm),
        _CustomizeItem(
          lead: 'Add or modify users.',
          rest: ' Edit ',
          path: '/etc/freeradius/3.0/users',
          tail: ' — usernames and passwords are case-sensitive.',
        ),
      ],
    );
  }
}

/// One "Customize" row: a bold lead phrase, plain connective text, a lime mono
/// config-file path chip, and optional trailing text.
class _CustomizeItem extends StatelessWidget {
  const _CustomizeItem({
    required this.lead,
    required this.rest,
    required this.path,
    this.tail,
  });

  final String lead;
  final String rest;
  final String path;
  final String? tail;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? trailing = tail;
    return Text.rich(
      TextSpan(
        style: (text.bodyMedium ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
        ),
        children: <InlineSpan>[
          TextSpan(
            text: lead,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          TextSpan(text: rest),
          TextSpan(
            text: path,
            style: TextStyle(
              fontFamily: 'DM Mono',
              fontSize: AppTextSize.caption,
              color: colors.textAccent,
            ),
          ),
          if (trailing != null) TextSpan(text: trailing),
        ],
      ),
    );
  }
}

// ─────────────────────────── Useful commands ───────────────────────────

class _UsefulCommands extends StatelessWidget {
  const _UsefulCommands();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CommandLine('sudo systemctl status freeradius.service'),
        SizedBox(height: AppSpacing.xs),
        _CommandLine('sudo journalctl -fu freeradius'),
        SizedBox(height: AppSpacing.xs),
        _CommandLine('sudo tcpdump -i eth0 -n udp port 1812'),
        SizedBox(height: AppSpacing.xs),
        _CommandLine('radtest student01 password01 localhost 0 secretwlanpros'),
      ],
    );
  }
}

// ───────────────────────────── Credit ─────────────────────────────

class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          style: (text.bodyMedium ?? const TextStyle()).copyWith(
            color: colors.textTertiary,
          ),
          children: <InlineSpan>[
            const TextSpan(text: 'Guide and install script by '),
            TextSpan(
              text: 'Ferney Munoz',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
