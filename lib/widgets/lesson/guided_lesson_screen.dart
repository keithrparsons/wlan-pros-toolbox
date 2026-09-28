// GuidedLessonScreen: renders any GuidedLesson, on a phone and in Present.
//
// PHONE. One centered column at the reading width: the cover art, the
// guide's tagline and promise, every step as a numbered landmark section,
// the "Take it with you" row, and the tool-help footer.
//
// PRESENT (wide windows). The Present button opens the shared Wi-Fi Classroom
// PresenterLayout (lib/widgets/presenter/) over the SAME controller, the way
// the Devices to Internet lesson does. One step per slide (a long appendix
// splits at its subheadings): the stage shows the step's figures, myths,
// lede, cards and callouts, scaled to fit with no scroll; the panel carries
// Previous / Next, the slide count and the rest of the step's text. A step
// that would scale its text under kLessonPresentTextFloor is split into
// parts, "Step 4 of 8, part 2 of 4" (see _StageState).
// Keys: Right and Left move a slide, through a step's parts and on to the
// next step; Space reveals the next fact on a myth slide; R goes back to the
// first slide with every fact hidden; F switches full screen, ? lists the
// keys, Esc exits.
//
// STATES (SOP-007 §5): the lesson is bundled data with no network, so the
// rendered state is success. A figure that fails to load says so in its
// card, and its caption still reads. A link to a tool that is not in the
// build draws nothing. Interactive: figure zoom, myth reveal, tool links,
// Previous / Next, all keyboard-reachable with the theme's focus ring.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../screens/tools/reference/lesson_parts.dart' hide LessonCallout;
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../presenter/presenter.dart';
import '../tool_help_footer.dart';
import 'guided_lesson.dart';
import 'guided_lesson_controller.dart';
import 'lesson_blocks.dart';
import 'lesson_figure_view.dart';

/// Widest the Present stage lays a step out before scaling it down.
const double kLessonStageMaxWidth = 1100;

class GuidedLessonScreen extends StatefulWidget {
  const GuidedLessonScreen({super.key, required this.lesson});

  final GuidedLesson lesson;

  static const Key previousKey = ValueKey<String>('lesson-present-previous');
  static const Key nextKey = ValueKey<String>('lesson-present-next');
  static const Key counterKey = ValueKey<String>('lesson-present-counter');

  @override
  State<GuidedLessonScreen> createState() => _GuidedLessonScreenState();
}

class _GuidedLessonScreenState extends State<GuidedLessonScreen> {
  late final GuidedLessonController _controller = GuidedLessonController(
    widget.lesson,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) {
    return PresenterLayout(
      title: widget.lesson.title,
      stage: GuidedLessonScope(controller: _controller, child: const _Stage()),
      controls: GuidedLessonScope(
        controller: _controller,
        child: const _Controls(),
      ),
      actions: _controller.presenterActions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final GuidedLesson lesson = widget.lesson;
    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.title),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: lesson.route, builder: _presenter),
        ],
      ),
      body: SafeArea(
        top: false,
        child: GuidedLessonScope(
          controller: _controller,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double edge = constraints.maxWidth >= 720
                  ? AppSpacing.screenEdgeDesktop
                  : AppSpacing.screenEdgeMobile;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.calculatorMaxWidth,
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      edge + AppSpacing.sm,
                    ),
                    children: <Widget>[
                      _Hero(lesson: lesson),
                      for (int s = 0; s < lesson.steps.length; s++)
                        LessonStepView(lesson: lesson, step: s),
                      LessonTakeaway(guideTitle: lesson.guideTitle),
                      const SizedBox(height: AppSpacing.lg),
                      ToolHelpFooter(toolId: lesson.toolId),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One step as a numbered landmark section. [only] limits it to those block
/// indexes (Present's stage).
class LessonStepView extends StatelessWidget {
  const LessonStepView({
    super.key,
    required this.lesson,
    required this.step,
    this.only,
  });

  final GuidedLesson lesson;
  final int step;
  final List<int>? only;

  @override
  Widget build(BuildContext context) {
    final LessonStep s = lesson.steps[step];
    final List<int> indexes =
        only ?? List<int>.generate(s.blocks.length, (int i) => i);
    return LessonSection(
      number: s.number,
      spokenNumber: s.spoken,
      title: s.title,
      children: <Widget>[
        for (final int i in indexes)
          LessonBlockView(block: s.blocks[i], step: step, index: i),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.lesson});

  final GuidedLesson lesson;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (lesson.cover != null) ...<Widget>[
            LessonFigureView(lesson.cover!),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (lesson.tagline != null) ...<Widget>[
            Text(
              lesson.tagline!,
              style: (t.labelMedium ?? const TextStyle()).copyWith(
                color: colors.textAccent,
                fontFamily: 'DM Mono',
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          LessonRich(
            lesson.promise,
            style: (t.titleMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              height: 1.4,
            ),
          ),
          for (final String line in lesson.byline) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            LessonRich(
              line,
              style: lessonBody(
                context,
                small: true,
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Present mode.
// ─────────────────────────────────────────────────────────────────────────────

/// The smallest text Present may show, in logical pixels on the stage: the
/// ≈10.4 CSS px rendered constant of GL-003 §7.2-4, "the smallest glyph this
/// brand stands behind." A mirror of that clause, never a source for it.
///
/// It is checked as the gate measures it: a paragraph's style font size
/// times the stage's scale-to-fit. The projector text scale Present applies
/// on top (PresenterScale.forWindow, never below 1.1x) is left out, so the
/// check errs large.
const double kLessonPresentTextFloor = 10.4;

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

/// One stage block measured at the stage width: its height inside a step's
/// section, less the section's own header and padding, and its smallest
/// font size.
typedef _Measure = ({double height, double minFont});

/// PRESENT FITS EACH SLIDE TO THE WINDOW. A step is laid out at the stage
/// width and scaled down to the stage height. A step with two or more tall
/// figures scaled so far that its text fell under the floor (How GPS Works
/// step 4 at 3.9 px), so the stage measures every step offstage, once per
/// stage size, and splits any slide whose text would land under
/// [kLessonPresentTextFloor] into parts
/// ([GuidedLessonController.splitToFit]). Each block is measured with every
/// fact revealed, so pressing Space never pushes a slide under the floor.
/// The phone screen never measures and never splits.
class _StageState extends State<_Stage> {
  Size? _fittedFor;
  Size? _measuring;
  final Map<(int, int?), GlobalKey> _keys = <(int, int?), GlobalKey>{};
  GuidedLessonController? _revealAll;

  @override
  void dispose() {
    _revealAll?.dispose();
    super.dispose();
  }

  GlobalKey _key(int step, int? block) =>
      _keys.putIfAbsent((step, block), GlobalKey.new);

  /// A controller over the same lesson with every fact showing, so a myth is
  /// measured at its tallest.
  GuidedLessonController _revealed(GuidedLesson lesson) {
    final GuidedLessonController? had = _revealAll;
    if (had != null && identical(had.lesson, lesson)) return had;
    had?.dispose();
    final GuidedLessonController c = GuidedLessonController(lesson);
    for (int s = 0; s < lesson.steps.length; s++) {
      for (int b = 0; b < lesson.steps[s].blocks.length; b++) {
        if (lesson.steps[s].blocks[b] is LessonMyth) {
          c.toggle(LessonBlockRef(s, b));
        }
      }
    }
    return _revealAll = c;
  }

  /// Every block that goes on some stage, per step.
  static Map<int, Set<int>> _stageBlocks(GuidedLessonController c) {
    final Map<int, Set<int>> out = <int, Set<int>>{};
    for (final LessonSlide s in c.baseSlides) {
      out.putIfAbsent(s.step, () => <int>{}).addAll(s.stage);
    }
    return out;
  }

  Widget _measureTree(GuidedLessonController c, double width) {
    final Map<int, Set<int>> blocks = _stageBlocks(c);
    return ExcludeFocus(
      child: TickerMode(
        enabled: false,
        child: GuidedLessonScope(
          controller: _revealed(c.lesson),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final MapEntry<int, Set<int>> e
                    in blocks.entries) ...<Widget>[
                  KeyedSubtree(
                    key: _key(e.key, null),
                    child: LessonStepView(
                      lesson: c.lesson,
                      step: e.key,
                      only: const <int>[],
                    ),
                  ),
                  for (final int b in e.value)
                    KeyedSubtree(
                      key: _key(e.key, b),
                      child: LessonStepView(
                        lesson: c.lesson,
                        step: e.key,
                        only: <int>[b],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _minFont(RenderObject root) {
    double m = double.infinity;
    void visit(RenderObject o) {
      if (o is RenderParagraph) {
        o.text.visitChildren((InlineSpan span) {
          final double? f = span.style?.fontSize;
          if (f != null && f < m) m = f;
          return true;
        });
      }
      o.visitChildren(visit);
    }

    visit(root);
    return m;
  }

  _Measure? _read(int step, int? block) {
    final RenderObject? r = _keys[(step, block)]?.currentContext
        ?.findRenderObject();
    if (r is! RenderBox || !r.hasSize) return null;
    return (height: r.size.height, minFont: _minFont(r));
  }

  void _fit(GuidedLessonController c, Size size) {
    if (!mounted || _measuring != size) return;
    final List<LessonSlide> fitted = <LessonSlide>[];
    for (final LessonSlide base in c.baseSlides) {
      final int step = base.step;
      final _Measure? header = _read(step, null);
      final Map<int, _Measure> own = <int, _Measure>{};
      for (final int b in base.stage) {
        final _Measure? m = _read(step, b);
        if (header == null || m == null) break;
        // What the block adds to a section: its gap and its own height.
        own[b] = (height: m.height - header.height, minFont: m.minFont);
      }
      if (header == null || own.length != base.stage.length) {
        fitted.add(base); // Not measured: show the slide as the data has it.
        continue;
      }
      bool fits(List<int> run) {
        double h = header.height;
        double font = header.minFont;
        for (final int b in run) {
          h += own[b]!.height;
          font = math.min(font, own[b]!.minFont);
        }
        final double scale = h <= size.height ? 1 : size.height / h;
        return font.isInfinite ||
            font * scale >= kLessonPresentTextFloor - 1e-6;
      }

      final List<LessonBlock> blocks = c.lesson.steps[step].blocks;
      for (final List<int> part in GuidedLessonController.splitToFit(
        base.stage,
        isFigure: (int b) => blocks[b] is LessonFigure,
        fits: fits,
      )) {
        fitted.add(LessonSlide(step, part));
      }
    }
    c.fitSlides(fitted);
    setState(() {
      _fittedFor = size;
      _measuring = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final GuidedLessonController c = GuidedLessonScope.of(context);
    final LessonSlide slide = c.current;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = math.min(box.maxWidth, kLessonStageMaxWidth);
        final Widget stage = Align(
          alignment: Alignment.topCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: w,
              child: LessonStepView(
                key: ValueKey<int>(c.slide),
                lesson: c.lesson,
                step: slide.step,
                only: slide.stage,
              ),
            ),
          ),
        );
        final Size size = box.biggest;
        if (!box.hasBoundedHeight ||
            !box.hasBoundedWidth ||
            _fittedFor == size) {
          return stage;
        }
        if (_measuring != size) {
          _measuring = size;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fit(c, size));
        }
        return Stack(
          children: <Widget>[
            Offstage(child: _measureTree(c, w)),
            stage,
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final GuidedLessonController c = GuidedLessonScope.of(context);
    final LessonSlide slide = c.current;
    final LessonStep step = c.lesson.steps[slide.step];
    final Set<int> onStage = <int>{
      for (final LessonSlide s in c.slides)
        if (s.step == slide.step) ...s.stage,
    };
    final TextTheme t = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              key: GuidedLessonScreen.previousKey,
              onPressed: c.atFirst ? null : c.previous,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Previous'),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Step ${slide.step + 1} of ${c.lesson.steps.length}'
                  '${_part(c)}',
                  key: GuidedLessonScreen.counterKey,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            FilledButton.icon(
              key: GuidedLessonScreen.nextKey,
              onPressed: c.atLast ? null : c.next,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
            ),
          ],
        ),
        for (int i = 0; i < step.blocks.length; i++)
          if (!onStage.contains(i)) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            LessonBlockView(block: step.blocks[i], step: slide.step, index: i),
          ],
      ],
    );
  }

  /// ", part 2 of 3" when a step spans several slides.
  static String _part(GuidedLessonController c) {
    final ({int part, int of}) p = c.partOfStep;
    return p.of < 2 ? '' : ', part ${p.part} of ${p.of}';
  }
}
