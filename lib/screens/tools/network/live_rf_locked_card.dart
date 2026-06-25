// LiveRfLockedCard — the "available once you enable live Wi-Fi" card.
//
// WHY THIS EXISTS: Pax's #1 anti-pattern (2026-06-07 onboarding research) is a
// live-Wi-Fi tool that opens to ZEROED or BLANK RF fields. To an IT pro who
// knows the data exists, zeroed signal/channel/PHY/rate reads as a BROKEN app,
// not as "iOS needs a bridge". This card replaces that dead state: before the
// companion Shortcut has ever delivered a payload, the rich RF fields (Signal /
// Channel / Rate / Wi-Fi Standard) are listed by NAME with an explicit
// "available once live Wi-Fi is on" affordance — never a fake 0 dBm / channel 0.
//
// It pairs with the native-first identity card: the app shows the REAL connected
// network basics (SSID / BSSID / security, read natively via NEHotspotNetwork)
// immediately, and this card honestly frames the RF metrics that genuinely need
// the Shortcut as a feature you TURN ON.
//
// HONESTY (GL-005): no values are shown here — only the field NAMES and the
// honest reason they are not yet readable. We never imply data we cannot read.
//
// Styling is GL-003 App Mode: surface1 card, hairline border, lime-primary
// FilledButton for the one prominent "enable" action, textSecondary copy,
// textTertiary lock glyphs. iOS-only — macOS reads CoreWLAN natively and never
// renders this.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'get_reading_icon.dart';

/// A non-zeroed placeholder for the live RF fields, shown before the companion
/// Shortcut has delivered any reading. Lists the RF metrics by name and offers
/// the one-time "enable live Wi-Fi" action.
class LiveRfLockedCard extends StatelessWidget {
  const LiveRfLockedCard({
    super.key,
    required this.onEnable,
    this.enableLabel = 'Enable live Wi-Fi',
  });

  /// Opens the one-time companion-Shortcut setup sheet.
  final VoidCallback onEnable;

  /// The action-button label. Caller-owned so each tool can name its own thing.
  final String enableLabel;

  /// The rich RF fields that genuinely require the companion Shortcut on iOS.
  /// Listed by NAME (never as zeroed values) so the user sees exactly what
  /// turning on live Wi-Fi unlocks.
  static const List<String> _rfFields = <String>[
    'Signal (RSSI) and SNR',
    'Channel, width, and band',
    'Tx / Rx rate',
    'Wi-Fi standard (PHY)',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Live signal details',
            style: text.titleSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Available once you enable live Wi-Fi. iOS reads these through the '
            'one-time companion Shortcut, no Location permission needed.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The RF fields by name, each behind a lock glyph. NOT zeroed values.
          ..._rfFields.map((String field) => _LockedFieldRow(label: field)),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: enableLabel,
            child: FilledButton.icon(
              onPressed: onEnable,
              icon: const GetReadingIcon(),
              label: Text(enableLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// One locked RF-field row: a lock glyph + the field name. Carries an explicit
/// "not yet available" semantic so a screen reader never reads it as a value.
class _LockedFieldRow extends StatelessWidget {
  const _LockedFieldRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: '$label, available once live Wi-Fi is enabled',
        excludeSemantics: true,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.lock_outline,
              size: 18,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
