// FieldPlateAction — the shared "open the printable field plate" AppBar
// affordance for the native Field & Trade Reference screens.
//
// WHY THIS EXISTS
// ---------------
// Thirteen of the Field & Trade Reference tools are native Dart screens
// (searchable, theme-aware, screen-reader-navigable), and each one has a
// companion PRINT PLATE — the single-sheet graphic Keith publishes and that
// people tape inside a job box. The screen is the better experience on a phone;
// the plate is the better artifact on paper. Both should be reachable, and the
// native screen is where somebody already is when they want the plate.
//
// This widget is the seam between them. It does NOT introduce a second share
// path: it pushes the existing [PdfReferenceScreen], which already owns the
// pinch-zoom viewer, the share/download button (lib/data/pdf_download.dart),
// the honest load-failure state, and the SR announcements. One tap to view, and
// the download affordance the user already knows from the laminated cards.
//
// PLATE SIZING (as bundled, 2026-08-21)
// -------------------------------------
// The thirteen plates are large-format: 17.5in wide with heights from 9.94in to
// 21.62in — not Letter, not tabloid, not ANSI C. They read well in the
// pinch-zoom viewer and print correctly at large format; printed to Letter
// their smallest type lands near 6.9pt. A Letter re-lay is queued as a second
// wave and will swap the files in place — the asset paths and this widget's
// contract are deliberately stable across that swap, so no catalog or screen
// change is needed when it lands. The one exception already meeting the Letter
// standard is `throughput-testing-where.pdf` (8.5x11 portrait).
//
// Source of truth for the affordance rules: GL-003 §8.16 (AppBar actions), §8.6
// (icon sizing/color), §8.3 (touch target + focus ring), §8.9 (a11y floor).
// The §8.3 keyboard focus ring is painted globally by the app ThemeData's
// `iconButtonTheme` (ButtonStyle.side → the 2px lime ring on
// WidgetState.focused), so — exactly as in [AppCopyAction] — this widget draws
// no ring of its own; the inner IconButton inherits it.

import 'package:flutter/material.dart';

import '../screens/tools/reference/pdf_reference_screen.dart';
import '../theme/app_color_scheme.dart';

/// Root of the bundled print plates. One PDF per tool, named by the tool's
/// catalog id, so the lookup is mechanical and a missing plate is a missing
/// file rather than a lookup-table entry somebody forgot to add.
const String kFieldPlateAssetRoot = 'assets/field-plates/';

/// Resolves the bundled plate asset for a catalog [toolId].
String fieldPlateAssetFor(String toolId) => '$kFieldPlateAssetRoot$toolId.pdf';

/// The "View printable plate" AppBar action for a native reference screen.
///
/// Placed in `AppBar.actions` AFTER [AppCopyAction] where both exist. §8.16
/// fixes only the copy-leading / help-trailing pair; the plate action is
/// neither, and it sits trailing so the copy affordance keeps the leading slot
/// the rule assigns it.
class FieldPlateAction extends StatelessWidget {
  const FieldPlateAction({
    required this.toolId,
    required this.plateTitle,
    this.label = 'View printable plate',
    super.key,
  });

  /// The catalog id of the screen this action sits on. Resolves the bundled
  /// asset via [fieldPlateAssetFor] and is forwarded to [PdfReferenceScreen] so
  /// the plate view inherits the tool's authored help entry.
  final String toolId;

  /// Title shown in the plate viewer's AppBar. The tool's own title reads as
  /// the screen you came from, so callers pass the PLATE's name.
  final String plateTitle;

  /// Semantics label and tooltip (§8.16: verb + object).
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;

    return Semantics(
      button: true,
      label: label,
      // The parent Semantics owns the single labelled button role; the inner
      // IconButton/Icon stay out of the tree (the [AppCopyAction] pattern).
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfReferenceScreen(
                title: plateTitle,
                assetPath: fieldPlateAssetFor(toolId),
                toolId: toolId,
              ),
            ),
          ),
          // 24px glyph (§8.6 nav size); IconButton keeps the ≥48dp hit region
          // for the §8.3 touch-target floor.
          iconSize: 24,
          tooltip: label,
          icon: Icon(
            Icons.picture_as_pdf_outlined,
            size: 24,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
