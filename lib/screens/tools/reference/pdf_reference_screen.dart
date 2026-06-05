// PDF reference card — one reusable screen for all 10 of Keith's laminated
// reference cards (Excel→PDF exports bundled under assets/reference-cards/).
//
// These are print-format cards, not in-app data tables. They are bundled as
// PDFs and rendered offline in a pinch-zoomable viewer (pdfx → Apple PDFKit on
// iOS + macOS — the two platforms the Toolbox ships first). No network, no
// computation, no platform-data: the asset is in the bundle, so the only states
// are loading (while PDFKit opens the document), error (asset failed to open),
// and success (the viewer paints). There is no empty state — a bundled card
// always has at least one page.
//
// The squeeze (corrected root cause, verified 2026-06-01): `bubble-diagram.pdf`
// is a SINGLE page with a portrait MediaBox (612×792) carrying a `/Rotate 90`
// flag — it is the ONLY rotated card; the other "landscape" cards have native
// landscape MediaBoxes (792×612, no rotate). The squeeze was never a multi-page
// seeding problem. It was page-rotation handling: a 612×792 page that must be
// presented as 792×612.
//
// Viewer choice (2026-06-01): we use pdfx's `PdfView` (PhotoView-backed), NOT
// `PdfViewPinch`. The difference that fixes the rotated card is in how each
// viewer sizes the page box:
//   - `PdfViewPinch` lays each page out from the REPORTED `PdfPageImage`
//     dimensions. On the Apple path the plugin reports the *requested* render
//     size in MediaBox order (1530×1980, portrait) even though the native
//     renderer correctly produces a landscape raster — so the landscape image
//     gets squeezed into a portrait box.
//   - `PdfView` feeds the raw PNG bytes to `PdfPageImageProvider`, which DECODES
//     them, and PhotoView fit-contains the DECODED image
//     (`PhotoViewComputedScale.contained`). The decoded raster is the ground
//     truth (1980×1530, landscape), so the rotated card paints undistorted.
//
// Objective evidence (integration_test/pdf_rotation_probe_test.dart, macOS):
// decoded PNG bytes are bubble-diagram 1980×1530 (LANDSCAPE, aspect 1.294),
// channel-allocations-5ghz 1980×1530 (native landscape, unchanged), and
// top-20-checklist 1530×1980 (PORTRAIT, unchanged). Aspect is correct for all
// three orientations.
//
// One screen class, parameterized by `title` + `assetPath`, wired once per card
// in app_router.dart. The catalog id → asset file mapping lives in the router /
// catalog, not here.
//
// Accessibility: the screen is wrapped in a Semantics node naming the document
// and the gesture ("Pinch to zoom"). The PDF's INNER content is rasterized by
// PDFKit and is NOT screen-reader readable — an inherent limitation of rendering
// a flat print PDF, not something this screen can fix. The screen label is the
// honest, clear thing we can do (GL-005): name the card, state the interaction.
//
// Tokens (GL-003 §8): surface0 canvas + app-bar, surface1 viewer backdrop,
// primary spinner, textPrimary/textSecondary for the error copy, AppSpacing for
// gaps. No hardcoded colors or sizes.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:pdfx/pdfx.dart';

import '../../../data/pdf_download.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';

/// The share/download seam this screen calls. Defaults to the real [sharePdf]
/// (native share sheet / web anchor download); widget tests inject a fake so the
/// test never touches a platform channel. Matches the [sharePdf] signature.
typedef PdfShareFn =
    Future<void> Function({
      required String assetPath,
      required String title,
      ShareOrigin? shareOrigin,
    });

/// Loading lifecycle for the bundled document. Drives which of the three
/// explicit states the scaffold body renders.
enum _PdfLoadState { loading, ready, error }

/// Renders one PDF page to a PNG raster for the pinch-viewer.
///
/// Sizing detail that matters for `/Rotate` pages: on the Apple (iOS + macOS)
/// path, pdfx's [PdfPage.width]/[PdfPage.height] return the raw **MediaBox**
/// dimensions and ignore the page's `/Rotate` flag. The native renderer DOES
/// honor `/Rotate` — for a 90°/270° page it swaps the bitmap to landscape — but
/// it derives that swap purely from the rotation flag, independent of the
/// width/height we pass. So passing MediaBox-order `width`/`height` is correct:
/// a 612×792 (`/Rotate 90`) page renders to a landscape raster, while a native
/// 792×612 (no rotate) page and a 612×792 portrait page render at their true
/// aspect. PhotoView then fit-contains the DECODED raster (it reads the real
/// pixel bytes, not the reported dimensions), so every card paints undistorted.
///
/// 2.5× for crispness on the detailed cards. White page background matches the
/// white print stock; the surrounding letterbox stays the dark `surface1`
/// backdrop set on the viewer.
Future<PdfPageImage?> renderReferencePage(PdfPage page) => page.render(
      width: page.width * 2.5,
      height: page.height * 2.5,
      format: PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
    );

/// A single bundled PDF reference card, rendered pinch-zoomable.
///
/// Reused for every "PDF reference card" tool — pass the card [title] (shown in
/// the app bar and the Semantics label), the bundled [assetPath]
/// (`assets/reference-cards/<id>.pdf`), and the catalog [toolId] of the SPECIFIC
/// card so the help action resolves that card's help entry, not a generic one.
class PdfReferenceScreen extends StatefulWidget {
  const PdfReferenceScreen({
    required this.title,
    required this.assetPath,
    required this.toolId,
    this.shareFn = sharePdf,
    super.key,
  });

  /// Card title — app-bar title and the spoken document name.
  final String title;

  /// Bundled asset path, e.g. `assets/reference-cards/bubble-diagram.pdf`.
  final String assetPath;

  /// Catalog id of the specific card being shown (e.g. `top-20-checklist`,
  /// `mcs-index-card`). Drives the per-card help action; the icon self-hides if
  /// no help entry exists for the id.
  final String toolId;

  /// Share/download implementation. Defaults to the real [sharePdf]; tests
  /// inject a fake so they never hit the platform channel.
  final PdfShareFn shareFn;

  @override
  State<PdfReferenceScreen> createState() => _PdfReferenceScreenState();
}

class _PdfReferenceScreenState extends State<PdfReferenceScreen> {
  late final PdfController _controller;
  _PdfLoadState _state = _PdfLoadState.loading;

  /// Anchors the iPad/macOS share popover to the share button's on-screen rect
  /// (share_plus throws on those platforms without a source rect).
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Computes the share button's global rect for the share-popover source.
  /// Returns null if the button hasn't been laid out yet (the platform then
  /// falls back to a default anchor).
  ShareOrigin? _shareButtonOrigin() {
    final RenderObject? box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    return ShareOrigin(
      topLeft.dx,
      topLeft.dy,
      box.size.width,
      box.size.height,
    );
  }

  Future<void> _handleShare() async {
    try {
      await widget.shareFn(
        assetPath: widget.assetPath,
        title: widget.title,
        shareOrigin: _shareButtonOrigin(),
      );
    } catch (_) {
      // Honest, quiet failure (§8.16 / GL-005): a screen-reader live-region
      // announcement, no crash and no SnackBar noise. The asset is bundled, so
      // this is the rare load/share-channel fault, not a routine empty state.
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Could not share this reference card.',
        TextDirection.ltr,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openAsset(widget.assetPath),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(PdfDocument _) {
    if (!mounted) return;
    setState(() => _state = _PdfLoadState.ready);
  }

  void _onError(Object _) {
    if (!mounted) return;
    setState(() => _state = _PdfLoadState.error);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        toolbarHeight: 64,
        // Share/download is now the only AppBar action (§8.16). The per-card
        // help moved to the ToolHelpFooter (§8.16.1) below the viewer — this is
        // a full-bleed non-scrolling PDF surface, so the footer is pinned as the
        // trailing row beneath the viewer rather than appended to a scroll body
        // (special case, see the build session log). The global iconButtonTheme
        // paints the §8.3 lime focus ring on the bare share IconButton.
        actions: <Widget>[
          IconButton(
            key: _shareButtonKey,
            onPressed: _handleShare,
            iconSize: 24,
            tooltip: 'Share or download',
            icon: Icon(
              Icons.ios_share,
              size: 24,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Semantics(
                // PDF inner content is rasterized and not SR-readable; the
                // screen label is the honest description of what this surface is
                // and how to use it.
                label: '${widget.title} reference card. Pinch to zoom.',
                // The pinch-viewer is a custom gesture surface, not a labelled
                // control — exclude its inner semantics so the one screen-level
                // label reads cleanly.
                explicitChildNodes: false,
                child: _body(context),
              ),
            ),
            // §8.16.1 — per-card help, pinned beneath the full-bleed viewer
            // (this screen has no scroll body). Self-omits when the card id has
            // no authored help entry.
            ToolHelpFooter(toolId: widget.toolId),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // The viewer is always mounted so its load callbacks fire; the loading and
    // error overlays sit on top of it until the document resolves. PhotoView
    // fit-contains the DECODED raster, so each page (including the `/Rotate 90`
    // bubble diagram) paints at its true aspect ratio.
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: PdfView(
            controller: _controller,
            renderer: renderReferencePage,
            onDocumentLoaded: _onLoaded,
            onDocumentError: _onError,
            // Dark, token-based backdrop for the letterbox around each page —
            // the default is a light gray that clashes with App Mode
            // (GL-003 §8.1).
            backgroundDecoration:
                BoxDecoration(color: colors.surface1),
            builders: PdfViewBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => _LoadingState(),
              pageLoaderBuilder: (_) => _LoadingState(),
              errorBuilder: (_, _) => const _ErrorState(),
            ),
          ),
        ),
        if (_state == _PdfLoadState.loading)
          const Positioned.fill(child: _LoadingState()),
        if (_state == _PdfLoadState.error)
          const Positioned.fill(child: _ErrorState()),
      ],
    );
  }
}

/// Loading state — centered spinner on the app canvas while PDFKit opens the
/// document.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ColoredBox(
      color: colors.surface0,
      child: Center(
        child: Semantics(
          label: 'Loading reference card',
          liveRegion: true,
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.textAccent),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error state — the bundled asset failed to open. Honest, plain copy (GL-005);
/// no retry because a bundled asset that fails to open will not succeed on a
/// retry (it is a packaging/decode fault, not a transient network one).
class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return ColoredBox(
      color: colors.surface0,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Semantics(
            label: 'This reference card could not be opened. '
                'The bundled PDF failed to load on this device.',
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 48,
                  color: colors.textTertiary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This reference card could not be opened.',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The bundled PDF failed to load on this device.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textSecondary,
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
