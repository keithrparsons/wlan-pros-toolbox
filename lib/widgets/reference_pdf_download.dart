// "Download PDF" (save/share) control for the Field & Trade Reference plates.
//
// Every field-reference screen (and the LED Decoder's master comparison plate)
// ships its Vera-passed print plate as a bundled vector PDF
// (assets/reference-pdf/<tool-id>.pdf, resolved by [ReferencePdfs]). This is the
// clear, labeled control that lets the user SAVE or SHARE that full-resolution
// plate — for print, AirDrop, Mail, or Save-to-Files.
//
// It reuses the app's EXISTING PDF seam (pdf_download.dart -> sharePdf), the same
// path the PDF reference cards and the FreeRADIUS download use:
//   * native (iOS / macOS / Android / Windows): copies the bundled bytes to a
//     temp file under a clean human filename and hands it to the OS share sheet;
//   * web: an anchor download of the same bytes under the clean filename.
// No new share mechanism is invented here — this is a thin, labeled trigger.
//
// GRACEFUL DEGRADATION: the control is only ever rendered when the plate PDF is
// actually bundled (the screen gates on ReferencePdfs.isBundled). If the share
// channel itself fails at tap time (the rare bundled-asset load / platform-
// channel fault), it fails HONESTLY (GL-005): a screen-reader live-region
// announcement, no crash and no SnackBar noise — mirroring PdfReferenceScreen and
// the FreeRADIUS download.
//
// STATES (SOP-007 §5): this is a static, always-present trigger for a bundled
// asset — there is no loading/empty state (the PDF is in the bundle). The states
// it owns are: success (tap -> share sheet / download), error (honest failure
// announcement), and interactive (hover + keyboard focus with the §8.3 lime ring,
// matching ReferencePickerRow). It is never disabled — a bundled plate is always
// shareable; when the plate is NOT bundled the screen omits the control entirely.
//
// TOKENS (GL-003 §8 / §8.20): every color from context.colors (dark §8 / light
// §8.20), every gap/size/radius from AppSpacing / AppRadius. Lime is a FOREGROUND
// ring here, so light substitutes the darkened-lime textAccent and bumps the ring
// to 3px (§8.20.2 / §8.20.3-B), exactly as ReferencePickerRow and AppToggle do.
// No hardcoded color, size, or spacing literal.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/pdf_download.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The share/download seam this control calls. Defaults to the real [sharePdf]
/// (native share sheet / web anchor download); widget tests inject a fake so the
/// test never touches a platform channel. Matches the [sharePdf] signature.
typedef PdfShareFn =
    Future<void> Function({
      required String assetPath,
      required String title,
      ShareOrigin? shareOrigin,
    });

/// A clear, labeled "Download PDF" control for a bundled reference plate.
///
/// Pass the bundled [assetPath] (`assets/reference-pdf/<id>.pdf`, via
/// [ReferencePdfs.pathFor]) and a human [title] — the title drives the clean
/// download filename (`WLAN-Pros-<slug>.pdf`, via [pdfDownloadFilename]) and the
/// spoken control label. [subtitle] overrides the default supporting line.
///
/// The caller is responsible for only rendering this when the PDF is bundled
/// (`ReferencePdfs.isBundled(id)`), so this control never points at a missing
/// asset.
class ReferencePdfDownloadCard extends StatefulWidget {
  const ReferencePdfDownloadCard({
    super.key,
    required this.assetPath,
    required this.title,
    this.subtitle = 'Save or share the full reference plate',
    this.shareFn = sharePdf,
  });

  /// Bundled asset path, e.g. `assets/reference-pdf/enclosure-ratings.pdf`.
  final String assetPath;

  /// Human plate title — drives the clean download filename and the label.
  final String title;

  /// Supporting line under the "Download PDF" label.
  final String subtitle;

  /// Share/download implementation. Defaults to the real [sharePdf]; tests inject
  /// a fake so they never hit the platform channel.
  final PdfShareFn shareFn;

  @override
  State<ReferencePdfDownloadCard> createState() =>
      _ReferencePdfDownloadCardState();
}

class _ReferencePdfDownloadCardState extends State<ReferencePdfDownloadCard> {
  bool _focused = false;

  /// Anchors the iPad/macOS share popover to this control's on-screen rect
  /// (share_plus throws on those platforms without a source rect).
  final GlobalKey _buttonKey = GlobalKey();

  /// Computes the control's global rect for the share-popover source. Returns
  /// null if it hasn't been laid out yet (the platform then picks a default).
  ShareOrigin? _origin() {
    final RenderObject? box = _buttonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    return ShareOrigin(topLeft.dx, topLeft.dy, box.size.width, box.size.height);
  }

  Future<void> _handleDownload() async {
    try {
      await widget.shareFn(
        assetPath: widget.assetPath,
        title: widget.title,
        shareOrigin: _origin(),
      );
    } catch (_) {
      // Honest, quiet failure (GL-005): a screen-reader live-region
      // announcement, no crash and no SnackBar noise. The asset is bundled, so
      // this is the rare load / share-channel fault.
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Could not download the PDF.',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // §8.3 focus ring vs §8.1 interactive boundary at rest (matches
    // ReferencePickerRow so the two interactive rows read identically).
    final Border rowBorder = _focused
        ? Border.all(
            color: colors.isLight ? colors.textAccent : colors.primary,
            width: colors.isLight ? 3 : 2,
          )
        : Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          );

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: 'Download PDF. ${widget.subtitle}',
      child: Material(
        key: _buttonKey,
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _handleDownload,
          onFocusChange: (bool hasFocus) {
            if (hasFocus != _focused) setState(() => _focused = hasFocus);
          },
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Lime-tinted leading affordance — the download glyph. The label
                // beside it carries the meaning, so the icon is decorative.
                Icon(
                  Icons.file_download_outlined,
                  size: 24,
                  color: colors.textAccent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Download PDF',
                        style: (text.bodyLarge ?? const TextStyle()).copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: text.labelMedium?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // A small mono "PDF" meta chip — reinforces the format without a
                // second interactive target.
                Text(
                  'PDF',
                  style: TextStyle(
                    fontFamily: 'DM Mono',
                    fontSize: AppTextSize.caption,
                    color: colors.textTertiary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
