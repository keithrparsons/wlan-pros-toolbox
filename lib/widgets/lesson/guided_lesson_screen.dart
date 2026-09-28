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
// Previous / Next, the slide count and the rest of the step's text.
// Keys: Right and Left move a step, Space reveals the next fact on a myth
// step, R goes back to the first step with every fact hidden, F switches
// full screen, ? lists the keys, Esc exits.
//
// STATES (SOP-007 §5): the lesson is bundled data with no network, so the
// rendered state is success. A figure that fails to load says so in its
// card, and its caption still reads. A link to a tool that is not in the
// build draws nothing. Interactive: figure zoom, myth reveal, tool links,
// Previous / Next, all keyboard-reachable with the theme's focus ring.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../screens/tools/reference/lesson_parts.dart'
    hide LessonCallout, LessonMyth;
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

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) {
    final GuidedLessonController c = GuidedLessonScope.of(context);
    final LessonSlide slide = c.current;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = math.min(box.maxWidth, kLessonStageMaxWidth);
        return Align(
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
    final int step = c.current.step;
    final List<int> ofStep = <int>[
      for (int i = 0; i < c.slides.length; i++)
        if (c.slides[i].step == step) i,
    ];
    if (ofStep.length < 2) return '';
    return ', part ${ofStep.indexOf(c.slide) + 1} of ${ofStep.length}';
  }
}
