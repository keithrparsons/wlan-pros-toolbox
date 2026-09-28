// A guide figure in a Guided Lesson: the guide's own SVG, fit to the column
// width, on an always-light card, with its caption and a zoom glyph under it. Tap, click, or
// focus and press Enter or Space, and it opens full screen to pinch and pan.
//
// WHY AN ALWAYS-LIGHT CARD. The guide figures are drawn for a white page:
// charcoal ink, slate and green series, pale fills. On the dark canvas they
// would lose their dark lines, and recoloring them would change the guide's
// figure. So the card is the light scheme's card surface in both themes,
// read from AppColorScheme.light(), the same "fixed surface from the other
// scheme" idiom DarkRasterDiagramCard uses for its always-dark card. In dark
// mode the card reads as a printed page lying on the dark screen.
//
// THE CAPTION IS THE ALT TEXT. The figure button's Semantics label is the
// plain caption, and the visible caption under it is excluded so a screen
// reader hears it once. [LessonFigure.alt] overrides the label when a lesson
// sets one.
//
// KEYBOARD. Unlike ZoomableGraphic (whose file records a WCAG 2.1.1 failure:
// its bare GestureDetector never takes focus), the zoom control here is a
// FocusableActionDetector: Tab reaches it, a focus ring shows, and Enter or
// Space opens the zoom. The pointer path stays a GestureDetector, so a
// single click opens it on macOS (the double-click bug ZoomableGraphic
// records came from an InkWell taking focus on the first click).
//
// STATES: the SVG is a bundled asset. While it loads, the card holds its
// final size (AspectRatio from the viewBox), so nothing below it moves. If it
// fails to load, the card shows a line saying the figure could not be shown,
// and the caption still reads.
//
// THEME: context.colors and AppColorScheme.light() only; AppSpacing and
// AppRadius for every size.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../screens/tools/reference/lesson_parts.dart'
    hide LessonCallout, LessonMyth;
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import 'guided_lesson.dart';

/// Test handle for a figure's zoom control, keyed by its asset path.
Key lessonFigureKey(String asset) => ValueKey<String>('lesson-figure:$asset');

class LessonFigureView extends StatefulWidget {
  const LessonFigureView(this.figure, {super.key});

  final LessonFigure figure;

  @override
  State<LessonFigureView> createState() => _LessonFigureViewState();
}

class _LessonFigureViewState extends State<LessonFigureView> {
  bool _focused = false;

  LessonFigure get _f => widget.figure;

  String get _label {
    final String said = _f.alt ?? lessonPlain(_f.caption ?? '');
    return said.isEmpty ? 'Figure' : said;
  }

  void _open() {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: AppMotion.base,
        reverseTransitionDuration: AppMotion.fast,
        settings: RouteSettings(name: 'lesson-figure-zoom:${_f.asset}'),
        pageBuilder:
            (BuildContext c, Animation<double> a, Animation<double> b) =>
                LessonFigureZoom(figure: _f, label: _label),
        transitionsBuilder:
            (
              BuildContext c,
              Animation<double> a,
              Animation<double> b,
              Widget child,
            ) {
              final bool reduce =
                  MediaQuery.maybeDisableAnimationsOf(c) ?? false;
              if (reduce) return child;
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: a,
                  curve: AppMotion.standardEase,
                ),
                child: child,
              );
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppColorScheme paper = AppColorScheme.light();
    final Widget card = Container(
      decoration: BoxDecoration(
        color: paper.surface1,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: _focused ? colors.textAccent : colors.border,
          width: _focused ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: AspectRatio(
        aspectRatio: _f.aspectRatio,
        child: LessonSvg(figure: _f),
      ),
    );

    final Widget control = Semantics(
      button: true,
      image: true,
      label: _label,
      hint: 'Opens the figure full screen',
      onTap: _open,
      child: FocusableActionDetector(
        onShowFocusHighlight: (bool v) => setState(() => _focused = v),
        mouseCursor: SystemMouseCursors.zoomIn,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _open();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: lessonFigureKey(_f.asset),
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: card,
        ),
      ),
    );

    final Widget sized = _f.maxWidth == null
        ? control
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _f.maxWidth!),
              child: control,
            ),
          );

    // The zoom glyph sits under the card, never on the art: a badge on the
    // figure covered its labels (the same collision DarkRasterDiagramCard
    // solved the same way). It is decorative; the card is the control.
    final Widget glyph = ExcludeSemantics(
      child: Icon(
        Icons.zoom_in,
        size: AppSpacing.md,
        color: colors.textSecondary,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        sized,
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _f.caption == null
                  ? const SizedBox.shrink()
                  : ExcludeSemantics(
                      child: LessonRich(
                        _f.caption!,
                        style: lessonBody(
                          context,
                          small: true,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            glyph,
          ],
        ),
      ],
    );
  }
}

/// The figure's SVG, contained in whatever box it is given, excluded from
/// semantics at the leaf (GL-003 §8.6.2.2) so the zoom control above it stays
/// reachable.
class LessonSvg extends StatelessWidget {
  const LessonSvg({super.key, required this.figure});

  final LessonFigure figure;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme paper = AppColorScheme.light();
    return SvgPicture.asset(
      figure.asset,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      placeholderBuilder: (BuildContext c) => const SizedBox.expand(),
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => Center(
        child: Text(
          'This figure could not be shown. Its caption is below.',
          textAlign: TextAlign.center,
          style: lessonBody(c, small: true, color: paper.textSecondary),
        ),
      ),
    );
  }
}

/// Full-screen zoom: the figure on its light card, pinch and pan from 1x to
/// 5x. Esc, the close button, or the system back gesture closes it.
class LessonFigureZoom extends StatelessWidget {
  const LessonFigureZoom({
    super.key,
    required this.figure,
    required this.label,
  });

  final LessonFigure figure;
  final String label;

  static const Key closeKey = ValueKey<String>('lesson-figure-zoom-close');

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppColorScheme paper = AppColorScheme.light();
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: colors.surface0,
            body: SafeArea(
              child: Stack(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xxl,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Center(
                      child: Semantics(
                        image: true,
                        label: label,
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          boundaryMargin: const EdgeInsets.all(AppSpacing.xxl),
                          child: Container(
                            decoration: BoxDecoration(
                              color: paper.surface1,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                            ),
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: AspectRatio(
                              aspectRatio: figure.aspectRatio,
                              child: LessonSvg(figure: figure),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: IconButton(
                      key: closeKey,
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.close, color: colors.textPrimary),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(
                          AppSpacing.minTouchTarget,
                          AppSpacing.minTouchTarget,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
