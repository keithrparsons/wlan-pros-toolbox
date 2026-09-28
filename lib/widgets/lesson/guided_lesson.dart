// The Guided Lesson format: a lesson is data, and one screen renders it.
//
// A Wi-Fi Classroom Guided Lesson is built from an explainer guide's approved
// text (myPKA Deliverables/2026-09-27-home-classroom-build/
// GUIDED-LESSON-FROM-EXPLAINER.md). Each guide section becomes a [LessonStep];
// each paragraph, callout, figure, myth, list and task inside it becomes a
// [LessonBlock]. [GuidedLessonScreen] renders any [GuidedLesson] on a phone
// and in Present mode, so a new lesson is a const value and a thin screen
// class, nothing else.
//
// INLINE MARKUP in every text field: **bold**, __italic__, and {{UI name}}
// for a button, tab or menu name as the screen shows it (GL-003 §12.3). A
// screen reader gets the plain words, never a marker.
//
// FIGURES are the guide's own SVGs, lifted out of the guide HTML by
// tool/extract_lesson_figures.py into assets/lesson-figures/<slug>/. That
// script also writes figures.json with each figure's viewBox size and its
// caption in lesson markup.
//
// Everything here is const-constructible and immutable. There is no
// behavior in this file; see guided_lesson_controller.dart for state and
// lesson_blocks.dart for rendering.

import 'package:flutter/foundation.dart';

/// One lesson: its catalog identity, its opening, and its steps in guide
/// order.
@immutable
class GuidedLesson {
  const GuidedLesson({
    required this.toolId,
    required this.route,
    required this.title,
    required this.guideTitle,
    required this.promise,
    required this.steps,
    this.tagline,
    this.byline = const <String>[],
    this.cover,
  });

  /// Catalog tool id (`<slug>-explained`). Backs the help entry and tests.
  final String toolId;

  /// The lesson's route (an AppRouter constant). Present mode names its own
  /// route after it.
  final String route;

  /// App bar and Present top-bar title.
  final String title;

  /// The PDF guide this lesson follows, named in the closing "Take it with
  /// you" row ("Find My, Explained").
  final String guideTitle;

  /// The guide cover's small label ("A plain-English guide"). Optional.
  final String? tagline;

  /// The guide cover's one-sentence promise, shown under the cover art.
  final String promise;

  /// The cover's byline lines, verbatim ("Keith Parsons · CWNE #3").
  final List<String> byline;

  /// The cover art, shown at the top of the phone screen. Optional.
  final LessonFigure? cover;

  final List<LessonStep> steps;
}

/// One guide section.
@immutable
class LessonStep {
  const LessonStep({
    required this.number,
    required this.title,
    required this.blocks,
    this.spoken,
    this.slides,
  });

  /// The badge: "1", "2" ... for the body, "A" for an appendix, "→" for the
  /// sources.
  final String number;

  final String title;

  final List<LessonBlock> blocks;

  /// What a screen reader says for the badge when the glyph alone would not
  /// read well ("Appendix A", "Sources"). Null reads "Section" and the number.
  final String? spoken;

  /// Present mode, only when the default does not suit this step: one entry
  /// per slide, each the indexes into [blocks] that go on the stage. Blocks
  /// on no slide's stage go in the controls panel. Null uses the default
  /// (see GuidedLessonController.slidesFor).
  final List<List<int>>? slides;
}

/// A piece of a step. Sealed, so the renderer handles every kind.
@immutable
sealed class LessonBlock {
  const LessonBlock();
}

/// The larger opening sentence of a section (the guide's `.lede`).
final class LessonLede extends LessonBlock {
  const LessonLede(this.text);
  final String text;
}

/// A paragraph. [small] is the guide's `.small` register: secondary text at
/// the caption size.
final class LessonText extends LessonBlock {
  const LessonText(this.text, {this.small = false});
  final String text;
  final bool small;
}

/// A subheading inside a step (the guide's `h3`).
final class LessonHeading extends LessonBlock {
  const LessonHeading(this.text);
  final String text;
}

/// The four GL-003 §12.2-1 callout kinds. In the app (§12.10-1): Note and
/// Quote on `statusInfo`; Caution on `statusWarning`; Stop (the guide's
/// Danger) on `statusDanger`, each with its word label and the warning mark.
enum LessonCalloutKind { note, caution, stop, quote }

/// A callout. Use the named constructors; each carries only the fields its
/// kind uses.
final class LessonCallout extends LessonBlock {
  /// Information: a definition, "A word on the words", "About this guide", a
  /// tip. Skipping it costs nothing. Slate (`statusInfo`), never warm.
  const LessonCallout.note({
    this.title,
    required this.body,
    this.steps = const <String>[],
  }) : kind = LessonCalloutKind.note,
       speaker = null,
       attribution = null;

  /// The reader pays a cost (money, time, a feature) if they miss this.
  const LessonCallout.caution({
    required String this.title,
    required this.body,
    this.steps = const <String>[],
  }) : kind = LessonCalloutKind.caution,
       speaker = null,
       attribution = null;

  /// Safety, security, or loss that cannot be undone. Labeled "Stop".
  const LessonCallout.stop({
    required String this.title,
    required this.body,
    this.steps = const <String>[],
  }) : kind = LessonCalloutKind.stop,
       speaker = null,
       attribution = null;

  /// Someone's own published words, such as a Keith's note. [speaker] is the
  /// label ("Keith's note", or with its source, "Keith's note, from
  /// __Fix Your Own Wi-Fi__"); [attribution] is the guide's source line under
  /// the words, when it has one.
  const LessonCallout.quote({
    required String this.speaker,
    this.title,
    required this.body,
    this.attribution,
  }) : kind = LessonCalloutKind.quote,
       steps = const <String>[];

  final LessonCalloutKind kind;
  final String? title;
  final String body;
  final String? speaker;
  final String? attribution;

  /// A procedure inside the callout (GL-003 §12.2-2 rule 5), shown as a step
  /// list after [body]. Empty for most callouts.
  final List<String> steps;
}

/// One of the guide's figures, from its extracted SVG.
final class LessonFigure extends LessonBlock {
  const LessonFigure({
    required this.asset,
    required this.width,
    required this.height,
    this.caption,
    this.alt,
    this.maxWidth,
  });

  /// `assets/lesson-figures/<slug>/fig-NN.svg`.
  final String asset;

  /// The SVG's viewBox size (figures.json `viewBox`), so the lesson reserves
  /// the right box before the SVG loads and nothing jumps.
  final double width;
  final double height;

  /// "**Figure N. Title.** Explanation." in lesson markup. Null only for the
  /// cover art.
  final String? caption;

  /// What a screen reader says for the figure. Null uses the caption.
  final String? alt;

  /// The widest the figure is drawn inline, in logical pixels, for the few
  /// small figures the guide itself draws narrower. Null fills the column.
  final double? maxWidth;

  double get aspectRatio => width / height;
}

/// A myth and its fact: the GL-003 §12.10-2 stacked pair, tap to reveal.
final class LessonMyth extends LessonBlock {
  const LessonMyth({required this.myth, required this.fact});
  final String myth;
  final String fact;
}

/// A procedure (GL-003 §12.3): numbered steps, each one action.
final class LessonSteps extends LessonBlock {
  const LessonSteps(this.items);
  final List<String> items;
}

/// A bulleted list of facts.
final class LessonBullets extends LessonBlock {
  const LessonBullets(this.items);
  final List<String> items;
}

/// Short cards side by side (the guide's `.two` / `.three` grids).
final class LessonCards extends LessonBlock {
  const LessonCards(this.cards);
  final List<LessonCardData> cards;
}

@immutable
class LessonCardData {
  const LessonCardData({this.title, required this.body});
  final String? title;
  final String body;
}

/// A task card from the appendix: a title that names the task, an optional
/// why line, the steps, and an optional closing note.
final class LessonTask extends LessonBlock {
  const LessonTask({
    required this.title,
    this.why,
    this.steps = const <String>[],
    this.after,
  });
  final String title;
  final String? why;
  final List<String> steps;
  final String? after;
}

/// The guide's sources list.
final class LessonSourceList extends LessonBlock {
  const LessonSourceList(this.items);
  final List<String> items;
}

/// An Open button for another tool in the app, looked up in the catalog by
/// id. No live catalog entry, no button.
final class LessonToolLink extends LessonBlock {
  const LessonToolLink(this.toolId);
  final String toolId;
}
