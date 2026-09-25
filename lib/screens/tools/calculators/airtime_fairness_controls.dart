// Airtime Fairness (Wi-Fi Lab) — the CONTROLS: everything the student sets,
// plus the readouts that answer it (the takeaway line, the per-turn line on
// each client).
//
// Two cards, each a public widget, and [AirtimeFairnessControls] composing
// both. The phone layout places the rule card above the stage and the clients
// card below it; a presenter layout can use [AirtimeFairnessControls] whole
// beside the stage. The screen owns every piece of state; these widgets only
// report edits through callbacks.
//
// THEME: context.colors only. Status danger only on an invalid custom rate
// (GL-003 §8.13). Selects for 4+ options (§8.14), toggles for 2 to 3 (§8.14.1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'airtime_fairness_common.dart';

const List<int> kAirtimeAggregationChoices = <int>[1, 2, 4, 8, 16, 32, 64];
const List<int> kAirtimePayloadChoices = <int>[64, 256, 576, 1000, 1500];

/// Both control cards, stacked. For layouts that keep the controls together.
class AirtimeFairnessControls extends StatelessWidget {
  const AirtimeFairnessControls({
    super.key,
    required this.rule,
    required this.clients,
  });

  final AirtimeFairnessRuleCard rule;
  final AirtimeFairnessClientsCard clients;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      rule,
      const SizedBox(height: AppSpacing.md),
      clients,
    ],
  );
}

// ── Rule card: sharing rule, takeaway, replay ────────────────────────────────

class AirtimeFairnessRuleCard extends StatelessWidget {
  const AirtimeFairnessRuleCard({
    super.key,
    required this.view,
    required this.onViewChanged,
    required this.takeaway,
    required this.onReplay,
    required this.reducedMotion,
  });

  final FairnessView view;
  final ValueChanged<FairnessView> onViewChanged;

  /// The live result sentence; null while an input is invalid.
  final String? takeaway;

  /// Replays the round animation; null disables the button.
  final VoidCallback? onReplay;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? line = takeaway;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Plain 802.11 contention gives every client about the same number '
            'of turns, not the same amount of time. A slow client holds the '
            'air longer each turn. Airtime fairness gives each client an equal '
            'share of time instead.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<FairnessView>(
            label: 'Sharing rule',
            value: view,
            expand: true,
            items: <AppToggleItem<FairnessView>>[
              for (final FairnessView v in FairnessView.values) (v, v.label),
            ],
            onChanged: onViewChanged,
          ),
          if (line != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                line,
                style: text.bodyLarge?.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (reducedMotion)
            Text(
              'Reduced motion is on, so the round is drawn complete.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            )
          else
            LabOutlineButton(
              icon: Icons.replay_rounded,
              label: 'Replay round',
              semanticLabel: 'Replay the round animation',
              onPressed: onReplay,
            ),
        ],
      ),
    );
  }
}

// ── Clients card ─────────────────────────────────────────────────────────────

class AirtimeFairnessClientsCard extends StatelessWidget {
  const AirtimeFairnessClientsCard({
    super.key,
    required this.clients,
    required this.payloadBytes,
    required this.onPayloadChanged,
    required this.onEdit,
    required this.onAdd,
    required this.onRemove,
  });

  /// The screen's drafts, in position order (letter A first).
  final List<AirtimeClientDraft> clients;
  final int payloadBytes;
  final ValueChanged<int> onPayloadChanged;

  /// Apply [change] to a draft and rebuild. Every draft edit goes through
  /// here so the screen stays the single owner of state.
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onAdd;

  /// Remove the draft with this id.
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final int n = clients.length;
    final bool full = n >= AirtimeConstants.maxClients;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabSectionTitle('Clients ($n of ${AirtimeConstants.maxClients})'),
          const SizedBox(height: AppSpacing.sm),
          _labeledSelect<int>(
            label: 'Payload per frame',
            value: payloadBytes,
            items: <AppSelectItem<int>>[
              for (final int b in kAirtimePayloadChoices) (b, '$b bytes'),
            ],
            onChanged: onPayloadChanged,
          ),
          for (int i = 0; i < n; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ClientRow(
              key: ValueKey<int>(clients[i].id),
              draft: clients[i],
              index: i,
              canRemove: n > AirtimeConstants.minClients,
              payloadBytes: payloadBytes,
              onEdit: onEdit,
              onRemove: () => onRemove(clients[i].id),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          LabOutlineButton(
            icon: Icons.add_rounded,
            label: 'Add client',
            semanticLabel: full
                ? 'Add client, unavailable: 8 is the maximum'
                : 'Add client ${clientLetter(n)}',
            onPressed: full ? null : onAdd,
          ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    super.key,
    required this.draft,
    required this.index,
    required this.canRemove,
    required this.payloadBytes,
    required this.onEdit,
    required this.onRemove,
  });

  final AirtimeClientDraft draft;
  final int index;
  final bool canRemove;
  final int payloadBytes;
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AirtimeClientDraft c = draft;
    final String letter = clientLetter(index);
    final ClientConfig? cfg = c.toConfig();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Client $letter',
                    style: text.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                tooltip: canRemove
                    ? 'Remove client $letter'
                    : 'At least one client is required',
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: colors.textSecondary,
                disabledColor: colors.textDisabled,
              ),
            ],
          ),
          _labeledSelect<RatePreset?>(
            label: 'PHY rate',
            semanticLabel: 'Client $letter PHY rate',
            value: c.preset,
            items: <AppSelectItem<RatePreset?>>[
              for (final RatePreset p in RatePreset.values) (p, p.label),
              (null, 'Custom rate'),
            ],
            onChanged: (RatePreset? p) => onEdit(() {
              if (p == null) {
                // Seed the custom field from the preset being left.
                final RatePreset? was = c.preset;
                if (was != null) {
                  c.controller.text = was.mbps.round().toString();
                  c.customLegacy = was.family.isLegacy;
                }
              }
              c.preset = p;
            }),
          ),
          if (c.preset == null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _customRate(context, letter),
          ],
          const SizedBox(height: AppSpacing.sm),
          _labeledSelect<int>(
            label: 'Frames per turn (aggregation)',
            semanticLabel: c.legacy
                ? 'Client $letter aggregation, unavailable: legacy clients '
                      'send one frame per turn'
                : 'Client $letter frames per turn',
            value: c.legacy ? 1 : c.aggregation,
            enabled: !c.legacy,
            items: <AppSelectItem<int>>[
              for (final int a in kAirtimeAggregationChoices)
                (a, a == 1 ? '1 (no aggregation)' : '$a frames'),
            ],
            onChanged: (int a) => onEdit(() => c.aggregation = a),
          ),
          if (cfg != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _perTurnLine(context, cfg),
          ],
        ],
      ),
    );
  }

  Widget _customRate(BuildContext context, String letter) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          label: 'Custom rate',
          semanticLabel: 'Client $letter custom PHY rate in Mbps',
          field: TextField(
            key: ValueKey<String>('custom-rate-${draft.id}'),
            controller: draft.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            onChanged: (_) => onEdit(() {}),
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            style: mono.outputLarge.copyWith(
              fontSize: AppTextSize.fieldNumeric,
            ),
            cursorColor: colors.textAccent,
            decoration: InputDecoration(
              hintText: 'e.g. 1201',
              suffixText: 'Mbps',
              errorText: draft.rateError,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppToggle<bool>(
          label: 'Preamble',
          semanticLabel: 'Client $letter preamble',
          value: draft.customLegacy,
          expand: true,
          items: const <AppToggleItem<bool>>[
            (true, 'Legacy'),
            (false, 'HT or newer'),
          ],
          onChanged: (bool v) => onEdit(() => draft.customLegacy = v),
        ),
      ],
    );
  }

  /// Lesson 1 on every row: how much of a turn is overhead, and what the
  /// client would get alone.
  Widget _perTurnLine(BuildContext context, ClientConfig cfg) {
    final AppColorScheme colors = context.colors;
    final double t = airtimeUs(cfg, payloadBytes: payloadBytes);
    final double oh = overheadUs(cfg);
    final double solo = payloadBits(cfg, payloadBytes: payloadBytes) / t;
    return Text(
      'Each turn: ${fmtUs(t)}, ${fmtPct(oh / t)} of it overhead. '
      'Alone on the air: ${fmtMbps(solo)} Mbps, '
      '${fmtPct(solo / cfg.rateMbps)} of its PHY rate.',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }
}

// ── Shared control pieces ────────────────────────────────────────────────────

/// A §8.14 Select under its §8.4 label line.
Widget _labeledSelect<T>({
  required String label,
  String? semanticLabel,
  required T value,
  required List<AppSelectItem<T>> items,
  required ValueChanged<T> onChanged,
  bool enabled = true,
}) {
  return LabeledField(
    label: label,
    field: AppSelect<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      enabled: enabled,
      semanticLabel: semanticLabel ?? label,
    ),
  );
}

/// Full-width outlined button, matching the Wi-Fi Lab siblings.
class LabOutlineButton extends StatelessWidget {
  const LabOutlineButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      enabled: enabled,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          // Disabled keeps a visible boundary (GL-003 §8.3, §8.14 states).
          side: BorderSide(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
