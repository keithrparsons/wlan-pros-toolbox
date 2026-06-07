// The one-time "set up live readings" prompt for the iOS live tools.
//
// Why this exists: on iOS the live tools (Wi-Fi Information, Cellular
// Information, Test My Connection) cannot read RF data until the user installs
// the combined "WLAN Pros Live" companion Shortcut, and iOS cannot auto-install
// it. Beta testers who had not added the Shortcut saw the live tools sit empty
// and assumed they were broken. This card replaces that silent/dead state with a
// clear explanation AND a prominent "Set up live readings (one-time)" button
// that opens the install sheet, so a new user is never left wondering why a tool
// is not working.
//
// When it shows: ONLY when the app has never received a live payload
// (hasEverReceived == false, the honest install-state signal — iOS cannot query
// installed Shortcuts). Once any payload has arrived the user demonstrably has
// the Shortcut working, so the prompt is gone permanently and never nags. This
// widget is built only on the iOS source path; macOS reads CoreWLAN natively and
// never renders it.
//
// Styling is GL-003 App Mode: surface1 card with a hairline border, lime-primary
// FilledButton for the one prominent action, textSecondary explanatory copy,
// textTertiary icon. Two variants: [LiveSetupCard.prompt] (the default,
// pre-error neutral nudge) and [LiveSetupCard.error] (after a failed Start —
// statusDanger icon + a "could not start" lead-in, but the SAME setup button).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// A one-time, dismiss-on-success setup prompt for the iOS live tools.
class LiveSetupCard extends StatelessWidget {
  const LiveSetupCard({
    super.key,
    required this.label,
    required this.onSetUp,
    this.isError = false,
  }) : assert(label != '');

  /// Builds the neutral first-run prompt (no error yet).
  const LiveSetupCard.prompt({
    Key? key,
    required String label,
    required VoidCallback onSetUp,
  }) : this(key: key, label: label, onSetUp: onSetUp, isError: false);

  /// Builds the post-failure variant: the live Start could not open the
  /// Shortcut, so the card leads with the honest failure and offers the same
  /// one-time setup action.
  const LiveSetupCard.error({
    Key? key,
    required String label,
    required VoidCallback onSetUp,
  }) : this(key: key, label: label, onSetUp: onSetUp, isError: true);

  /// The action-button label, e.g. "Set up live Wi-Fi (one-time)". Caller-owned
  /// so each tool names its own thing.
  final String label;

  /// Opens the install sheet (the one-time companion-Shortcut onboarding).
  final VoidCallback onSetUp;

  /// When true, the card is the error variant (failed Start). When false, it is
  /// the neutral first-run prompt.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // The error variant leads with the honest "could not start" sentence (in a
    // liveRegion so a Start failure is announced). The neutral variant explains
    // the one-time step up front so a brand-new user understands the wall.
    final String body = isError
        ? 'Live readings could not start. iOS needs the "WLAN Pros Live" '
            'companion Shortcut, which may not be added yet. Set it up once, '
            'then tap Start again.'
        : 'iOS reads live data through a one-time companion Shortcut, "WLAN '
            'Pros Live". Add it once and every live tool works. Until then, '
            'this tool has nothing to read.';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                isError ? Icons.error_outline : Icons.bolt_outlined,
                size: 20,
                // Error variant carries the §8.13 danger verdict (paired with the
                // failure text, never color-only); the neutral variant uses a
                // muted tertiary glyph (decorative, not a verdict).
                color: isError ? colors.statusDanger : colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: isError,
                  child: Text(
                    body,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: label,
            child: FilledButton.icon(
              onPressed: onSetUp,
              icon: const Icon(Icons.download_outlined),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
