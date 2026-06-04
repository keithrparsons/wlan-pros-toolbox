// Educational resource detail — the per-resource reading screen.
//
// Shows the title, topic, cost + level badges, the 1-2 paragraph offline
// reading copy (`description`), the tags, and an "Open website" button that
// opens `url` in the system browser (url_launcher, externalApplication mode).
// On the destination resources (the wlan-talks set) it also renders the
// "Inspired by wlan-talks.net by Victor Njoroge" credit, scoped per
// `_meta.attribution_scope`; the canonical tools / vendor-doc resources do not
// show it.
//
// The AppBar carries the shared AppCopyAction (§8.16): tapping copies a plain-
// text summary of the resource (title, topic, cost/level WORDS, url, tags,
// description) to the clipboard — color-independent, every metadata word
// present, matching the app-wide copy affordance on the results screens.
//
// HTTPS opens fine on iOS + macOS via the system browser; no ATS exception and
// no macOS entitlement is needed for an http/https LaunchMode.externalApplication
// launch (GL-008: this is a browser hand-off, not an in-app cleartext fetch).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/educational/educational_resources_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import 'resource_badges.dart';

/// The wlan-talks destinations credit, displayed only on destination resources.
const String _kDestinationAttribution =
    'Inspired by wlan-talks.net by Victor Njoroge.';

class EducationalResourceDetailScreen extends StatefulWidget {
  const EducationalResourceDetailScreen({
    super.key,
    required this.resource,
    this.launcher,
  });

  final EducationalResource resource;

  /// Injectable URL opener for tests. Defaults to [launchUrl]. Returns whether
  /// the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<EducationalResourceDetailScreen> createState() =>
      _EducationalResourceDetailScreenState();
}

class _EducationalResourceDetailScreenState
    extends State<EducationalResourceDetailScreen> {
  String? _launchError;

  bool get _isDestination => EducationalResourcesService.destinationTopics
      .contains(widget.resource.topic);

  /// Plain-text payload for AppCopyAction. Carries every metadata WORD (cost,
  /// level) so nothing that was on-screen survives only as a value
  /// (§8.16 content contract — clipboard has no color).
  String _copyText() {
    final EducationalResource r = widget.resource;
    final StringBuffer b = StringBuffer()
      ..writeln(r.title)
      ..writeln('Topic: ${r.topic}')
      ..writeln('Cost: ${r.cost.label}')
      ..writeln('Level: ${r.level.label}')
      ..writeln('Website: ${r.url}');
    if (r.tags.isNotEmpty) {
      b.writeln('Tags: ${r.tags.join(', ')}');
    }
    b
      ..writeln()
      ..writeln(r.description);
    if (_isDestination) {
      b
        ..writeln()
        ..writeln(_kDestinationAttribution);
    }
    return b.toString().trimRight();
  }

  Future<void> _openWebsite() async {
    final Uri? uri = Uri.tryParse(widget.resource.url);
    if (uri == null) {
      _showLaunchError();
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError();
        return;
      }
      if (!mounted) return;
      setState(() => _launchError = null);
    } on Object {
      _showLaunchError();
    }
  }

  void _showLaunchError() {
    if (!mounted) return;
    setState(
      () => _launchError =
          'Could not open the browser. The link is ${widget.resource.url}',
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final EducationalResource r = widget.resource;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.title),
        toolbarHeight: 64,
        // §8.16: copy leads the actions slot. Always enabled — a resource detail
        // always has content to copy.
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return CenteredContent(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                children: <Widget>[
                  _TopicLine(topic: r.topic),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    r.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ResourceMetaBadges(cost: r.cost, level: r.level),
                  const SizedBox(height: AppSpacing.md),
                  _DescriptionCard(description: r.description),
                  if (r.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _TagsSection(tags: r.tags),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _OpenWebsiteButton(
                    title: r.title,
                    onPressed: _openWebsite,
                  ),
                  if (_launchError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _LaunchError(message: _launchError!),
                  ],
                  if (_isDestination) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    const _Attribution(text: _kDestinationAttribution),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The topic eyebrow line above the title.
class _TopicLine extends StatelessWidget {
  const _TopicLine({required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        const Icon(
          Icons.folder_outlined,
          size: 16,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            topic,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The offline reading copy. Splits double-newline paragraphs for readable
/// spacing, since some descriptions carry two paragraphs.
class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> paragraphs = description
        .split('\n\n')
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < paragraphs.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Text(
              paragraphs[i],
              style: text.bodyLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tags section: a "Tags" heading + a Wrap of neutral tag chips.
class _TagsSection extends StatelessWidget {
  const _TagsSection({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Tags',
          style: text.labelLarge?.copyWith(
            fontSize: AppTextSize.caption,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final String tag in tags) ResourceTagChip(label: tag),
          ],
        ),
      ],
    );
  }
}

/// The primary "Open website" CTA. Primary button (§8.3): lime fill, charcoal
/// text, 48dp height, focus ring inherited from the theme. Explicit SR label
/// names the resource and that it opens in the browser.
class _OpenWebsiteButton extends StatelessWidget {
  const _OpenWebsiteButton({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open $title website in browser',
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: AppSpacing.minTouchTarget,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.open_in_new, size: 20),
          label: const Text('Open website'),
        ),
      ),
    );
  }
}

/// Honest error shown when the browser hand-off fails (link still readable).
class _LaunchError extends StatelessWidget {
  const _LaunchError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.statusDanger, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 20,
            color: AppColors.statusDanger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: text.labelMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The destinations credit line shown at the foot of a destination resource.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 2, right: AppSpacing.xs),
          child: Icon(
            Icons.favorite_outline,
            size: 14,
            color: AppColors.textTertiary,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}
