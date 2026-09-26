// PresenterDisclosure: the "rarely used settings" fold for a presenter
// controls panel (spec §3: group rarely used settings behind a disclosure so
// the panel fits without scrolling).
//
// Built on TextButton rather than ExpansionTile, because ExpansionTile's
// ListTile needs a Material directly above it and asserts inside the tools'
// colored cards. Starts closed. Keyboard: Tab to it, Enter toggles; the
// header reports expanded or collapsed to screen readers.

import 'package:flutter/material.dart';

import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';

class PresenterDisclosure extends StatefulWidget {
  const PresenterDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.initiallyOpen = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyOpen;

  @override
  State<PresenterDisclosure> createState() => _PresenterDisclosureState();
}

class _PresenterDisclosureState extends State<PresenterDisclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          expanded: _open,
          child: TextButton(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(
              foregroundColor: colors.textAccent,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: colors.textAccent,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
