// The "Download PDF" control for an in-tool graphic that has a bundled PDF twin.
//
// ONE control, ONE definition. It is used by LargeGraphic (the zoomable face
// cards) and by naming_conventions_screen's bit-field band, which renders its
// graphic through a bespoke band rather than LargeGraphic. Two copies of a
// download button is how they drift apart, and this one carries an a11y contract
// and a 44pt target that a copy would quietly lose.
//
// Keith picked four graphics of 125 on 2026-07-30, so the common case on any
// screen is that this never renders at all. Callers gate on GraphicPdfs.has().

import 'package:flutter/material.dart';

import '../data/graphic_pdfs.dart';
import '../data/pdf_download.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The share/download seam, injectable so a widget test never touches a platform
/// channel. Mirrors [sharePdf]'s signature exactly, the same pattern
/// `pdf_reference_screen.dart` uses for the reference cards.
typedef GraphicPdfShareFn =
    Future<void> Function({
      required String assetPath,
      required String title,
      ShareOrigin? shareOrigin,
    });

/// Default seam. Overridable per-instance in tests.
GraphicPdfShareFn shareGraphicPdf = sharePdf;

/// "Download PDF" control under a [LargeGraphic] that has a bundled PDF twin.
///
/// Deliberately a labelled text button rather than a bare glyph. The zoom
/// affordance above it is already an icon, and two unlabelled icons on one card
/// is a guessing game. The label also tells a screen-reader user what they get,
/// which "icon button" does not.
class GraphicPdfDownload extends StatelessWidget {
  const GraphicPdfDownload({
    super.key,
    required this.assetName,
    required this.onShare,
  });

  final String assetName;
  final GraphicPdfShareFn onShare;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final String? assetPath = GraphicPdfs.path(assetName);
    final String? title = GraphicPdfs.title(assetName);
    // Belt and braces: the caller already checked `has`, but a null here would
    // otherwise crash on a bad map entry rather than degrade.
    if (assetPath == null || title == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => onShare(
          assetPath: assetPath,
          title: title,
          shareOrigin: null,
        ),
        icon: Icon(Icons.download_outlined, size: 20, color: colors.textSecondary),
        label: Text(
          'Download PDF',
          style: TextStyle(color: colors.textSecondary),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44), // 44pt touch target, GL-003
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      ),
    );
  }
}
