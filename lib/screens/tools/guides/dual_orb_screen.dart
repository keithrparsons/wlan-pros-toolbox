// Dual Orbs on WLAN Pi — a how-to / guide screen (v1.1).
//
// Turns a WLAN Pi R4/M4+ into TWO Orb sensors (one on Ethernet, one on Wi-Fi)
// by installing the bundled `wlanpi-dual-orb_1.1.3_all.deb` (bundled in-app as
// `wlanpi-dual-orb_1.1.3_all.deb.bin` for iOS signing; downloads under the real
// `.deb` name). This screen renders
// the approved preview (Deliverables/2026-06-05-dual-orb-wlanpi/mockup, dark +
// light): a concept band, an intro line, an ACCURATE caveat box, the numbered
// install steps (scp / apt install / reboot), the cloned-image identity-reset
// note, the reconfigure-Wi-Fi note, a useful-commands list, link-outs to Orb and
// the WLAN Pi project, and a credit line for Ferney Munoz.
//
// LICENSING ACCURACY (Keith, 2026-06-05 + GL-005): we distribute NOTHING of
// Orb's. The bundled `.deb` is the open-source dual-Orb sensor packaging by
// Ferney Munoz; it installs the FREE, open-source Orb sensor agent on the Pi and
// runs its services as root. The user views results in their OWN Orb account
// (free for up to 5 devices). The caveat box states exactly that — no more, no
// fewer claims (the truthfulness rule).
//
// PRIMARY ACTION: a "Download wlanpi-dual-orb.deb" button that reuses the app's
// existing bundled-asset share/download seam (lib/data/pdf_download.dart →
// shareAsset), the SAME mechanism the PDF reference cards use. On native it
// copies the bundled bytes to a temp file under the real package filename and
// hands it to the OS share sheet (Save-to-Files / AirDrop / Mail); on web it
// triggers a browser anchor download. The filename is the REAL package name
// (`wlanpi-dual-orb_1.1.3_all.deb`) because it is meaningful to the install
// command — it is NOT slugified.
//
// TOKENS (GL-003 §8): surface0 canvas + app bar, surface1 cards/code blocks,
// surface2 inline-code chips, border hairlines, borderStrong code-block outline,
// textPrimary/Secondary/Tertiary ramp, primary lime fill (download button + step
// numerals + section underline), textAccent foreground lime (light-safe), the
// §8.13/§8.20.1 warning status for the caveat box, AppSpacing / AppRadius
// throughout. Every value reads from `context.colors` so the screen renders
// correctly in BOTH themes (no hardcoded hex / px). DM Mono for every CLI line.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/pdf_download.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';

/// The share/download seam this screen calls. Defaults to the real [shareAsset]
/// (native share sheet / web anchor download); widget tests inject a fake so the
/// test never touches a platform channel. Matches the [shareAsset] signature.
typedef AssetShareFn =
    Future<void> Function({
      required String assetPath,
      required String filename,
      required String mimeType,
      required String title,
      ShareOrigin? shareOrigin,
    });

/// Bundled package asset path (declared in pubspec.yaml). Bundled under a `.bin`
/// extension so iOS distribution signing does not treat the `.deb` as unsigned
/// code (error 90035); the download still hands the user a file named
/// `wlanpi-dual-orb_1.1.3_all.deb` via [kDualOrbDebFilename].
const String kDualOrbAssetPath =
    'assets/downloads/wlanpi-dual-orb_1.1.3_all.deb.bin';

/// The real package filename — meaningful to the install command, never
/// slugified.
const String kDualOrbDebFilename = 'wlanpi-dual-orb_1.1.3_all.deb';

/// Debian package MIME type for the share sheet.
const String kDebMimeType = 'application/vnd.debian.binary-package';

/// "Dual Orbs on WLAN Pi" how-to guide. Static content + one download action;
/// the only runtime state is the share-failure path (announced, never a crash).
class DualOrbScreen extends StatefulWidget {
  const DualOrbScreen({this.shareFn = shareAsset, super.key});

  /// Share/download implementation. Defaults to the real [shareAsset]; tests
  /// inject a fake so they never hit the platform channel.
  final AssetShareFn shareFn;

  @override
  State<DualOrbScreen> createState() => _DualOrbScreenState();
}

class _DualOrbScreenState extends State<DualOrbScreen> {
  /// Anchors the iPad/macOS share popover to the button's on-screen rect
  /// (share_plus throws on those platforms without a source rect).
  final GlobalKey _downloadButtonKey = GlobalKey();

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
        assetPath: kDualOrbAssetPath,
        filename: kDualOrbDebFilename,
        mimeType: kDebMimeType,
        title: 'WLAN Pi Dual Orb package',
        shareOrigin: _downloadButtonOrigin(),
      );
    } catch (_) {
      // Honest, quiet failure (§8.16 / GL-005): a screen-reader live-region
      // announcement, no crash and no SnackBar noise. The asset is bundled, so
      // this is the rare load/share-channel fault, not a routine empty state.
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Could not share the dual-Orb package.',
        TextDirection.ltr,
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dual Orbs on WLAN Pi'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: CenteredContent(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _ConceptBand(),
                  const SizedBox(height: AppSpacing.md),
                  const _Intro(),
                  const SizedBox(height: AppSpacing.md),
                  const _CaveatBox(),

                  // ── Download ─────────────────────────────────────────────
                  const SizedBox(height: AppSpacing.lg),
                  _DownloadButton(
                    buttonKey: _downloadButtonKey,
                    onPressed: _handleDownload,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const _DownloadMeta(),

                  // ── Steps ────────────────────────────────────────────────
                  const _SectionHeading('Install'),
                  const _Steps(),

                  // ── Cloned-image reset ───────────────────────────────────
                  const _SectionHeading('Cloned a WLAN Pi image?'),
                  const _ClonedImageNote(),

                  // ── Reconfigure Wi-Fi ────────────────────────────────────
                  const _SectionHeading('Change the Wi-Fi credentials'),
                  const _ReconfigureNote(),

                  // ── Useful commands ──────────────────────────────────────
                  const _SectionHeading('Useful commands'),
                  const _UsefulCommands(),

                  // ── Links ────────────────────────────────────────────────
                  const _SectionHeading('Learn more'),
                  _Links(onOpen: _openUrl),

                  // ── Credit ───────────────────────────────────────────────
                  const SizedBox(height: AppSpacing.lg),
                  _Credit(textColor: colors.textTertiary),

                  // §8.16.1 — per-tool help footer. Self-omits if no entry.
                  const ToolHelpFooter(toolId: 'dual-orb-wlanpi'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Concept band ─────────────────────────────────────

/// A flat line illustration of the concept: one WLAN Pi feeding two Orb sensors
/// (Ethernet + Wi-Fi). Decorative; excluded from semantics (the intro carries
/// the meaning).
class _ConceptBand extends StatelessWidget {
  const _ConceptBand();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        height: 108,
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _ConceptPainter(
            board: colors.textTertiary,
            link: colors.statusInfo,
            orb: colors.textAccent,
          ),
        ),
      ),
    );
  }
}

class _ConceptPainter extends CustomPainter {
  const _ConceptPainter({
    required this.board,
    required this.link,
    required this.orb,
  });

  final Color board;
  final Color link;
  final Color orb;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    final double cx = size.width / 2;

    final Paint boardStroke = Paint()
      ..color = board
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final Paint orbStroke = Paint()
      ..color = orb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final Paint orbFill = Paint()..color = orb;
    final Paint linkPaint = Paint()
      ..color = link
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // WLAN Pi board in the center.
    final Rect boardRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: 70,
      height: 44,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(6)),
      boardStroke,
    );
    // little chip + LED on the board.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(boardRect.left + 10, cy - 12, 18, 12),
        const Radius.circular(2),
      ),
      Paint()
        ..color = board
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(Offset(boardRect.right - 12, cy + 8), 3.2, orbFill);

    // Two Orb sensor circles (left = Ethernet, right = Wi-Fi).
    final Offset ethCenter = Offset(boardRect.left - 78, cy);
    final Offset wifiCenter = Offset(boardRect.right + 78, cy);
    canvas.drawCircle(ethCenter, 16, orbStroke);
    canvas.drawCircle(wifiCenter, 16, orbStroke);
    // inner orb dots
    canvas.drawCircle(ethCenter, 4, orbFill);
    canvas.drawCircle(wifiCenter, 4, orbFill);

    // Ethernet link: solid line from board to the left Orb.
    canvas.drawLine(
      Offset(boardRect.left, cy),
      Offset(ethCenter.dx + 16, cy),
      linkPaint,
    );

    // Wi-Fi link: dashed line from board to the right Orb (radio = not a wire).
    const double dash = 5;
    const double gap = 4;
    double x = boardRect.right;
    final double endX = wifiCenter.dx - 16;
    while (x < endX) {
      final double xEnd = (x + dash).clamp(x, endX);
      canvas.drawLine(Offset(x, cy), Offset(xEnd, cy), linkPaint);
      x += dash + gap;
    }
    // Wi-Fi arcs over the right Orb.
    for (int i = 1; i <= 2; i++) {
      final double r = 22.0 + i * 7;
      canvas.drawArc(
        Rect.fromCircle(center: wifiCenter, radius: r),
        -2.7,
        1.0,
        false,
        orbStroke,
      );
    }
  }

  @override
  bool shouldRepaint(_ConceptPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.link != link ||
      oldDelegate.orb != orb;
}

// ───────────────────────── Intro ────────────────────────────────────────────

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle base =
        (text.bodyLarge ?? const TextStyle()).copyWith(color: colors.textSecondary);
    final TextStyle strong = base.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          const TextSpan(text: 'Turn a '),
          TextSpan(text: 'WLAN Pi R4 or M4+', style: strong),
          const TextSpan(
            text: ' into two Orb sensors — one testing your wired '
                'connection over ',
          ),
          TextSpan(text: 'Ethernet', style: strong),
          const TextSpan(text: ', one testing your '),
          TextSpan(text: 'Wi-Fi', style: strong),
          const TextSpan(
            text: '. Tested on both the R4 and the M4+.',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Caveat box ───────────────────────────────────────

/// The §8.13 / §8.20.1 amber warning callout — never color-only (carries an
/// eyebrow label + body text). States exactly what the install does, no more.
class _CaveatBox extends StatelessWidget {
  const _CaveatBox();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    final TextStyle body =
        (text.bodyMedium ?? const TextStyle()).copyWith(color: colors.textSecondary);
    final TextStyle code =
        (Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults())
            .inlineCode
            .copyWith(fontSize: AppTextSize.caption, color: colors.textPrimary);

    InlineSpan chip(String s) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(s, style: code),
          ),
        );

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.statusWarningFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: warn),
            right: BorderSide(color: warn),
            bottom: BorderSide(color: warn),
            left: BorderSide(color: warn, width: 6),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 22, color: warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'WHAT THIS INSTALLS',
                    style: (text.labelSmall ?? const TextStyle()).copyWith(
                      color: warn,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08 * (text.labelSmall?.fontSize ?? 12),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text.rich(
                    TextSpan(
                      style: body,
                      children: <InlineSpan>[
                        const TextSpan(
                          text: 'This installs the free, open-source Orb '
                              'sensor on the Pi and runs its services as ',
                        ),
                        chip('root'),
                        const TextSpan(
                          text: '. You view the results in your own Orb '
                              'account, free for up to 5 devices. Nothing of '
                              "Orb's is bundled here — the package just sets "
                              'the sensor up for you.',
                        ),
                      ],
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

// ───────────────────────── Section heading ──────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              label,
              style: (text.headlineSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Lime underline accent (FILL — §8.20.2 allows lime as a fill on light).
          Container(
            width: 42,
            height: 3,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Steps ────────────────────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _Step(
          number: 1,
          label: 'Copy the package to the WLAN Pi',
          command:
              'scp wlanpi-dual-orb_1.1.3_all.deb wlanpi@<your-Pi-IP>:~',
        ),
        SizedBox(height: AppSpacing.sm),
        _Step(
          number: 2,
          label: 'SSH to the Pi and install it',
          command: 'sudo apt install ./wlanpi-dual-orb_1.1.3_all.deb',
          note:
              'Prompts for the Wi-Fi SSID, password, and encryption, then '
              'configures everything.',
        ),
        SizedBox(height: AppSpacing.sm),
        _Step(
          number: 3,
          label: 'Reboot',
          command: 'sudo reboot',
          note:
              'orb-install.service runs on boot, installs Orb, and starts both '
              'sensors.',
        ),
      ],
    );
  }
}

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
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Numeral chip — lime fill, onPrimary text (theme-safe in both modes).
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
              style:
                  (Theme.of(context).extension<AppMonoText>() ??
                          AppMonoText.defaults())
                      .inlineCode
                      .copyWith(
                        fontSize: AppTextSize.caption,
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w500,
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
                if (note != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    note!,
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Command line ─────────────────────────────────────

/// A single monospaced CLI command on a recessed surface, with a lime `$`
/// prompt. Horizontally scrollable so long commands never wrap or clip. The
/// command text is selectable so a user can copy it.
class _CommandLine extends StatelessWidget {
  const _CommandLine(this.command, {this.inComment});

  final String command;

  /// Optional trailing `# comment` rendered tertiary (for the useful-commands
  /// list, where each line documents what it does).
  final String? inComment;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle cmdStyle = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText.rich(
          TextSpan(
            style: cmdStyle,
            children: <InlineSpan>[
              TextSpan(
                text: '\$ ',
                style: cmdStyle.copyWith(color: colors.textAccent),
              ),
              TextSpan(text: command),
              if (inComment != null)
                TextSpan(
                  text: '  # $inComment',
                  style: cmdStyle.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

// ───────────────────────── Download button + meta ───────────────────────────

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.buttonKey, required this.onPressed});

  final GlobalKey buttonKey;
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
        ),
        icon: const Icon(Icons.download_rounded, size: 20),
        label: const Text('Download wlanpi-dual-orb.deb'),
      ),
    );
  }
}

class _DownloadMeta extends StatelessWidget {
  const _DownloadMeta();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Center(
      child: Text(
        'Debian package · v1.1.3 · ~12 KB',
        style: mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

// ───────────────────────── Cloned-image note ────────────────────────────────

class _ClonedImageNote extends StatelessWidget {
  const _ClonedImageNote();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'A cloned image keeps the Orb IDs and hostnames of the original. If '
          'several WLAN Pis share one image, reset the identity on each so the '
          'Orb dashboard sees a new sensor. This creates fresh Orb IDs and '
          'names from the WLAN Pi hostname.',
          style: (text.bodyMedium ?? const TextStyle())
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _CommandLine('sudo orb-reset-identity'),
        const SizedBox(height: AppSpacing.xs),
        const _CommandLine(
          'sudo orb-reset-identity --dry-run',
          inComment: 'shows what would change, makes no changes',
        ),
      ],
    );
  }
}

// ───────────────────────── Reconfigure note ─────────────────────────────────

class _ReconfigureNote extends StatelessWidget {
  const _ReconfigureNote();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Re-run the Wi-Fi setup to change the SSID, password, or encryption '
          'for the Wi-Fi sensor.',
          style: (text.bodyMedium ?? const TextStyle())
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _CommandLine('sudo orb-wifi-configure'),
      ],
    );
  }
}

// ───────────────────────── Useful commands ──────────────────────────────────

class _UsefulCommands extends StatelessWidget {
  const _UsefulCommands();

  static const List<({String cmd, String note})> _commands =
      <({String cmd, String note})>[
    (cmd: 'sudo systemctl status orb.service', note: 'Ethernet Orb status'),
    (
      cmd: 'sudo systemctl status orb-wifi-sensor.service',
      note: 'Wi-Fi Orb status'
    ),
    (cmd: 'sudo journalctl -fu orb', note: 'live Ethernet Orb logs'),
    (
      cmd: 'sudo journalctl -fu orb-wifi-sensor',
      note: 'live Wi-Fi Orb logs'
    ),
    (cmd: 'sudo orb-wifi-configure', note: 'change Wi-Fi credentials'),
    (cmd: 'sudo systemctl daemon-reload', note: 'reload systemd config'),
    (cmd: 'sudo systemctl restart orb.service', note: 'restart Ethernet Orb'),
    (
      cmd: 'sudo systemctl restart orb-wifi-sensor.service',
      note: 'restart Wi-Fi Orb'
    ),
    (
      cmd: 'sudo orb-reset-identity',
      note: 'new Orb IDs on cloned images'
    ),
    (cmd: 'sudo ip netns exec orb-wifi iw dev', note: 'iw dev in orb-wifi ns'),
    (
      cmd: 'sudo ip netns exec orb-wifi ip link show',
      note: 'ip link in orb-wifi ns'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < _commands.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: AppSpacing.xs));
      rows.add(_CommandLine(_commands[i].cmd, inComment: _commands[i].note));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

// ───────────────────────── Links ────────────────────────────────────────────

class _Links extends StatelessWidget {
  const _Links({required this.onOpen});

  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LinkRow(
          label: 'Orb — orb.net',
          subtitle: 'Create your free Orb account (up to 5 devices)',
          url: 'https://orb.net',
          onOpen: onOpen,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LinkRow(
          label: 'WLAN Pi project',
          subtitle: 'The open-source WLAN Pi platform',
          url: 'https://www.wlanpi.com',
          onOpen: onOpen,
        ),
      ],
    );
  }
}

// A bare InkWell suppresses Material's default focus highlight here (the app
// theme sets focusColor transparent, §8.3), so this row carried NO visible
// keyboard focus indicator (SC 2.4.7 gap). Like _FooterButton in
// lib/widgets/tool_help_footer.dart, _LinkRow is a custom composite that cannot
// inherit the global iconButtonTheme ring, so it self-paints the §8.3 lime focus
// ring via FocusableActionDetector — 2px brand lime in dark, 3px darkened-lime
// textAccent in light (§8.20.2 / §8.20.3-B). Focus-only; no at-rest change.
class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.label,
    required this.subtitle,
    required this.url,
    required this.onOpen,
  });

  final String label;
  final String subtitle;
  final String url;
  final Future<void> Function(String url) onOpen;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${widget.label}. Opens in browser.',
      child: FocusableActionDetector(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen(widget.url);
              return null;
            },
          ),
        },
        onShowFocusHighlight: (bool value) {
          if (value != _focused) setState(() => _focused = value);
        },
        child: Container(
          // §8.3 focus ring drawn as a foreground decoration so it never disturbs
          // the row's resting render: 2px brand lime in dark, 3px darkened-lime
          // textAccent in light (§8.20.2 / §8.20.3-B). Focus-only.
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: colors.isLight ? colors.textAccent : colors.primary,
                    width: colors.isLight ? 3 : 2,
                  ),
                )
              : null,
          child: Material(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => widget.onOpen(widget.url),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.rowPadding,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.label,
                              style: (text.bodyLarge ?? const TextStyle())
                                  .copyWith(
                                color: colors.textAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              widget.subtitle,
                              style: (text.bodySmall ?? const TextStyle())
                                  .copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.open_in_new,
                          size: 20, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Credit ───────────────────────────────────────────

class _Credit extends StatelessWidget {
  const _Credit({required this.textColor});

  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Center(
      child: Text.rich(
        TextSpan(
          style: (text.bodyMedium ?? const TextStyle()).copyWith(color: textColor),
          children: <InlineSpan>[
            const TextSpan(text: 'Guide and package by '),
            TextSpan(
              text: 'Ferney Munoz',
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
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
