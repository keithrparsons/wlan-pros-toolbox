// The stage of the Connected, No Internet walk-through: the device, the
// network and the internet, the exchange at the current step, and what the
// person holding the device sees. Controls live in captive_portal_controls.dart
// so this widget only draws.
//
// States (SOP-007 §5): every step of both modes renders here; there is no
// loading, empty or error state because the model is compiled in. The held
// and open internet states carry a word and an icon, never color alone (GL-003
// §8.13); the intercepted reply carries the word Intercepted.
//
// THEME: `context.colors` only.
//
// ACCESSIBILITY: the step heading is a live region, so a screen reader hears
// the new step when Step or Back is pressed. Decorative icons are excluded;
// every fact they show is in the text beside them.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/captive_portal_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

class CaptivePortalStage extends StatelessWidget {
  const CaptivePortalStage({
    super.key,
    required this.step,
    required this.index,
    required this.count,
  });

  final CaptiveStep step;

  /// Zero-based position of [step].
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool open = step.internet == InternetAccess.open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            'Step ${index + 1} of $count: ${step.title}',
            style: (t.titleSmall ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Path(open: open),
        const SizedBox(height: AppSpacing.sm),
        _Exchange(step: step),
        const SizedBox(height: AppSpacing.sm),
        _Status(
          icon: Icons.smartphone_outlined,
          label: 'On screen',
          value: step.onScreen,
        ),
        _Status(
          icon: open ? Icons.lock_open_outlined : Icons.lock_outline,
          label: 'Internet',
          value: open ? 'Open' : 'Held by the network until sign-in',
          tone: open ? colors.statusSuccess : colors.statusWarning,
        ),
        _Status(
          icon: Icons.call_outlined,
          label: 'Wi-Fi Calling',
          value: step.wifiCallingCanConnect
              ? 'Can connect'
              : 'Waits for the sign-in',
          tone: step.wifiCallingCanConnect
              ? colors.statusSuccess
              : colors.statusWarning,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          step.explanation,
          style: (t.bodyMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Device, network, internet in a row (a column on a narrow screen), with
/// the Wi-Fi link always up and the gate to the internet held or open.
class _Path extends StatelessWidget {
  const _Path({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final List<Widget> parts = <Widget>[
      const _Node(icon: Icons.smartphone_outlined, label: 'This device'),
      _Link(icon: Icons.wifi, label: 'Wi-Fi link up', color: colors.textAccent),
      const _Node(icon: Icons.router_outlined, label: 'The network'),
      _Link(
        icon: open ? Icons.lock_open_outlined : Icons.lock_outline,
        label: open ? 'Open' : 'Held',
        color: open ? colors.statusSuccess : colors.statusWarning,
      ),
      const _Node(icon: Icons.public, label: 'The internet'),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (c.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: parts,
          );
        }
        return Row(
          children: <Widget>[
            for (final Widget p in parts)
              p is _Node
                  ? Expanded(flex: 3, child: p)
                  : Expanded(flex: 2, child: p),
          ],
        );
      },
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(icon, size: 20, color: colors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ExcludeSemantics(child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two messages of the current step: what the device sends, what comes
/// back. An intercepted reply is tagged in words; so is the announcement.
class _Exchange extends StatelessWidget {
  const _Exchange({required this.step});

  final CaptiveStep step;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Message(
            icon: Icons.arrow_forward,
            label: 'Device sends',
            text: step.sent,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Message(
            icon: Icons.arrow_back,
            label: 'Network replies',
            text: step.reply,
            tag: step.replyIsInterception
                ? 'Intercepted'
                : (step.announcesPortal ? 'Portal announced' : null),
            tagColor: step.replyIsInterception
                ? colors.statusWarning
                : colors.textAccent,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.label,
    required this.text,
    this.tag,
    this.tagColor,
  });

  final IconData icon;
  final String label;
  final String text;
  final String? tag;
  final Color? tagColor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs / 2),
              child: Icon(icon, size: 18, color: colors.textAccent),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      label,
                      style: t.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs / 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: tagColor ?? colors.border),
                        ),
                        child: Text(
                          tag!,
                          style: t.labelSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs / 2),
                Text(
                  text,
                  style: t.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(icon, size: 18, color: tone ?? colors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '$label: ',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    TextSpan(
                      text: value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: t.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
