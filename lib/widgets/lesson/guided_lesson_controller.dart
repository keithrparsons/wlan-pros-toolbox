// The one state object a Guided Lesson has: which Present slide is showing,
// and which myths have their fact revealed. The phone screen and Present mode
// read the same object (presenter adoption rule 1, lib/widgets/presenter/
// presenter.dart), so a fact revealed on one is revealed on the other.
//
// Lifted from the Devices to Internet lesson's DevicesToInternetLesson
// (wifi-lab/lesson-devices-to-internet, devices_to_internet_explained_screen
// .dart), generalized from its hand-written slide table to one derived from
// the lesson data.

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
    : slides = List<LessonSlide>.unmodifiable(<LessonSlide>[
        for (int s = 0; s < lesson.steps.length; s++)
          for (final List<int> stage in slidesFor(lesson.steps[s]))
            LessonSlide(s, stage),
      ]);

  final GuidedLesson lesson;
  final List<LessonSlide> slides;

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
  /// rest in the panel. A step with no stage-kind block at all (an appendix
  /// of tasks) puts everything on the stage instead, split at its
  /// subheadings and then every [tasksPerSlide] task cards; the text before
  /// the first subheading rides on the first slide, and a subheading stays
  /// with the tasks under it.
  static List<List<int>> slidesFor(LessonStep step) {
    if (step.slides != null) return step.slides!;
    final List<int> stage = <int>[
      for (int i = 0; i < step.blocks.length; i++)
        if (isStageKind(step.blocks[i])) i,
    ];
    if (stage.isNotEmpty) return <List<int>>[stage];
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

  /// The Present keys: Right and Left move a step, Space reveals, R resets.
  /// F, Esc and ? are the shell's own.
  PresenterActions get presenterActions => PresenterActions(
    playPause: revealNext,
    playPauseLabel: 'Reveal the next fact (myth steps)',
    step: next,
    stepLabel: 'Next step',
    reset: reset,
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Previous step',
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
