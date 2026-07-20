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
// The squeeze (root cause as diagnosed 2026-06-01): the card that squeezed was
// `bubble-diagram.pdf`, then a portrait MediaBox carrying a `/Rotate 90` flag — a
// page whose stored box and presented box disagree. The squeeze was never a
// multi-page seeding problem; it was page-rotation handling.
//
// EVIDENCE RE-MEASURED 2026-07-20 (Vera gate). The paragraph above describes the
// asset as it was in June. It is no longer what ships: `bubble-diagram.pdf` now
// has `/MediaBox [0 0 1440 810]` and **no `/Rotate` key at all** — it is a native
// landscape page, and there is currently NO rotated card in the bundle. The
// header previously cited "612×792 with /Rotate 90"; the asset was evidently
// re-exported and this header was never updated. Corrected rather than deleted,
// because the viewer choice below still rests on this reasoning.
//
// Viewer choice (2026-06-01, still correct): we use pdfx's `PdfView`
// (PhotoView-backed), NOT `PdfViewPinch`. The difference that fixed the rotated
// card is in how each viewer sizes the page box:
//   - `PdfViewPinch` lays each page out from the REPORTED `PdfPageImage`
//     dimensions. On the Apple path the plugin reports the *requested* render
//     size in MediaBox order even though the native renderer correctly produces
//     a landscape raster — so a landscape image gets squeezed into a portrait
//     box.
//   - `PdfView` feeds the raw PNG bytes to `PdfPageImageProvider`, which DECODES
//     them, and PhotoView fit-contains the DECODED image
//     (`PhotoViewComputedScale.contained`). The decoded raster is the ground
//     truth, so the page paints undistorted whatever its MediaBox says.
// Keep `PdfView`: the reasoning is orientation-general, so it holds even though
// the specific rotated asset that motivated it is gone. If a `/Rotate` card is
// ever added back, the probe below already covers it.
//
// Objective evidence (integration_test/pdf_rotation_probe_test.dart, macOS,
// re-measured 2026-07-20): decoded PNG bytes are bubble-diagram 3600×2025
// (LANDSCAPE, aspect 1.778), channel-allocations-5ghz 1980×1530 (LANDSCAPE,
// 1.294), and top-20-checklist 1530×1980 (PORTRAIT, 0.773). That probe now
// ASSERTS these aspects instead of only printing them.
//
// One screen class, parameterized by `title` + `assetPath`, wired once per card
// in app_router.dart. The catalog id → asset file mapping lives in the router /
// catalog, not here.
//
// DESKTOP NAVIGATION (fixed 2026-07-20, customer report: Peter, Windows). The
// report: "Fix Your Own Wi-Fi doesn't seem to work on the Windows version. Just
// shows the title image and then you can't scroll / access the rest of the
// content." That is a real defect, and it was ours, not Windows'.
//
// Root cause (confirmed empirically on the real macOS build, see
// integration_test/pdf_desktop_navigation_test.dart): `PdfView` pages
// horizontally through a `PhotoViewGallery` backed by a `PageView`, and a
// `PageView` is a `Scrollable`. Flutter's default `ScrollBehavior.dragDevices`
// is `_kTouchLikeDeviceTypes` (widgets/scroll_configuration.dart) — touch,
// stylus, invertedStylus, trackpad, unknown. `PointerDeviceKind.mouse` is
// deliberately excluded, because Flutter expects desktop scrolling to happen via
// a scrollbar or the wheel. A `PageView` offers neither. With no page controls
// and no keyboard handling either, a mouse user had NO way to leave page 1.
//
// The control probe that proved it, on the unfixed screen: a drag of identical
// geometry moved the pager to page 1.0 for `PointerDeviceKind.touch`, 1.0 for
// `trackpad`, and 0.0 for `mouse`. Note `trackpad` is in the default set — which
// is exactly why this shipped: on a MacBook trackpad the viewer pages fine, so
// the defect is invisible unless you actually plug in a mouse.
//
// THREE of the 13 bundled documents are multi-page and were affected:
// fix-your-own-wifi (64 pages), ham-radio-general-exam-study-notes (15) and
// general-license-frequency-chart (6). Peter reported the book; the same bug was
// silently hiding pages of two reference cards. (Counts per `mdls -name
// kMDItemNumberOfPages`. An earlier revision of this comment listed
// mcs-index-card as 2 pages and the total as four documents; that came from a
// naive `/Type /Page` regex which double-counts the page-tree node.
// mcs-index-card is `/Count 1`, one page.)
//
// The fix is four independent affordances, so no single one is load-bearing:
//   1. [PdfViewerScrollBehavior] adds `mouse` to `dragDevices` — drag-to-page.
//   2. Visible previous/next controls + a "12 / 64" page indicator.
//   3. Arrow keys and PageUp/PageDown.
//   4. Mouse wheel pages; Command/Control + wheel zooms, as do explicit +/-
//      controls (Peter also reported "images are hard to view and it's not easy
//      / intuitive to zoom in / out" — pinch-to-zoom is not reachable by mouse).
//
// Accessibility: the screen is wrapped in a Semantics node naming the document
// and the gesture. That label is now PLATFORM-ACCURATE — it used to say "Pinch
// to zoom" unconditionally, which is a touch-only instruction that was simply
// false on the desktop builds where this bug lived. The PDF's INNER content is
// rasterized by PDFKit and is NOT screen-reader readable — an inherent
// limitation of rendering a flat print PDF, not something this screen can fix.
// The screen label is the honest, clear thing we can do (GL-005): name the card,
// state the interaction that actually exists on THIS platform.
//
// Tokens (GL-003 §8): surface0 canvas + app-bar, surface1 viewer backdrop,
// primary spinner, textPrimary/textSecondary/textTertiary for the error copy and
// the control bar, AppSpacing for gaps. No hardcoded colors or sizes. The
// prev/next/zoom glyphs are bare `IconButton`s so they inherit the §8.3 lime
// focus ring from the global `iconButtonTheme` rather than painting one locally,
// and they follow §8.16's "disabled, not hidden" rule at the document ends.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../../data/pdf_download.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';

/// Bundled asset for Keith's consumer book "Fix Your Own Wi-Fi" (Book 3) — shown
/// FREE in this same offline [PdfReferenceScreen] viewer and reached from the
/// home callout near "Check My Connection". Public so the home entry point and
/// the widget tests share one source of truth rather than re-typing the string.
///
/// NOTE: the bundled file is a near-final PLACEHOLDER export (Keith is finalizing
/// the Vellum export — a stray "Untitled" page). Swap the file at this path to
/// update; this constant stays stable so nothing downstream needs editing.
const String kFixYourOwnWifiBookAsset = 'assets/books/fix-your-own-wifi.pdf';

/// Zoom bounds this screen applies to every page, as multipliers of the
/// fit-to-viewport ("contained") scale.
///
/// Public because [_PdfReferenceScreenState._pageBuilder] re-implements pdfx's
/// private default page builder, and the only way to keep that copy honest is to
/// assert it against pdfx's own defaults from a test. See
/// `integration_test/pdf_rotation_probe_test.dart`.
const double kPdfMinZoomFactor = 1;
const double kPdfMaxZoomFactor = 3;

/// Whether a page turn may proceed. Pure, so it can be tested directly.
///
/// EXTRACTED 2026-07-20 (Vera gate). This logic used to be three inline
/// conditions inside `_turnPage`, and the most important of them — [pagerAttached]
/// — was **uncoverable**. It guards a sub-frame race (pdfx cross-fades its viewer
/// in via an `AnimatedSwitcher`, so "document loaded" briefly precedes "pager
/// exists"), and on a warm test process the document can open inside two frames.
/// Driving input at every frame of the load still could not reproduce it: with
/// the guard deleted, the integration suite stayed green. A guard whose deletion
/// no test can detect is a guard that will be deleted by someone tidying up.
///
/// Pulling the decision out of the widget makes the condition itself checkable
/// without needing to win a race. This is production logic, not a test seam: the
/// widget calls it on every keystroke, wheel tick and button press.
///
/// - [turning] — an animated turn is already in flight; further input is dropped
///   so a wheel flick cannot queue a dozen turns.
/// - [pagerAttached] — the `PageController` has a live position. Turning before
///   this trips `PageView`'s `positions.isNotEmpty` assertion and CRASHES, which
///   is why it is a hard gate rather than a nicety.
/// - [currentPage] is 1-based, matching `PdfController.page`.
bool canTurnPdfPage({
  required bool turning,
  required bool pagerAttached,
  required int currentPage,
  required int pageCount,
  required bool forward,
}) {
  if (turning) return false;
  if (!pagerAttached) return false;
  return forward ? currentPage < pageCount : currentPage > 1;
}

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

/// Scroll behavior for the PDF pager that accepts a MOUSE drag.
///
/// Flutter's default [ScrollBehavior.dragDevices] omits
/// [PointerDeviceKind.mouse] by design: on desktop it assumes a scrollbar or a
/// wheel will do the scrolling. A [PageView] has neither, so under the default
/// behavior a mouse user cannot turn the page at all. This adds `mouse` to the
/// touch-like set rather than replacing it, so touch, stylus, and trackpad
/// paging on iOS/Android are untouched.
///
/// Public so the widget test can assert the mouse kind is present without
/// reaching into private state.
class PdfViewerScrollBehavior extends MaterialScrollBehavior {
  const PdfViewerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        // The one that fixes Peter's report.
        PointerDeviceKind.mouse,
        PointerDeviceKind.unknown,
      };
}

/// Turn one page. [forward] follows reading order, so `true` is the next page.
class _TurnPageIntent extends Intent {
  const _TurnPageIntent({required this.forward});

  final bool forward;
}

/// True on platforms driven by a mouse/keyboard, where page controls and zoom
/// controls are needed because there is no pinch or swipe.
///
/// Reads [defaultTargetPlatform] rather than `dart:io` so it stays web-safe —
/// the same signal [about_screen.dart]'s platform gate uses. On web this
/// resolves to the host OS, which is the behavior we want: desktop browsers get
/// the controls, mobile browsers keep the touch affordances.
///
/// Note this is deliberately NOT the codebase's other `isDesktop`, which is a
/// 720px width breakpoint. Whether a pointer exists is a platform question, not
/// a window-size question: a narrow window on Windows still has only a mouse.
bool get _isPointerPlatform => switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      TargetPlatform.iOS || TargetPlatform.android || TargetPlatform.fuchsia =>
        false,
    };

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

  /// Page count of the open document, 0 until it loads. Drives whether the
  /// page-navigation half of the control bar appears at all — a single-page
  /// reference card gets no pager and no "1 / 1" indicator.
  int _pageCount = 0;

  /// Current 1-based page, mirroring [PdfController.page].
  int _currentPage = 1;

  /// Guards against a flick of the wheel queueing a dozen page turns: while an
  /// animated turn is in flight, further wheel ticks are dropped.
  bool _turning = false;

  /// True once the pager is actually laid out and its [PageController] has a
  /// position attached.
  ///
  /// Needed because "the document loaded" and "the pager exists" are not the
  /// same instant: pdfx wraps its content in an `AnimatedSwitcher`, so there is
  /// a window after `onDocumentLoaded` where the gallery has not been built yet.
  /// Calling `animateToPage` in that window trips PageView's
  /// `positions.isNotEmpty` assertion and crashes. A keystroke or a wheel tick
  /// during the loading spinner is an ordinary thing for a user to do, so this
  /// is a real crash, not a test artifact — it was caught by the arrow-key test
  /// hitting the transition window.
  ///
  /// [ScrollMetricsNotification] is the honest signal: it fires when a
  /// scrollable reports its metrics, which only happens once attached.
  bool _pagerAttached = false;

  /// Keyboard focus for the viewer, so arrow keys and PageUp/PageDown reach the
  /// [Shortcuts] above it.
  final FocusNode _viewerFocusNode = FocusNode(debugLabel: 'PDF viewer');

  /// One PhotoView controller per page index, created lazily, so the +/- zoom
  /// controls can drive the SAME transform the pinch gesture drives. pdfx's
  /// default page builder creates these internally and keeps them private, so
  /// the screen overrides `pageBuilder` purely to inject a controller it can
  /// reach.
  final Map<int, PhotoViewController> _photoControllers =
      <int, PhotoViewController>{};

  /// Rendered raster size per page index, captured as each page's render future
  /// completes. Half of the fit-to-viewport calculation below.
  final Map<int, Size> _pageRasterSizes = <int, Size>{};

  /// The viewer's own box, from the [LayoutBuilder] around the viewer. The other
  /// half of the fit-to-viewport calculation.
  Size? _viewerSize;

  /// Zoom bounds, mirroring the `minScale`/`maxScale` this screen passes to
  /// [PhotoViewGalleryPageOptions] so the buttons and the pinch gesture agree.
  /// Library-level so `pdf_rotation_probe_test` can assert them against pdfx's
  /// OWN defaults, which is what keeps [_pageBuilder] honest (see its doc).
  static const double _minZoomFactor = kPdfMinZoomFactor;
  static const double _maxZoomFactor = kPdfMaxZoomFactor;

  /// One press of + or one wheel notch. 1.4 gives roughly four steps across the
  /// 1x to 3x range, which reads as responsive without overshooting.
  static const double _zoomStep = 1.4;

  /// Anchors the iPad/macOS share popover to the share button's on-screen rect
  /// (share_plus throws on those platforms without a source rect).
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Lazily creates the PhotoView controller for [index].
  PhotoViewController _photoControllerFor(int index) =>
      _photoControllers.putIfAbsent(index, PhotoViewController.new);

  /// The fit-to-viewport ("contained") scale for [index], or null while the
  /// page or the viewport is still unmeasured.
  ///
  /// We compute this rather than read it back off the [PhotoViewController],
  /// because photo_view leaves `controller.scale` NULL until the user's first
  /// gesture and falls back to its internally computed `initialScale` in the
  /// meantime (photo_view_controller_delegate.dart `scale` getter). Waiting for
  /// a non-null scale would mean the +/- buttons silently did nothing until the
  /// user had already zoomed some other way, which on a mouse-only desktop is
  /// never. This mirrors photo_view's own `_scaleForContained`
  /// (photo_view_utils.dart): min of the two axis ratios.
  double? _baseScaleFor(int index) {
    final Size? child = _pageRasterSizes[index];
    final Size? outer = _viewerSize;
    if (child == null || outer == null) return null;
    if (child.isEmpty || outer.isEmpty) return null;
    return math.min(outer.width / child.width, outer.height / child.height);
  }

  /// Page builder that matches pdfx's own defaults exactly, plus the injected
  /// [PhotoViewController] and the desktop [disableGestures] handoff.
  ///
  /// This is a hand-copy of pdfx's PRIVATE `_PdfViewState._pageBuilder`, so it
  /// can silently drift if pdfx changes its defaults. That risk is ENCODED, not
  /// merely narrated: `pdf_rotation_probe_test.dart` builds pdfx's own default
  /// `PdfViewBuilders` and asserts its scale values equal [kPdfMinZoomFactor] /
  /// [kPdfMaxZoomFactor] / contained*1. If pdfx changes them, that test goes red
  /// and this copy gets updated.
  ///
  /// The min/max/initial scales stay expressed as [PhotoViewComputedScale] so
  /// the fit behavior this file's header documents (PhotoView fit-containing the
  /// DECODED raster, which is what makes the `/Rotate 90` bubble diagram paint
  /// undistorted) is completely unchanged.
  PhotoViewGalleryPageOptions _pageBuilder(
    BuildContext context,
    Future<PdfPageImage> pageImage,
    int index,
    PdfDocument document,
  ) {
    // Record the raster dimensions for the zoom math. Errors are pdfx's to
    // surface through its own error builder; swallowing here only means the
    // zoom buttons stay inert for a page that never rendered anyway.
    unawaited(
      pageImage.then<void>(
        (PdfPageImage image) {
          final int? w = image.width;
          final int? h = image.height;
          if (w == null || h == null || w <= 0 || h <= 0) return;
          _pageRasterSizes[index] = Size(w.toDouble(), h.toDouble());
        },
        onError: (Object _) {},
      ),
    );

    return PhotoViewGalleryPageOptions(
      imageProvider: PdfPageImageProvider(pageImage, index, document.id),
      controller: _photoControllerFor(index),
      // Hand plain drags to the pager while the page is at fit scale, and give
      // them back to PhotoView once the user has zoomed in and actually needs to
      // pan. See [_pageOwnsDragGesture] for why this is necessary on desktop.
      disableGestures: !_pageOwnsDragGesture(index),
      minScale: PhotoViewComputedScale.contained * _minZoomFactor,
      maxScale: PhotoViewComputedScale.contained * _maxZoomFactor,
      initialScale: PhotoViewComputedScale.contained * 1.0,
      heroAttributes: PhotoViewHeroAttributes(tag: '${document.id}-$index'),
    );
  }

  /// True when [index] is zoomed in past its fit-to-viewport scale.
  bool _isZoomedIn(int index) {
    final double? base = _baseScaleFor(index);
    final double? scale = _photoControllers[index]?.scale;
    if (base == null || scale == null) return false;
    // 1% tolerance so floating-point noise does not read as "zoomed".
    return scale > base * 1.01;
  }

  /// Whether PhotoView should keep its own drag gestures for [index].
  ///
  /// This is the second half of the desktop fix, and it is needed because
  /// [PdfViewerScrollBehavior] alone is not sufficient INSIDE the gallery.
  /// Measured on the real macOS build: a mouse fling on a bare `PageView` moves
  /// it to page 0.999 under our behavior (and 0.0 under Flutter's default), but
  /// the same fling inside `PhotoViewGallery` produces ZERO scroll
  /// notifications. photo_view's `PhotoViewGestureRecognizer` is a
  /// `ScaleGestureRecognizer`, and for precise pointers it claims the gesture at
  /// `kPrecisePointerPanSlop` (2px) instead of `kPanSlop` (36px), so on a mouse
  /// it wins the arena before the pager's drag recognizer ever starts. Its
  /// axis-aware hand-off to the parent `PageView` works for touch and simply
  /// does not for a mouse.
  ///
  /// So on pointer platforms we disable PhotoView's gestures WHILE THE PAGE IS
  /// AT FIT SCALE (nothing to pan, so nothing is lost) and re-enable them the
  /// moment the user zooms in (where dragging should pan, not page). Touch
  /// platforms are never affected: pinch and swipe keep working exactly as
  /// before, which is why the touch paths in the test suite are unchanged.
  bool _pageOwnsDragGesture(int index) =>
      !_isPointerPlatform || _isZoomedIn(index);

  bool get _canGoBack => _currentPage > 1;

  bool get _canGoForward => _currentPage < _pageCount;

  /// Animates one page in [forward] reading order. No-ops at either end so a
  /// held arrow key or a wheel flick cannot scroll past the document.
  Future<void> _turnPage({required bool forward}) async {
    if (!canTurnPdfPage(
      turning: _turning,
      pagerAttached: _pagerAttached,
      currentPage: _currentPage,
      pageCount: _pageCount,
      forward: forward,
    )) {
      return;
    }
    _turning = true;
    try {
      await _controller.animateToPage(
        _currentPage + (forward ? 1 : -1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } finally {
      _turning = false;
    }
  }

  /// Multiplies the current page's zoom by [factor], clamped to the same bounds
  /// the pinch gesture obeys.
  void _zoomBy(double factor) {
    final int index = _currentPage - 1;
    final double? base = _baseScaleFor(index);
    // Before the page or viewport has been measured we have no baseline to
    // clamp against, so doing nothing is the honest response (GL-005) rather
    // than guessing a scale and yanking the view.
    if (base == null) return;
    final PhotoViewController controller = _photoControllerFor(index);
    // A null controller scale means "still at the initial/contained scale".
    final double current = controller.scale ?? base;
    controller.scale =
        (current * factor).clamp(base * _minZoomFactor, base * _maxZoomFactor);
    // Crossing the fit-scale threshold flips which widget owns drag gestures
    // (see [_pageOwnsDragGesture]), so the gallery has to rebuild.
    if (mounted) setState(() {});
  }

  /// Returns the current page to fit-the-viewport.
  void _resetZoom() {
    final int index = _currentPage - 1;
    final double? base = _baseScaleFor(index);
    if (base == null) return;
    _photoControllerFor(index)
      ..scale = base
      ..position = Offset.zero;
    if (mounted) setState(() {});
  }

  /// Mouse wheel: a plain notch turns the page, Command/Control + notch zooms.
  ///
  /// Registering with the [PointerSignalResolver] rather than acting directly
  /// means the enclosing [Scrollable] does not ALSO consume the same tick, so
  /// one notch never turns two pages.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      final PointerScrollEvent scroll = resolved as PointerScrollEvent;
      final bool zoomModifier = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      // A mouse wheel reports on dy; a horizontal wheel or a tilted one reports
      // on dx. Take whichever axis actually moved.
      final double delta = scroll.scrollDelta.dy.abs() >=
              scroll.scrollDelta.dx.abs()
          ? scroll.scrollDelta.dy
          : scroll.scrollDelta.dx;
      if (delta == 0) return;
      if (zoomModifier) {
        // Wheel up (negative dy) zooms in, matching every desktop PDF reader.
        _zoomBy(delta < 0 ? _zoomStep : 1 / _zoomStep);
        return;
      }
      unawaited(_turnPage(forward: delta > 0));
    });
  }

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
    final Future<PdfDocument> documentFuture =
        PdfDocument.openAsset(widget.assetPath);
    _controller = PdfController(document: documentFuture);

    // Defensive open-failure handling (GL-005 honest degradation). pdfx's
    // PdfView catches a failed document future once it mounts and attaches the
    // controller, but until that happens the future is unobserved. If the asset
    // cannot open — a corrupt PDF, or an unsupported platform with no native PDF
    // engine (e.g. the headless test host, where openAsset throws
    // PlatformNotSupportedException) — and the screen is disposed before the
    // viewer attaches, that rejection would surface as an uncaught async error
    // instead of a quiet, honest error state. Observing the future here
    // guarantees it is always handled and drives the same error UI, so the
    // screen degrades gracefully rather than crashing on any platform.
    unawaited(
      documentFuture.then<void>(
        (_) {},
        onError: _onError,
      ),
    );
  }

  @override
  void dispose() {
    for (final PhotoViewController controller in _photoControllers.values) {
      controller.dispose();
    }
    _viewerFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(PdfDocument document) {
    if (!mounted) return;
    setState(() {
      _state = _PdfLoadState.ready;
      // Drives the page indicator and whether the pager controls appear.
      _pageCount = document.pagesCount;
    });
  }

  void _onPageChanged(int page) {
    if (!mounted) return;
    setState(() => _currentPage = page);
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
          // Explicit accessible name (GL-003 §8.16, WCAG 2.2 AA SC 4.1.2).
          // `tooltip:` alone is NOT an accessible name: Flutter keeps it in a
          // separate field, which macOS maps to AXHelp rather than AXTitle, so a
          // live semantics dump of this button read `label="" button=true` — an
          // unnamed button to a screen reader. Same treatment as [_ControlButton].
          Semantics(
            button: true,
            // Must be set explicitly. A Semantics node with `button: true` and no
            // `enabled` leaves the isEnabled flag UNSET, which AT reads as a
            // DISABLED button — a live dump showed exactly that after the label
            // was added. Share is always available here (the asset is bundled),
            // so this is unconditionally true; [_ControlButton] passes its real
            // enabled state instead, because its controls genuinely do disable.
            enabled: true,
            label: 'Share or download',
            child: IconButton(
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
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowRight):
                      _TurnPageIntent(forward: true),
                  SingleActivator(LogicalKeyboardKey.arrowLeft):
                      _TurnPageIntent(forward: false),
                  SingleActivator(LogicalKeyboardKey.arrowDown):
                      _TurnPageIntent(forward: true),
                  SingleActivator(LogicalKeyboardKey.arrowUp):
                      _TurnPageIntent(forward: false),
                  SingleActivator(LogicalKeyboardKey.pageDown):
                      _TurnPageIntent(forward: true),
                  SingleActivator(LogicalKeyboardKey.pageUp):
                      _TurnPageIntent(forward: false),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _TurnPageIntent: CallbackAction<_TurnPageIntent>(
                      onInvoke: (_TurnPageIntent intent) {
                        unawaited(_turnPage(forward: intent.forward));
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    focusNode: _viewerFocusNode,
                    // The viewer is the primary content of this screen, so it
                    // takes focus on open and the arrow keys work immediately
                    // without the user hunting for a control to focus first.
                    autofocus: true,
                    child: Semantics(
                      // PDF inner content is rasterized and not SR-readable; the
                      // screen label is the honest description of what this
                      // surface is and how to use it. The interaction named here
                      // is the one that actually exists on THIS platform.
                      label: _semanticsLabel,
                      // Child semantics are deliberately NOT excluded, and this
                      // comment used to claim otherwise. `explicitChildNodes:
                      // false` is Flutter's default and excludes nothing; the flag
                      // that would exclude is `excludeSemantics: true` (used
                      // correctly on the page indicator below).
                      //
                      // Corrected the COMMENT rather than the code, because
                      // excluding here would be a real accessibility regression:
                      // [_body] contains the `_LoadingState` and `_ErrorState`
                      // liveRegion announcements, and silencing those would leave
                      // a screen-reader user with no signal that the card is
                      // loading or that it failed to open. The rasterized PDF
                      // contributes no competing label, so there is nothing to
                      // suppress in the success case anyway.
                      explicitChildNodes: false,
                      child: Listener(
                        onPointerSignal: _handlePointerSignal,
                        child: _body(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Page + zoom controls. Self-omits entirely on touch platforms
            // showing a single-page card, where there is nothing to navigate
            // and pinch already handles zoom.
            _ViewerControlBar(
              currentPage: _currentPage,
              pageCount: _pageCount,
              showPageControls: _isPointerPlatform,
              showZoomControls: _isPointerPlatform,
              onPrevious: _canGoBack ? () => _turnPage(forward: false) : null,
              onNext: _canGoForward ? () => _turnPage(forward: true) : null,
              onZoomIn: () => _zoomBy(_zoomStep),
              onZoomOut: () => _zoomBy(1 / _zoomStep),
              onZoomReset: _resetZoom,
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

  /// Platform-accurate screen label. The old copy said "Pinch to zoom"
  /// unconditionally, which is a touch-only instruction and was simply false on
  /// macOS/Windows/Linux — the platforms where this screen was unnavigable.
  String get _semanticsLabel {
    final StringBuffer label = StringBuffer('${widget.title} reference card.');
    if (_isPointerPlatform) {
      if (_pageCount > 1) {
        label.write(
          ' Page $_currentPage of $_pageCount.'
          ' Use the arrow keys or the on-screen controls to change page.',
        );
      }
      // Command on macOS, Control on Windows and Linux, matching the modifier
      // each platform's users already expect for zoom.
      final String zoomModifier =
          defaultTargetPlatform == TargetPlatform.macOS ? 'Command' : 'Control';
      label.write(
        ' Use the zoom controls, or hold $zoomModifier and scroll, to zoom.',
      );
      return label.toString();
    }
    if (_pageCount > 1) {
      label.write(
        ' Page $_currentPage of $_pageCount. Swipe to change page.',
      );
    }
    label.write(' Pinch to zoom.');
    return label.toString();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // The viewer is always mounted so its load callbacks fire; the loading and
    // error overlays sit on top of it until the document resolves. PhotoView
    // fit-contains the DECODED raster, so each page (including the `/Rotate 90`
    // bubble diagram) paints at its true aspect ratio.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The viewer's box is PhotoView's `outerSize`, the denominator of the
        // fit-to-viewport scale the zoom controls work from. Recorded during
        // layout, so a window resize keeps the zoom math correct.
        _viewerSize = Size(constraints.maxWidth, constraints.maxHeight);
        return _viewer(context, colors);
      },
    );
  }

  Widget _viewer(BuildContext context, AppColorScheme colors) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          // Marks the pager live once its scroll position exists, so a keystroke
          // or wheel tick during the load transition cannot call animateToPage
          // on an unattached controller.
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (ScrollMetricsNotification _) {
              // Deliberately NOT a setState: this flag only gates a callback and
              // is never read during build, so rebuilding here would be pure
              // cost. It would also be harmful — metrics fire mid-drag, and the
              // rebuild interrupts the very gesture we are trying to support.
              _pagerAttached = true;
              // Let the notification keep bubbling; we only observe it.
              return false;
            },
            // THE mouse fix: without this the inner PageView rejects
            // PointerDeviceKind.mouse drags outright and the document is pinned
            // to page 1 on every desktop platform.
            child: ScrollConfiguration(
              behavior: const PdfViewerScrollBehavior(),
              child: PdfView(
                controller: _controller,
                renderer: renderReferencePage,
                onDocumentLoaded: _onLoaded,
                onDocumentError: _onError,
                onPageChanged: _onPageChanged,
                // Dark, token-based backdrop for the letterbox around each page
                // — the default is a light gray that clashes with App Mode
                // (GL-003 §8.1).
                backgroundDecoration:
                    BoxDecoration(color: colors.surface1),
                builders: PdfViewBuilders<DefaultBuilderOptions>(
                  options: const DefaultBuilderOptions(),
                  documentLoaderBuilder: (_) => _LoadingState(),
                  pageLoaderBuilder: (_) => _LoadingState(),
                  errorBuilder: (_, _) => const _ErrorState(),
                  // Injects a reachable PhotoViewController per page so the +/-
                  // controls drive the same transform pinch does.
                  pageBuilder: _pageBuilder,
                ),
              ),
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

/// Page + zoom controls pinned beneath the viewer.
///
/// Visibility rules, so the bar never shows a control that does nothing:
///   - Page controls (prev / next) need a pointer platform AND a multi-page
///     document. Touch platforms already swipe; a single-page card has no pages
///     to turn.
///   - The page indicator shows on EVERY platform for a multi-page document —
///     knowing you are on 12 of 64 is useful whether or not you can click.
///   - Zoom controls need a pointer platform. Touch has pinch; a mouse does not,
///     which is the second half of the customer's report.
///
/// The whole bar self-omits when it would be empty (the common case: a
/// single-page reference card on iOS/Android).
///
/// Per GL-003 §8.16 the end-of-document prev/next are **disabled, not hidden**,
/// so the bar does not reflow as you page and a screen-reader user meets a
/// labelled disabled control rather than a vanishing one. The glyphs are bare
/// [IconButton]s so they inherit the §8.3 lime focus ring from the global
/// `iconButtonTheme` instead of painting one locally.
class _ViewerControlBar extends StatelessWidget {
  const _ViewerControlBar({
    required this.currentPage,
    required this.pageCount,
    required this.showPageControls,
    required this.showZoomControls,
    required this.onPrevious,
    required this.onNext,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final int currentPage;
  final int pageCount;
  final bool showPageControls;
  final bool showZoomControls;

  /// Null disables the control (document start / end).
  final VoidCallback? onPrevious;

  /// Null disables the control (document start / end).
  final VoidCallback? onNext;

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final bool multiPage = pageCount > 1;
    final bool pagerVisible = showPageControls && multiPage;
    // Nothing to draw: don't take vertical space from the viewer.
    if (!pagerVisible && !showZoomControls && !multiPage) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface0,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (pagerVisible)
              _ControlButton(
                icon: Icons.chevron_left,
                label: 'Previous page',
                onPressed: onPrevious,
              ),
            if (multiPage)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                ),
                child: Semantics(
                  // Read as a sentence rather than "1 slash 64".
                  label: 'Page $currentPage of $pageCount',
                  excludeSemantics: true,
                  child: Text(
                    '$currentPage / $pageCount',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            if (pagerVisible)
              _ControlButton(
                icon: Icons.chevron_right,
                label: 'Next page',
                onPressed: onNext,
              ),
            if (showZoomControls) ...<Widget>[
              if (multiPage)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: SizedBox(
                    height: AppSpacing.sm,
                    child: VerticalDivider(
                      width: 1,
                      color: colors.border,
                    ),
                  ),
                ),
              _ControlButton(
                icon: Icons.zoom_out,
                label: 'Zoom out',
                onPressed: onZoomOut,
              ),
              _ControlButton(
                icon: Icons.zoom_in,
                label: 'Zoom in',
                onPressed: onZoomIn,
              ),
              _ControlButton(
                icon: Icons.fit_screen_outlined,
                label: 'Fit page to window',
                onPressed: onZoomReset,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One icon control in the [_ViewerControlBar].
///
/// A bare [IconButton] so the §8.3 focus ring arrives from the global
/// `iconButtonTheme`. Passing a null [onPressed] both greys the glyph to
/// `textDisabled` and drops it from focus traversal, which is the §8.16
/// disabled treatment.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = onPressed != null;
    // Explicit Semantics per GL-003 §8.16 ("Semantics(button: true) label" on
    // icon-only affordances). This is NOT redundant with the tooltip: a
    // semantics dump of this screen on macOS showed the tooltip contributing no
    // accessible name at all, so an icon-only control would otherwise reach a
    // screen reader as an unlabelled button.
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        iconSize: 24,
        tooltip: label,
        // Keeps the ≥44pt hit region of §8.3 even though the glyph is 24px.
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        icon: Icon(
          icon,
          size: 24,
          color: enabled ? colors.textSecondary : colors.textDisabled,
        ),
      ),
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
