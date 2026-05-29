// ValueRow — a label/value line shared across the network tool screens.
//
// Renders a left-aligned caption label and a right-aligned value. A null or
// empty value shows the canonical "Not available on this platform" treatment
// (brief §10) in tertiary text — never a 0, never a blank that reads as a bug.
// Addresses and numeric values render in DM Mono (GL-003 §8.5) when `mono` is
// set, so columns of IPs align cleanly.

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasize = false,
  });

  final String label;

  /// Null or empty renders the unavailable treatment.
  final String? value;

  /// Render the value in DM Mono (for IPs, MACs, masks).
  final bool mono;

  /// Lime + larger weight for the headline value (e.g. Primary IPv4).
  final bool emphasize;

  bool get _available => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText monoStyle =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final TextStyle valueStyle = _available
        ? (mono
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
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
