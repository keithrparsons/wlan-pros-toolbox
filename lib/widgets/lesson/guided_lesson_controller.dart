// The one state object a Guided Lesson has: which Present slide is showing,
// and which myths have their fact revealed. The phone screen and Present mode
// read the same object (presenter adoption rule 1, lib/widgets/presenter/
// presenter.dart), so a fact revealed on one is revealed on the other.
//
// Lifted from the Devices to Internet lesson's DevicesToInternetLesson
// (wifi-lab/lesson-devices-to-internet, devices_to_internet_explained_screen
// .dart), generalized from its hand-written slide table to one derived from
// the lesson data.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../presenter/presenter_actions.dart';
import 'guided_lesson.dart';

/// A myth's address in the lesson: its step and its block index.
@immutable
class LessonBlockRef {
  const LessonBlockRef(this.step, this.block);
  final int step;
  final int block;

  @override
  bool operator ==(Object other) =>
      other is LessonBlockRef && other.step == step && other.block == block;

  @override
  int get hashCode => Object.hash(step, block);

  @override
  String toString() => 'LessonBlockRef($step, $block)';
}

/// One Present slide: a step, and which of its blocks sit on the stage.
@immutable
class LessonSlide {
  const LessonSlide(this.step, this.stage);
  final int step;
  final List<int> stage;
}

class GuidedLessonController extends ChangeNotifier {
  GuidedLessonController(this.lesson)
    : baseSlides = List<LessonSlide>.unmodifiable(<LessonSlide>[
        for (int s = 0; s < lesson.steps.length; s++)
          for (final List<int> stage in slidesFor(lesson.steps[s]))
            LessonSlide(s, stage),
      ]);

  final GuidedLesson lesson;

  /// The slides the lesson data defines ([slidesFor]), before Present fits
  /// them to a window.
  final List<LessonSlide> baseSlides;

  /// The slides Present walks: [baseSlides] until Present's stage measures
  /// them, then [baseSlides] with any slide too tall to read split in parts
  /// (see [fitSlides]).
  List<LessonSlide> get slides => _slides;
  late List<LessonSlide> _slides = baseSlides;

  final Set<LessonBlockRef> _revealed = <LessonBlockRef>{};
  int _slide = 0;

  // ── Default slides ──────────────────────────────────────────────────────

  /// Blocks that go on the stage by default: the pictures and the short,
  /// large things a room reads from the back.
  static bool isStageKind(LessonBlock b) => switch (b) {
    LessonFigure() ||
    LessonMyth() ||
    LessonLede() ||
    LessonCards() ||
    LessonCallout() => true,
    _ => false,
  };

  /// Most task cards one appendix slide carries, so a projected task stays
  /// large enough to read from the back of a room.
  static const int tasksPerSlide = 2;

  /// A step's Present slides. [LessonStep.slides] wins when set. Otherwise
  /// one slide per step, with every stage-kind block on the stage and the
  /// rest in the panel. An appendix of tasks, a step whose only stage-kind
  /// blocks are ledes (or none at all) and that holds a task card, puts
  /// everything on the stage instead, split at its subheadings and then
  /// every [tasksPerSlide] task cards; the text before the first subheading
  /// or task rides on the first slide, and a subheading stays with the tasks
  /// under it. (A lede alone on the stage would leave the tasks, the point
  /// of the step, in the side panel.)
  static List<List<int>> slidesFor(LessonStep step) {
    if (step.slides != null) return step.slides!;
    final List<int> stage = <int>[
      for (int i = 0; i < step.blocks.length; i++)
        if (isStageKind(step.blocks[i])) i,
    ];
    final bool taskAppendix =
        step.blocks.any((LessonBlock b) => b is LessonTask) &&
        stage.every((int i) => step.blocks[i] is LessonLede);
    if (stage.isNotEmpty && !taskAppendix) return <List<int>>[stage];
    final List<List<int>> slides = <List<int>>[<int>[]];
    int tasks = 0;
    bool prelude = true;
    for (int i = 0; i < step.blocks.length; i++) {
      final LessonBlock b = step.blocks[i];
      final bool breakHere =
          (b is LessonHeading && !prelude) ||
          (b is LessonTask && tasks == tasksPerSlide);
      if (breakHere && slides.last.isNotEmpty) {
        slides.add(<int>[]);
        tasks = 0;
      }
      if (b is LessonHeading) prelude = false;
      if (b is LessonTask) {
        prelude = false;
        tasks++;
      }
      slides.last.add(i);
    }
    return slides;
  }

  // ── Fitting a slide to the window (Present) ─────────────────────────────

  /// Splits one slide's [stage] so every part fits the window with its text
  /// at or above the floor. [fits] answers for a run of block indexes in
  /// stage order; [isFigure] names the figures.
  ///
  /// A stage that fits stays one slide. Otherwise the blocks keep the guide's
  /// order and fill parts from the top: a block joins the part above it when
  /// the two still fit, and a figure never joins a part that already holds a
  /// figure, so each figure after the first gets a part of its own with its
  /// caption at full size. In the usual step (a lede, then its figures) the
  /// first part is the lede and the first figure, and each further figure
  /// follows alone. A single block that cannot fit even alone keeps a part of
  /// its own; nothing is ever dropped.
  static List<List<int>> splitToFit(
    List<int> stage, {
    required bool Function(int block) isFigure,
    required bool Function(List<int> blocks) fits,
  }) {
    if (stage.length < 2 || fits(stage)) return <List<int>>[stage];
    final List<List<int>> parts = <List<int>>[];
    List<int> part = <int>[];
    for (final int b in stage) {
      if (part.isEmpty) {
        part = <int>[b];
        continue;
      }
      final bool secondFigure = isFigure(b) && part.any(isFigure);
      final List<int> joined = <int>[...part, b];
      if (secondFigure || !fits(joined)) {
        parts.add(part);
        part = <int>[b];
      } else {
        part = joined;
      }
    }
    parts.add(part);
    return parts;
  }

  /// Present: walk [fitted] instead, a refinement of [baseSlides] that
  /// splits a slide the window cannot show at a readable size. The presenter
  /// stays on what they were showing: the new current slide is the part that
  /// holds the first block of the old one. Myth reveals are untouched.
  void fitSlides(List<LessonSlide> fitted) {
    assert(fitted.isNotEmpty, 'a lesson has at least one slide');
    if (_sameSlides(fitted, _slides)) return;
    final LessonSlide was = current;
    _slides = List<LessonSlide>.unmodifiable(fitted);
    int at = _slides.indexWhere(
      (LessonSlide s) =>
          s.step == was.step &&
          (was.stage.isEmpty
              ? s.stage.isEmpty
              : s.stage.contains(was.stage.first)),
    );
    if (at < 0) at = _slides.indexWhere((LessonSlide s) => s.step == was.step);
    _slide = at < 0 ? 0 : at;
    notifyListeners();
  }

  static bool _sameSlides(List<LessonSlide> a, List<LessonSlide> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].step != b[i].step || !listEquals(a[i].stage, b[i].stage)) {
        return false;
      }
    }
    return true;
  }

  /// Where the current slide sits among its step's slides: (1, 1) for a step
  /// on one slide, (2, 3) for the second of three.
  ({int part, int of}) get partOfStep {
    int first = _slide;
    while (first > 0 && _slides[first - 1].step == current.step) {
      first--;
    }
    int last = _slide;
    while (last < _slides.length - 1 &&
        _slides[last + 1].step == current.step) {
      last++;
    }
    return (part: _slide - first + 1, of: last - first + 1);
  }

  // ── Slides ──────────────────────────────────────────────────────────────

  int get slide => _slide;
  LessonSlide get current => slides[_slide];
  bool get atFirst => _slide == 0;
  bool get atLast => _slide == slides.length - 1;

  void next() {
    if (atLast) return;
    _slide++;
    notifyListeners();
  }

  void previous() {
    if (atFirst) return;
    _slide--;
    notifyListeners();
  }

  /// Present R: back to the first slide with every fact hidden again, the
  /// way the lesson opened.
  void reset() {
    if (_slide == 0 && _revealed.isEmpty) return;
    _slide = 0;
    _revealed.clear();
    notifyListeners();
  }

  // ── Myths ───────────────────────────────────────────────────────────────

  bool isRevealed(LessonBlockRef myth) => _revealed.contains(myth);

  void toggle(LessonBlockRef myth) {
    if (!_revealed.remove(myth)) _revealed.add(myth);
    notifyListeners();
  }

  /// The myths on the current slide's stage, in order.
  List<LessonBlockRef> get mythsOnSlide => <LessonBlockRef>[
    for (final int i in current.stage)
      if (lesson.steps[current.step].blocks[i] is LessonMyth)
        LessonBlockRef(current.step, i),
  ];

  /// Present Space: reveals the next hidden fact on this slide, top to
  /// bottom. Once every fact on the slide shows, Space hides them all, so a
  /// presenter can run the myths again. Does nothing on a slide with no myth.
  void revealNext() {
    final List<LessonBlockRef> myths = mythsOnSlide;
    if (myths.isEmpty) return;
    for (final LessonBlockRef m in myths) {
      if (!_revealed.contains(m)) {
        _revealed.add(m);
        notifyListeners();
        return;
      }
    }
    _revealed.removeAll(myths);
    notifyListeners();
  }

  /// The Present keys: Right and Left move a slide (through a step's parts,
  /// then on to the next step), Space reveals, R resets. F, Esc and ? are
  /// the shell's own.
  PresenterActions get presenterActions => PresenterActions(
    playPause: revealNext,
    playPauseLabel: 'Reveal the next fact (myth steps)',
    step: next,
    stepLabel: 'Next slide',
    reset: reset,
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Previous slide',
        onPressed: previous,
      ),
    ],
  );
}

/// Makes the controller reachable from any block below the lesson.
class GuidedLessonScope extends InheritedNotifier<GuidedLessonController> {
  const GuidedLessonScope({
    super.key,
    required GuidedLessonController controller,
    required super.child,
  }) : super(notifier: controller);

  static GuidedLessonController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GuidedLessonScope>()!
      .notifier!;

  static GuidedLessonController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuidedLessonScope>()?.notifier;
}
