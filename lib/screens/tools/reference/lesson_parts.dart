// Building blocks for the interactive Guided Lessons in the Wi-Fi Classroom
// (Public Wi-Fi, Wi-Fi Privacy Myths). They follow Find My, Explained
// (find_my_explained_screen.dart) block for block: the same numbered-section
// landmarks, paragraph register, callouts, myth/fact pairs and sources list,
// lifted here so a lesson with an interactive control does not carry a third
// private copy. Find My keeps its own; this file does not change it.
//
// Inline markup in lesson copy: **bold**, __italic__, and {{UI name}} for a
// button, tab or menu name exactly as the screen shows it, drawn as a GL-003
// §12.3 UI-label chip. A screen reader gets the plain string, never a
// marker.
//
// THEME: every color from `context.colors`; spacing and radii from AppSpacing /
// AppRadius. No raw hex, no AppColors.*.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scaffold.
// ─────────────────────────────────────────────────────────────────────────────

/// The lesson page: app bar, one centered scrolling column at the reading
/// width, and the tool-help footer last.
class LessonScaffold extends StatelessWidget {
  const LessonScaffold({
    super.key,
    required this.title,
    required this.toolId,
    required this.children,
  });

  final String title;
  final String toolId;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), toolbarHeight: 64),
      body: SafeArea(
        top: false,
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
                    ...children,
                    ToolHelpFooter(toolId: toolId),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline markup.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _markup = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\{\{(.+?)\}\}');

List<InlineSpan> _spans(String source, {InlineSpan Function(String)? chip}) {
  final List<InlineSpan> out = <InlineSpan>[];
  int at = 0;
  for (final RegExpMatch m in _markup.allMatches(source)) {
    if (m.start > at) out.add(TextSpan(text: source.substring(at, m.start)));
    if (m.group(1) != null) {
      out.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (m.group(2) != null) {
      out.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      out.add(
        chip?.call(m.group(3)!) ??
            TextSpan(
              text: m.group(3),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
      );
    }
    at = m.end;
  }
  if (at < source.length) out.add(TextSpan(text: source.substring(at)));
  return out;
}

/// [source] with its markup removed: what a screen reader says and what the
/// tests look up.
String lessonPlain(String source) => source.replaceAllMapped(
  _markup,
  (Match m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '',
);

/// Body text style: bodyMedium (or bodySmall when [small]) in [color], default
/// primary text.
TextStyle lessonBody(BuildContext context, {bool small = false, Color? color}) {
  final TextTheme t = Theme.of(context).textTheme;
  final TextStyle base =
      (small ? t.bodySmall : t.bodyMedium) ?? const TextStyle();
  return base.copyWith(
    color: color ?? context.colors.textPrimary,
    height: small ? 1.45 : 1.5,
  );
}

/// Rich text over [source]'s markup; semantics carry the plain string.
class LessonRich extends StatelessWidget {
  const LessonRich(this.source, {super.key, required this.style});

  final String source;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // GL-003 §12.3 UI label: the name in semibold primary text on a raised
    // surface with a hairline border. It never wraps inside itself, so a
    // long path breaks between names, as the guide's does.
    InlineSpan chip(String name) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: colors.surface2,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          name,
          style: style.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
    return Text.rich(
      TextSpan(children: _spans(source, chip: chip)),
      style: style,
      semanticsLabel: lessonPlain(source),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero, sections, paragraphs.
// ─────────────────────────────────────────────────────────────────────────────

/// The eyebrow and one-sentence promise at the top of a lesson.
class LessonHero extends StatelessWidget {
  const LessonHero({super.key, required this.eyebrow, required this.promise});

  final String eyebrow;
  final String promise;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            eyebrow,
            style: (t.labelMedium ?? const TextStyle()).copyWith(
              color: colors.textAccent,
              fontFamily: 'DM Mono',
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            promise,
            style: (t.titleMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered section: a landmark header, then its blocks with even spacing.
class LessonSection extends StatelessWidget {
  const LessonSection({
    super.key,
    required this.number,
    required this.title,
    required this.children,
    this.spokenNumber,
  });

  final String number;
  final String title;
  final List<Widget> children;

  /// What a screen reader says for the badge when the glyph alone would not
  /// read well ("Sources" rather than an arrow).
  final String? spokenNumber;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            label: '${spokenNumber ?? 'Section $number'}. $title',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    number,
                    textAlign: TextAlign.center,
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: (text.titleMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final Widget c in children) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            c,
          ],
        ],
      ),
    );
  }
}

/// A subheading inside a section.
class LessonSub extends StatelessWidget {
  const LessonSub(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: (t.titleSmall ?? const TextStyle()).copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A body paragraph. [small] is the notes-and-sources register, in secondary
/// text.
class LessonP extends StatelessWidget {
  const LessonP(this.source, {super.key, this.small = false});

  final String source;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return LessonRich(
      source,
      style: lessonBody(
        context,
        small: small,
        color: small ? context.colors.textSecondary : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards, callouts, myths, sources.
// ─────────────────────────────────────────────────────────────────────────────

/// A plain bordered card on surface1, the container every interactive block
/// sits in.
class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

/// The small mono label that heads an interactive block ("Try it", "Predict,
/// then reveal").
class LessonLabel extends StatelessWidget {
  const LessonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
          .copyWith(
            color: context.colors.textAccent,
            fontFamily: 'DM Mono',
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
          ),
    );
  }
}

enum LessonTone { accent, warning }

/// A titled callout with a filled rail. The title carries the meaning, so the
/// rail color is never the only cue.
class LessonCallout extends StatelessWidget {
  const LessonCallout({
    super.key,
    required this.title,
    required this.body,
    this.tone = LessonTone.accent,
  });

  final String title;
  final String body;
  final LessonTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color rail = tone == LessonTone.warning
        ? colors.statusWarning
        : colors.primary;
    final TextStyle base = lessonBody(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: colors.isLight ? 4 : 3, color: rail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: base.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    LessonRich(body, style: base),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A myth and its fact: the GL-003 §12.10-2 stacked pair is LessonMythView in
// lib/widgets/lesson/lesson_blocks.dart. The red two-panel LessonMyth that
// lived here was retired on 2026-09-28 (§12.2-4: no red in a myth).

/// A bulleted sources list in the small register.
class LessonSources extends StatelessWidget {
  const LessonSources(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = lessonBody(
      context,
      small: true,
      color: colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Text(
                    '•  ',
                    style: s.copyWith(color: colors.textAccent),
                  ),
                ),
                // A source may name a book in italics (__Title__).
                Expanded(child: LessonRich(item, style: s)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Predict, then reveal": a question, a button that shows and hides the
/// answer, and the answer in a live region so a screen reader hears it
/// appear.
class LessonPredict extends StatefulWidget {
  const LessonPredict({
    super.key,
    required this.question,
    required this.answer,
    this.after,
  });

  final String question;
  final String answer;

  /// Optional control shown under the answer (for instance, a button that
  /// sets the lesson's control to the case the answer describes).
  final Widget? after;

  @override
  State<LessonPredict> createState() => _LessonPredictState();
}

class _LessonPredictState extends State<LessonPredict> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return LessonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LessonLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.question,
            style: t.titleMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.visibility_off : Icons.visibility),
              label: Text(_open ? 'Hide the answer' : 'Reveal the answer'),
            ),
          ),
          if (_open) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: LessonRich(widget.answer, style: lessonBody(context)),
            ),
            if (widget.after != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Align(alignment: Alignment.centerLeft, child: widget.after),
            ],
          ],
        ],
      ),
    );
  }
}
