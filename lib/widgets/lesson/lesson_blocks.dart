// Renders every LessonBlock kind. One widget per kind, and LessonBlockView,
// which picks one by exhaustive switch over the sealed LessonBlock, so a new
// block kind fails to compile until it has a renderer.
//
// Lifted from the Devices to Internet lesson (_Note, _Lede, _Cards, _Card,
// _Numbered, _Task, _MythCard, _LessonLink in wifi-lab/lesson-devices-to-
// internet), made public and data-driven, plus the Caution, Stop and Quote
// callouts that lesson did not need.
//
// GL-003 §12.10 in the app:
//  - Note and Quote: a 6px `statusInfo` bar on `statusInfoFill`; the Quote's
//    speaker label in `statusInfo`. Information, never warm (§12.2-0).
//  - Caution / Stop: a 6px `statusWarning` / `statusDanger` bar on its fill,
//    the word label CAUTION / STOP and the explainer set's warning.svg mark in
//    that hue, so the kind never rests on color alone (§12.2-1).
//  - Myth / fact: the stacked pair, tap to reveal. The myth bar and label in
//    `textTertiary`, the myth text in `textSecondary`; the fact bar and label
//    in `textAccent`, the fact in `textPrimary`. Never `statusSuccess`, no
//    fill, no panel (§12.10-2).
//
// THEME: context.colors only; AppSpacing, AppRadius for every size. The 6px,
// 4px and 2px bars and the 24px step disc are GL-003 §12 dimensions
// (§12.1-2, §12.2-1, §12.2-4), which have no App Mode token.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/tool_catalog.dart';
import '../../screens/tools/reference/lesson_parts.dart'
    hide LessonCallout, LessonMyth;
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import 'guided_lesson.dart';
import 'guided_lesson_controller.dart';
import 'lesson_figure_view.dart';

/// The explainer icon set's warning mark (GL-003 §12.2-1), copied unchanged
/// from myPKA Deliverables/2026-09-28-explainer-icon-set/svg/warning.svg.
const String kLessonWarningMark = 'assets/lesson-figures/_shared/warning.svg';

// GL-003 §12 dimensions (see the header).
const double _calloutBar = 6;
const double _mythBar = 2;
const double _factBar = 4;
const double _stepDisc = 24;
const double _markSize = 20;

/// Test handle for a myth's reveal control.
Key lessonMythKey(LessonBlockRef ref) =>
    ValueKey<String>('lesson-myth:${ref.step}:${ref.block}');

/// Renders one block of step [step] at index [index].
class LessonBlockView extends StatelessWidget {
  const LessonBlockView({
    super.key,
    required this.block,
    required this.step,
    required this.index,
  });

  final LessonBlock block;
  final int step;
  final int index;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      LessonLede(:final String text) => LessonLedeView(text),
      LessonText(:final String text, :final bool small) => LessonP(
        text,
        small: small,
      ),
      LessonHeading(:final String text) => LessonSub(text),
      final LessonCallout c => LessonCalloutView(c),
      final LessonFigure f => LessonFigureView(f),
      final LessonMyth m => LessonMythView(
        myth: m,
        ref: LessonBlockRef(step, index),
      ),
      LessonSteps(:final List<String> items) => LessonNumbered(items),
      LessonBullets(:final List<String> items) => LessonBulletList(items),
      LessonCards(:final List<LessonCardData> cards) => LessonCardGrid(cards),
      final LessonTask t => LessonTaskView(t),
      LessonSourceList(:final List<String> items) => LessonSources(items),
      LessonToolLink(
        :final String toolId,
        :final String? route,
        :final String? title,
      ) =>
        LessonToolLinkView(
          toolId,
          route: route,
          title: title,
          keySuffix: '-$step-$index',
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text.
// ─────────────────────────────────────────────────────────────────────────────

/// The larger opening sentence of a section.
class LessonLedeView extends StatelessWidget {
  const LessonLedeView(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return LessonRich(
      source,
      style: (t.titleMedium ?? const TextStyle()).copyWith(
        color: context.colors.textPrimary,
        height: 1.4,
      ),
    );
  }
}

TextStyle _labelStyle(BuildContext context, Color color) =>
    (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: color,
      fontFamily: 'DM Mono',
      fontWeight: FontWeight.w500,
      letterSpacing: 1.0,
    );

// ─────────────────────────────────────────────────────────────────────────────
// Callouts.
// ─────────────────────────────────────────────────────────────────────────────

class LessonCalloutView extends StatelessWidget {
  const LessonCalloutView(this.callout, {super.key});

  final LessonCallout callout;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = lessonBody(context);
    final LessonCallout c = callout;
    final (Color hue, Color fill) = switch (c.kind) {
      LessonCalloutKind.note ||
      LessonCalloutKind.quote => (colors.statusInfo, colors.statusInfoFill),
      LessonCalloutKind.caution => (
        colors.statusWarning,
        colors.statusWarningFill,
      ),
      LessonCalloutKind.stop => (colors.statusDanger, colors.statusDangerFill),
    };

    final List<Widget> lines = <Widget>[];
    switch (c.kind) {
      case LessonCalloutKind.caution:
      case LessonCalloutKind.stop:
        final String word = c.kind == LessonCalloutKind.stop
            ? 'STOP'
            : 'CAUTION';
        lines.add(
          Row(
            children: <Widget>[
              SvgPicture.asset(
                kLessonWarningMark,
                width: _markSize,
                height: _markSize,
                excludeFromSemantics: true,
                theme: SvgTheme(currentColor: hue),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(word, style: _labelStyle(context, hue)),
            ],
          ),
        );
        lines.add(const SizedBox(height: AppSpacing.xxs));
      case LessonCalloutKind.quote:
        // The label may name its source in italics, as the guide's does
        // (`.lab i`). Upper-casing leaves the __ markers intact.
        lines.add(
          LessonRich(
            c.speaker!.toUpperCase(),
            style: _labelStyle(context, hue),
          ),
        );
        lines.add(const SizedBox(height: AppSpacing.xxs));
      case LessonCalloutKind.note:
        if (c.title == null) {
          // §12.10-1: never color-only. A Note with no title carries the
          // info glyph.
          lines.add(
            Icon(
              Icons.info_outline,
              size: _markSize,
              color: hue,
              semanticLabel: 'Note',
            ),
          );
          lines.add(const SizedBox(height: AppSpacing.xxs));
        }
    }
    if (c.title != null) {
      lines.add(
        Semantics(
          header: true,
          child: LessonRich(
            c.title!,
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
      lines.add(const SizedBox(height: AppSpacing.xxs));
    }
    if (c.body.isNotEmpty) {
      lines.add(
        LessonRich(
          c.body,
          style: c.kind == LessonCalloutKind.quote
              ? base
              : base.copyWith(color: colors.textSecondary),
        ),
      );
    }
    if (c.steps.isNotEmpty) {
      if (c.body.isNotEmpty) lines.add(const SizedBox(height: AppSpacing.xs));
      lines.add(LessonNumbered(c.steps));
    }
    if (c.attribution != null) {
      lines.add(const SizedBox(height: AppSpacing.xxs));
      lines.add(
        LessonRich(
          c.attribution!,
          style: lessonBody(context, small: true, color: colors.textSecondary),
        ),
      );
    }

    return Semantics(
      container: true,
      label: switch (c.kind) {
        LessonCalloutKind.caution => 'Caution',
        LessonCalloutKind.stop => 'Stop',
        LessonCalloutKind.quote => lessonPlain(c.speaker!),
        LessonCalloutKind.note => null,
      },
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: _calloutBar, color: hue),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: lines,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Myth and fact.
// ─────────────────────────────────────────────────────────────────────────────

/// The stacked pair, tap to reveal. The revealed state lives on the
/// GuidedLessonController, so Present and the phone screen agree. Outside a
/// lesson (a widget test, a preview) it keeps its own state.
class LessonMythView extends StatefulWidget {
  const LessonMythView({super.key, required this.myth, required this.ref});

  final LessonMyth myth;
  final LessonBlockRef ref;

  @override
  State<LessonMythView> createState() => _LessonMythViewState();
}

class _LessonMythViewState extends State<LessonMythView> {
  bool _localOpen = false;

  @override
  Widget build(BuildContext context) {
    final GuidedLessonController? lesson = GuidedLessonScope.maybeOf(context);
    final bool open = lesson?.isRevealed(widget.ref) ?? _localOpen;
    void toggle() => lesson != null
        ? lesson.toggle(widget.ref)
        : setState(() => _localOpen = !_localOpen);
    final AppColorScheme colors = context.colors;

    Widget stacked({
      required double bar,
      required Color barColor,
      required List<Widget> children,
    }) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: bar, color: barColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        stacked(
          bar: _mythBar,
          barColor: colors.textTertiary,
          children: <Widget>[
            Text('MYTH', style: _labelStyle(context, colors.textTertiary)),
            const SizedBox(height: AppSpacing.xxs),
            LessonRich(
              widget.myth.myth,
              style: lessonBody(context, color: colors.textSecondary),
            ),
            Semantics(
              hint: open ? 'Hides the fact' : 'Reveals the fact under the myth',
              child: TextButton.icon(
                key: lessonMythKey(widget.ref),
                onPressed: toggle,
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    AppSpacing.minTouchTarget,
                    AppSpacing.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                ),
                icon: Icon(open ? Icons.visibility_off : Icons.visibility),
                label: Text(open ? 'Hide the fact' : 'Reveal the fact'),
              ),
            ),
          ],
        ),
        if (open) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            liveRegion: true,
            child: stacked(
              bar: _factBar,
              barColor: colors.textAccent,
              children: <Widget>[
                Text('FACT', style: _labelStyle(context, colors.textAccent)),
                const SizedBox(height: AppSpacing.xxs),
                LessonRich(widget.myth.fact, style: lessonBody(context)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lists, cards, tasks.
// ─────────────────────────────────────────────────────────────────────────────

/// A GL-003 §12.3 step list: a 24px disc in primary text with the numeral in
/// the canvas color, 8px to the text, 8px between steps. Each step is spoken
/// "Step n." first.
class LessonNumbered extends StatelessWidget {
  const LessonNumbered(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = lessonBody(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  width: _stepDisc,
                  height: _stepDisc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style:
                        (Theme.of(context).textTheme.labelSmall ??
                                const TextStyle())
                            .copyWith(
                              color: colors.surface0,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  label: 'Step ${i + 1}.',
                  child: LessonRich(items[i], style: base),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A bulleted list of facts at body size.
class LessonBulletList extends StatelessWidget {
  const LessonBulletList(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = lessonBody(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Text('•  ', style: s.copyWith(color: colors.textAccent)),
              ),
              Expanded(child: LessonRich(items[i], style: s)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Cards two to a row at 440 and wider, stacked on a narrow screen.
class LessonCardGrid extends StatelessWidget {
  const LessonCardGrid(this.cards, {super.key});

  final List<LessonCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final List<Widget> tiles = <Widget>[
          for (final LessonCardData d in cards) _Card(d),
        ];
        if (c.maxWidth < AppSpacing.gridTwoColBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                tiles[i],
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int r = 0; r < tiles.length; r += 2) ...<Widget>[
              if (r > 0) const SizedBox(height: AppSpacing.xs),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: tiles[r]),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: r + 1 < tiles.length
                          ? tiles[r + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.data);

  final LessonCardData data;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return LessonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (data.title != null) ...<Widget>[
            Semantics(
              header: true,
              child: LessonRich(
                data.title!,
                style: (t.titleSmall ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          LessonRich(
            data.body,
            style: lessonBody(
              context,
              small: true,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// An appendix task card: a title naming the task, the why line, the steps,
/// and a closing note.
class LessonTaskView extends StatelessWidget {
  const LessonTaskView(this.task, {super.key});

  final LessonTask task;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle small = lessonBody(
      context,
      small: true,
      color: colors.textSecondary,
    );
    return LessonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: LessonRich(
              task.title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (task.why != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            LessonRich(task.why!, style: small),
          ],
          if (task.steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            LessonNumbered(task.steps),
          ],
          if (task.after != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            LessonRich(task.after!, style: small),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Links and the closing row.
// ─────────────────────────────────────────────────────────────────────────────

/// An Open button for another tool, looked up in the catalog by id. No live
/// entry and no [route], no button: the sentence that names the tool still
/// reads.
class LessonToolLinkView extends StatelessWidget {
  const LessonToolLinkView(
    this.toolId, {
    super.key,
    this.route,
    this.title,
    this.keySuffix = '',
  });

  final String toolId;

  /// The fallback door for a tool with no catalog tile (see
  /// LessonToolLink.route).
  final String? route;
  final String? title;
  final String keySuffix;

  /// The route and title the button opens, or null when there is nothing
  /// to open.
  static ({String route, String title})? target(
    String toolId, {
    String? route,
    String? title,
  }) {
    final ToolEntry? entry = find(toolId);
    if (entry != null) return (route: entry.routeName, title: entry.title);
    if (route != null && title != null) return (route: route, title: title);
    return null;
  }

  static ToolEntry? find(String id) {
    for (final ToolCategory c in kToolCategories) {
      for (final ToolEntry t in c.tools) {
        if (t.id == id && t.isLive) return t;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ({String route, String title})? to = target(
      toolId,
      route: route,
      title: title,
    );
    if (to == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey<String>('lesson-link:$toolId$keySuffix'),
        onPressed: () => Navigator.of(context).pushNamed(to.route),
        icon: const Icon(Icons.open_in_new),
        label: Text('Open ${to.title}'),
      ),
    );
  }
}

/// The closing "Take it with you" row: the lesson follows a guide that is a
/// free PDF from WLAN Pros. The PDF is not bundled in the app.
class LessonTakeaway extends StatelessWidget {
  const LessonTakeaway({super.key, required this.guideTitle});

  final String guideTitle;

  static const Key rowKey = ValueKey<String>('lesson-take-it-with-you');

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Container(
        key: rowKey,
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                Icons.description_outlined,
                color: colors.textAccent,
                size: AppSpacing.md,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      'Take it with you',
                      style: (t.titleSmall ?? const TextStyle()).copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  LessonRich(
                    'This lesson follows __${guideTitle}__, a free PDF guide '
                    'from WLAN Pros.',
                    style: lessonBody(
                      context,
                      small: true,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
