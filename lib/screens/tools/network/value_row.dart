// ValueRow — a label/value line shared across the network tool screens.
//
// Renders a left-aligned caption label and a right-aligned value. A null or
// empty value shows the canonical "Not available on this platform" treatment
// (brief §10) in tertiary text — never a 0, never a blank that reads as a bug.
//
// Two distinct fixed-width registers, per GL-003 §8.5:
//   - `mono`       → DM Mono (`inlineCode`) — computed numerics (counts, coords,
//                    measured durations) so decimal columns align.
//   - `identifier` → Roboto Mono (`robotoMono`) — address/identifier strings
//                    (IP, MAC, BSSID, subnet/wildcard/gateway, CIDR, ASN, hex
//                    serials/fingerprints) per the identifier rule. Scanned
//                    glyph-by-glyph, so they take the cleaner identifier face.
// Set at most one of the two; `identifier` wins if both are passed.

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.identifier = false,
    this.emphasize = false,
  });

  /// Fixed width of the left-hand label column, shared by every label/value
  /// row on the network tool screens (`ValueRow` and the bespoke rows that
  /// must align under it — the Public IP and MAC-type rows in
  /// `interface_info_screen.dart`). Named here so the column alignment cannot
  /// fork across those rows. Not a §4 spacing token — it is a layout column
  /// width specific to these data rows.
  static const double labelColumnWidth = 112;

  final String label;

  /// Null or empty renders the unavailable treatment.
  final String? value;

  /// Render the value in DM Mono — computed numerics (counts, coordinates,
  /// measured durations). For address/identifier strings use [identifier].
  final bool mono;

  /// Render the value in Roboto Mono — address/identifier strings (IP, MAC,
  /// BSSID, subnet/wildcard/gateway, CIDR, ASN, hex serial/fingerprint) per
  /// GL-003 §8.5. Takes precedence over [mono] if both are set.
  final bool identifier;

  /// Lime + larger weight for the headline value (e.g. Primary IPv4).
  final bool emphasize;

  bool get _available => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText monoStyle =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final TextStyle valueStyle = _available
        ? (identifier
              ? monoStyle.robotoMono.copyWith(
                  color: emphasize ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
                )
              : mono
              ? monoStyle.inlineCode.copyWith(
                  color: emphasize ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
                )
              : (text.bodyLarge ?? const TextStyle()).copyWith(
                  color: emphasize ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
                ))
        : (text.bodyLarge ?? const TextStyle()).copyWith(
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelColumnWidth,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              _available ? value! : 'Not available on this platform',
              style: valueStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
