// ToolRow — the shared tool list row, used by the category screen (grouped) and
// the global search results screen.
//
// Extracted from category_screen.dart's former private _ToolRow so both surfaces
// render identical rows (Tickets 1 + 2). It keeps every behavior the original
// had — the §8.3 lime focus ring on keyboard focus, the §8.1 interactive
// boundary at rest, the Tier-2 SVG icon resolver with graceful fallback, the
// "Coming soon" disabled affordance, and the §8.9 collapsed-semantics label —
// and adds three OPTIONAL extras for search:
//   * a lime-highlighted match span in the title ([highlightQuery], §8.3 lime is
//     the active/match accent),
//   * a neutral content-type chip (§8.17, via [contentType]),
//   * a neutral category source tag + optional "matches in content" note for
//     description/keyword-only hits (mockup 04).
//
// All extras default off, so the category screen gets the original row exactly.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/content_type.dart';
import '../data/tool_assets.dart';
import '../data/tool_catalog.dart';
import '../theme/app_tokens.dart';
import 'content_type_chip.dart';

class ToolRow extends StatefulWidget {
  const ToolRow({
    required this.tool,
    this.onTap,
    this.highlightQuery,
    this.contentType,
    this.categorySourceLabel,
    this.matchNote,
    super.key,
  });

  /// The tool this row represents.
  final ToolEntry tool;

  /// Tap handler. When null, a LIVE tool defaults to
  /// `Navigator.pushNamed(tool.routeName)`; a non-live tool is always inert.
  /// Search passes an explicit handler so it can route from its own context.
  final VoidCallback? onTap;

  /// When non-empty, the case-insensitive substring is highlighted (lime) in the
  /// title (mockup 04). Original casing is preserved.
  final String? highlightQuery;

  /// When set, a neutral §8.17 content-type chip is shown under the title.
  final ContentType? contentType;

  /// When set (search results), a neutral §8.17 source tag naming the tool's
  /// category, shown with the content-type glyph (mockup 04).
  final String? categorySourceLabel;

  /// When set (search results, description/keyword-only hits), the
  /// `matches '<term>' in content` note shown after the source tag (mockup 04).
  final String? matchNote;

  @override
  State<ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<ToolRow> {
  // §8.9 — keyboard focus must stay visible. The global §8.3 pass cleared the
  // ambient focus tint, so we track focus locally and paint the 2px lime ring,
  // matching the button/chip treatment. Only live rows are focusable.
  bool _focused = false;

  bool get _live => widget.tool.isLive;

  void _handleTap() {
    if (!_live) return;
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      Navigator.of(context).pushNamed(widget.tool.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool live = _live;

    // §8.3 focus ring (live + focused) vs §8.1 interactive boundary.
    final Border rowBorder = (live && _focused)
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(
            color: live ? AppColors.borderStrong : AppColors.border,
            width: 1,
          );

    // §8.9 — collapse child semantic nodes; VoiceOver hears one curated label.
    final String semanticLabel = _buildSemanticLabel();

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      button: true,
      enabled: live,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: live ? _handleTap : null,
          onFocusChange: live
              ? (bool hasFocus) {
                  if (hasFocus != _focused) {
                    setState(() => _focused = hasFocus);
                  }
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _LeadingIcon(tool: widget.tool, live: live),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _content(text, live)),
                if (live)
                  const Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.xs,
                      top: 2,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(TextTheme text, bool live) {
    final List<Widget> children = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: _title(text, live)),
          if (!live)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                'Coming soon',
                style: text.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    ];

    // Search-results meta line: source tag (+ "matches in content" note).
    if (widget.categorySourceLabel != null) {
      children
        ..add(const SizedBox(height: AppSpacing.xs))
        ..add(_sourceLine(text));
    } else {
      // Default category-screen row: description, plus an optional type chip.
      children
        ..add(const SizedBox(height: 2))
        ..add(
          Text(
            widget.tool.description,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        );
      if (widget.contentType != null) {
        children
          ..add(const SizedBox(height: AppSpacing.xs))
          ..add(
            ContentTypeChip(
              label: widget.contentType!.label,
              icon: widget.contentType!.glyph,
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// The source tag + optional match note for a search row (mockup 04). The
  /// source tag is a neutral §8.17 chip; the note is quiet tertiary text.
  Widget _sourceLine(TextTheme text) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        ContentTypeChip(
          label: widget.categorySourceLabel!,
          icon: widget.contentType?.glyph,
        ),
        if (widget.matchNote != null)
          Text(
            widget.matchNote!,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
      ],
    );
  }

  /// Title, with the lime match highlight applied when [highlightQuery] is set.
  Widget _title(TextTheme text, bool live) {
    final TextStyle base =
        text.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: live ? AppColors.textPrimary : AppColors.textSecondary,
        ) ??
        const TextStyle();

    final String? q = widget.highlightQuery;
    if (q == null || q.trim().isEmpty) {
      return Text(widget.tool.title, style: base);
    }

    return Text.rich(_highlightSpan(widget.tool.title, q.trim(), base));
  }

  /// Builds a TextSpan that highlights every case-insensitive occurrence of
  /// [query] in [source] with lime (§8.3 active/match accent), preserving the
  /// source's original casing.
  TextSpan _highlightSpan(String source, String query, TextStyle base) {
    final String lowerSource = source.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    final TextStyle hit = base.copyWith(
      color: AppColors.secondary, // charcoal text on the lime highlight (§8.3)
      backgroundColor: AppColors.primary,
    );

    final List<TextSpan> spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final int idx = lowerSource.indexOf(lowerQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: source.substring(start), style: base));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: source.substring(start, idx), style: base));
      }
      spans.add(
        TextSpan(
          text: source.substring(idx, idx + query.length),
          style: hit,
        ),
      );
      start = idx + query.length;
    }
    return TextSpan(children: spans);
  }

  String _buildSemanticLabel() {
    final ToolEntry t = widget.tool;
    final StringBuffer b = StringBuffer(t.title);
    b.write('. ');
    if (!_live) b.write('Coming soon. ');
    if (widget.categorySourceLabel != null) {
      b.write('In ${widget.categorySourceLabel}. ');
      if (widget.matchNote != null) b.write('${widget.matchNote}. ');
    } else {
      b.write(t.description);
      if (widget.contentType != null) {
        b.write('. ${widget.contentType!.label}.');
      }
    }
    return b.toString();
  }
}

/// The leading 40×40 surface-2 tile holding the tool's Tier-2 SVG icon (lime,
/// §8.6.1), the lock for non-live rows, or the Icons.bolt fallback when no SVG
/// is bundled for this id.
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.tool, required this.live});

  final ToolEntry tool;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: !live
          ? const Icon(
              Icons.lock_clock_outlined,
              color: AppColors.textTertiary,
              size: 20,
            )
          : ToolAssets.hasIcon(tool.id)
          ? SvgPicture.asset(
              ToolAssets.iconPath(tool.id),
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.primary,
                BlendMode.srcIn,
              ),
              excludeFromSemantics: true,
              placeholderBuilder: (_) => const SizedBox.shrink(),
            )
          : const Icon(Icons.bolt, color: AppColors.primary, size: 20),
    );
  }
}
