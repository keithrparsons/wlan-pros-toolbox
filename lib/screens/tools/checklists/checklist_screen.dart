// ChecklistScreen — the reusable tappable-checklist screen type for the
// Checklists category (LOCKED 6-category map §6).
//
// A checklist is an optional intro paragraph followed by an ordered list of
// phases; each phase is a heading + an ordered list of items; each item is a
// line of text with an optional supporting note. A checklist with no phase
// structure is modeled as a single phase with `label == null` — the heading is
// then dropped and the items render as one ungrouped list.
//
// Interaction: every item is a tappable row carrying a session-local checked
// state (StatefulWidget; NOT persisted to disk for v1 — closing the screen
// resets it, which is the right default for a per-session field checklist). A
// progress indicator ("7 / 12 done") sits at the top and is announced to
// screen readers on every toggle, mirroring reason_codes' live-count
// announcement (WCAG 4.1.3).
//
// This file is the screen TYPE + data MODEL only. The two real checklists'
// content (How to NOT Have a Wireless Problem, Wi-Fi Client Testing Checklist)
// is produced separately by Pax (pax-research-7-additions.md) and dropped into
// `const Checklist` definitions that this screen renders verbatim. A built-in
// smoke-test definition (`Checklist.smokeTest`) exercises every path — single
// ungrouped list AND phased list, items with and without notes — so the type
// can be wired and gated before the real data lands.
//
// Style: GL-003 §8 tokens only (no literal hex / px). Item rows follow the
// §8.3 focus-ring-on-tappable-row idiom established in category_screen
// (_ToolRow): borderStrong 1px at rest, 2px lime ring on keyboard focus, 48dp
// min touch target, curated single Semantics label announcing the item text +
// checked state. Cards use surface1 / 12px radius / decorative border like
// every reference screen. A concept-graphic band renders at the top when the
// tool has a bundled graphic (ToolAssets.hasGraphic), same as the reference
// screens.
//
// States (SOP-007 §5): this is a static, in-memory checklist — there is no
// network, no async load, no parse. The only states are:
//   - success     → the phases + items render (the default and only data path).
//   - empty        → a checklist with zero items renders an honest "empty" card
//                    rather than a blank screen (defensive; real checklists are
//                    never empty).
//   - interactive  → per-item checked / unchecked, plus keyboard focus ring.
//   - "complete"   → a success-tinted progress line when every item is checked.
// There is no loading / error path (nothing is fetched) and no
// NetworkUnavailableView (fully offline on every platform).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// One actionable checklist item: a line of [text] with an optional supporting
/// [note]. Immutable content; the checked state lives in the screen, not here,
/// so the same const definition can be reused across screen instances.
@immutable
class ChecklistItem {
  const ChecklistItem(this.text, {this.note});

  /// The thing to do / verify. The primary, always-present line.
  final String text;

  /// Optional one-line elaboration shown beneath [text] in tertiary ink.
  final String? note;
}

/// An ordered group of items under an optional heading. A `null` [label]
/// renders the items as a single ungrouped list with no heading — the model
/// for a flat, unphased checklist.
@immutable
class ChecklistPhase {
  const ChecklistPhase({this.label, required this.items});

  /// Phase heading, e.g. "Before you start". `null` → ungrouped (no heading).
  final String? label;

  /// The items in this phase, in display order.
  final List<ChecklistItem> items;
}

/// A complete checklist: an optional [intro] paragraph plus ordered [phases].
/// A flat checklist is a single phase with `label == null`.
@immutable
class Checklist {
  const Checklist({
    required this.title,
    this.intro,
    required this.phases,
  });

  /// AppBar title and the screen's semantic heading.
  final String title;

  /// Optional intro paragraph rendered above the first phase.
  final String? intro;

  /// Ordered phases. Each holds its own ordered items.
  final List<ChecklistPhase> phases;

  /// Total item count across all phases — the progress denominator.
  int get totalItems =>
      phases.fold<int>(0, (int sum, ChecklistPhase p) => sum + p.items.length);

  /// Built-in smoke-test checklist. Exercises every render path: a flat
  /// ungrouped phase, a labeled phase, and items both with and without notes.
  /// Used by the widget test and as a temporary route target until Pax's real
  /// checklist data lands. NOT shipped on the home grid (its category is
  /// deferred from the catalog) — it exists so the type is gate-able now.
  static const Checklist smokeTest = Checklist(
    title: 'Checklist',
    intro:
        'A reusable tappable checklist. Tap a row to mark it done; the count '
        'at the top tracks progress. State is per session and is not saved.',
    phases: <ChecklistPhase>[
      ChecklistPhase(
        label: 'Before you start',
        items: <ChecklistItem>[
          ChecklistItem(
            'Confirm the SSID and band the client expects to join',
            note: 'A 2.4 GHz-only client never sees a 6 GHz-only SSID.',
          ),
          ChecklistItem('Note the client make, model, and OS version'),
        ],
      ),
      ChecklistPhase(
        label: 'On site',
        items: <ChecklistItem>[
          ChecklistItem(
            'Measure RSSI and SNR at the client location',
            note: 'Target -67 dBm RSSI / 25 dB SNR for voice.',
          ),
          ChecklistItem('Verify the client associates to the nearest AP'),
          ChecklistItem('Capture a roaming event end to end'),
        ],
      ),
    ],
  );
}

/// Renders a [Checklist] as an interactive, session-state tappable list.
///
/// Pass a [checklist] definition (Pax's data, or [Checklist.smokeTest]). The
/// screen owns the per-item checked state and never persists it (v1).
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({
    super.key,
    required this.checklist,
    this.toolId,
  });

  /// The checklist content to render. Title, intro, phases, and items all come
  /// from here so one screen type serves every checklist.
  final Checklist checklist;

  /// Catalog id (kebab-case) used to resolve a concept-graphic band, when one
  /// is bundled. `null` (or an id with no bundled graphic) renders no band —
  /// the §8.6.2 graceful-degradation contract.
  final String? toolId;

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  /// Checked state keyed by a stable (phaseIndex, itemIndex) pair. Absent /
  /// false → not done. Session-only; never written to disk (v1).
  final Set<({int phase, int item})> _done = <({int phase, int item})>{};

  int get _doneCount => _done.length;
  int get _totalCount => widget.checklist.totalItems;

  bool _isDone(int phase, int item) =>
      _done.contains((phase: phase, item: item));

  void _toggle(int phase, int item) {
    final ({int phase, int item}) key = (phase: phase, item: item);
    setState(() {
      if (!_done.remove(key)) _done.add(key);
    });
    // WCAG 4.1.3 — announce the new progress count so AT users hear the list
    // advance without focus leaving the row. Mirrors reason_codes' live count.
    final int done = _doneCount;
    final int total = _totalCount;
    SemanticsService.sendAnnouncement(
      View.of(context),
      done == total
          ? 'All $total items done'
          : '$done of $total done',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.checklist.title),
        toolbarHeight: 64,
        // The per-tool help moved out of the AppBar to the ToolHelpFooter at the
        // end of the scroll body (§8.16.1). This screen type has no AppBar
        // action; help is keyed to the SPECIFIC checklist id in the footer below
        // and self-omits when toolId is null or has no help entry.
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    final Checklist cl = widget.checklist;
    final bool isEmpty = _totalCount == 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        final List<Widget> children = <Widget>[];

        final bool hasGraphic =
            widget.toolId != null && ToolAssets.hasGraphic(widget.toolId!);
        if (hasGraphic) {
          children.add(
            ConceptGraphicBand(toolId: widget.toolId!, isDesktop: isDesktop),
          );
          children.add(const SizedBox(height: AppSpacing.md));
        }

        if (isEmpty) {
          children.add(const _EmptyCard());
        } else {
          children.add(_ProgressCard(done: _doneCount, total: _totalCount));
          children.add(const SizedBox(height: AppSpacing.sm));

          if (cl.intro != null) {
            children.add(_IntroCard(intro: cl.intro!));
            children.add(const SizedBox(height: AppSpacing.sm));
          }

          for (int p = 0; p < cl.phases.length; p++) {
            children.add(
              _PhaseCard(
                phase: cl.phases[p],
                isDone: (int item) => _isDone(p, item),
                onToggle: (int item) => _toggle(p, item),
              ),
            );
            if (p != cl.phases.length - 1) {
              children.add(const SizedBox(height: AppSpacing.sm));
            }
          }
        }

        // §8.16.1 — per-tool help footer at the end of the scroll body. Only
        // when this checklist carries a real tool id (ToolHelpFooter requires a
        // non-null id; it self-omits when the id has no authored help entry).
        if (widget.toolId != null) {
          children.add(ToolHelpFooter(toolId: widget.toolId!));
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Progress readout. Renders "N / M done" with a thin progress bar. Turns the
/// success color (not lime — §8.13: lime is "computed", success is a verdict)
/// when every item is checked. The bar is decorative; the text carries the
/// state, and the live count is announced on toggle, so this is not color-only.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool complete = total > 0 && done == total;
    final double fraction = total == 0 ? 0 : done / total;
    final Color barColor =
        complete ? colors.statusSuccess : colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      // The progress count is announced live on toggle; this node carries the
      // resting summary so AT lands on it as a labeled status, not raw text.
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: complete
            ? 'Progress, all $total items done'
            : 'Progress, $done of $total done',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progress',
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  '$done / $total done',
                  style: mono.inlineCode.copyWith(
                    color: complete
                        ? colors.statusSuccess
                        : colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: colors.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Intro paragraph card — tertiary ink on a standard surface1 card.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.intro});

  final String intro;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        intro,
        style: text.labelMedium?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// One phase: an optional heading followed by its item rows in a bordered card.
/// A `null` phase label drops the heading entirely (flat ungrouped checklist).
class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.phase,
    required this.isDone,
    required this.onToggle,
  });

  final ChecklistPhase phase;
  final bool Function(int item) isDone;
  final void Function(int item) onToggle;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phase.label != null) ...[
            Text(
              phase.label!,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (int i = 0; i < phase.items.length; i++)
            _ChecklistRow(
              item: phase.items[i],
              done: isDone(i),
              onToggle: () => onToggle(i),
            ),
        ],
      ),
    );
  }
}

/// One tappable item row: a check box affordance, the item text, and an
/// optional note. Carries session-local focus state and renders the §8.3 lime
/// focus ring on keyboard focus, exactly like category_screen's `_ToolRow`.
/// 48dp min touch target. A single curated Semantics label announces the item
/// text + checked state; the row is a toggleable button to AT.
class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    required this.item,
    required this.done,
    required this.onToggle,
  });

  final ChecklistItem item;
  final bool done;
  final VoidCallback onToggle;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  // §8.9 — keyboard focus must stay visible. The app-wide §8.3 pass cleared the
  // global focusColor to transparent, so we track focus locally and paint the
  // 2px lime ring ourselves, matching _ToolRow.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool done = widget.done;

    // §8.3 focus ring on the focusable row. Lime 2px on focus; the row at rest
    // has no border (it sits inside the phase card) so focus is the only ring.
    final BoxDecoration decoration = _focused
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colors.textAccent, width: 2),
          )
        : const BoxDecoration();

    // Curated label so AT hears the state and the item as one node, e.g.
    // "Checked. Measure RSSI and SNR at the client location. Target -67 dBm…".
    final String note = widget.item.note == null ? '' : ' ${widget.item.note}';
    final String label =
        '${done ? 'Checked' : 'Not checked'}. ${widget.item.text}$note';

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      toggled: done,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onToggle,
          onFocusChange: (bool hasFocus) {
            if (hasFocus != _focused) {
              setState(() => _focused = hasFocus);
            }
          },
          child: Container(
            decoration: decoration,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xs,
              horizontal: AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Check affordance — lime filled box when done, outlined
                // borderStrong box when not. 24px glyph centered in the touch
                // region. Decorative (the curated row label carries the state).
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    done
                        ? Icons.check_box_outlined
                        : Icons.check_box_outline_blank,
                    size: 24,
                    color: done ? colors.textAccent : colors.borderStrong,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.text,
                        style: text.bodyMedium?.copyWith(
                          color: done
                              ? colors.textTertiary
                              : colors.textPrimary,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          decorationColor: colors.textTertiary,
                        ),
                      ),
                      if (widget.item.note != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.item.note!,
                          style: text.labelMedium?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
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

/// Defensive empty state — a checklist with zero items. Real checklists are
/// never empty; this keeps the screen honest rather than blank if one is.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.checklist_outlined,
            size: 20,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This checklist has no items yet.',
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
