// EapLadderControls: the inputs-and-readouts half of the 802.1X and EAP
// Ladder.
//
// Takes the shared EapLadderController and a set of parts to show, so the
// phone layout can put playback and readouts right under the stage and the
// settings after them, while a presenter layout shows every part in one
// column beside the stage. No part draws the ladder; EapLadderStage owns it.
//
// Control types follow GL-003 §8.14: the method (five options) is a Select;
// roam mode, inner method and playback speed (two or three options) are
// AppToggles. Settings that change nothing for the chosen method or roam
// mode are disabled with a sentence saying why. The method's credential and
// certificate lines are read from the app's 802.1X / EAP Types reference
// (EapTypesScreen.methods), not restated, so the two tools cannot disagree.
//
// JOIN AND ROAM (spec 21b): in those modes the readouts and settings come
// from eap_ladder_jr_controls.dart; the transport is the same.
//
// PRESENTER (spec 00): inside a PresenterLayout the panel keeps playback, the
// method and the roam mode in view (the inner method only for EAP-TTLS); the
// counts are on the stage, and the certificate and RADIUS settings, the
// readouts and the method's credentials fold into PresenterDisclosures.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../services/wifi_lab/join_roam.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import '../reference/eap_types_screen.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_jr_controls.dart';
import 'eap_ladder_palette.dart';
import 'eap_ladder_parts.dart';
import 'security_compat_controls.dart';

/// The groups EapLadderControls can show.
enum LadderControlPart {
  /// Play, pause, back, step, reset, show all and speed.
  transport,

  /// Message counts, round trips, time and what was skipped.
  readouts,

  /// Method, inner method, roam mode, certificate size and RADIUS time.
  settings,
}

class EapLadderControls extends StatelessWidget {
  const EapLadderControls({
    super.key,
    required this.controller,
    this.parts = const <LadderControlPart>{
      LadderControlPart.transport,
      LadderControlPart.readouts,
      LadderControlPart.settings,
    },
  });

  final EapLadderController controller;
  final Set<LadderControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final EapLadderController c = controller;
        if (PresenterMode.isActive(context)) {
          return c.isJr ? _JrPresenterPanel(c) : _PresenterPanel(c);
        }
        final List<Widget> cards = c.whyMode
            // Why won't it associate? (spec 43): the client and the network
            // first, then what the scan and timing still decide.
            ? <Widget>[
                if (parts.contains(LadderControlPart.transport))
                  _TransportCard(c),
                if (parts.contains(LadderControlPart.settings)) ...<Widget>[
                  ScClientCard(controller: c),
                  ScNetworkCard(controller: c),
                ],
                if (parts.contains(LadderControlPart.readouts))
                  JrReadoutsCard(controller: c),
                if (parts.contains(LadderControlPart.settings))
                  JrSettingsCard(
                    controller: c,
                    groups: const <JrSettingsGroup>{
                      JrSettingsGroup.eap,
                      JrSettingsGroup.scan,
                      JrSettingsGroup.sixGhz,
                      JrSettingsGroup.addressCheck,
                    },
                  ),
              ]
            : c.isJr
            ? <Widget>[
                if (parts.contains(LadderControlPart.transport))
                  _TransportCard(c),
                if (parts.contains(LadderControlPart.readouts))
                  JrReadoutsCard(controller: c),
                if (parts.contains(LadderControlPart.settings))
                  JrSettingsCard(controller: c),
              ]
            : <Widget>[
                if (parts.contains(LadderControlPart.transport))
                  _TransportCard(c),
                if (parts.contains(LadderControlPart.readouts))
                  _ReadoutsCard(c),
                if (parts.contains(LadderControlPart.settings))
                  _SettingsCard(c),
              ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

// ── Presenter panel ─────────────────────────────────────────────────────────

class _PresenterPanel extends StatelessWidget {
  const _PresenterPanel(this.c);

  final EapLadderController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final LadderConfig cfg = c.config;
    final EapMethod? ref = _SettingsCard._reference(cfg.method);
    final bool ttls = cfg.method == LadderMethod.eapTtls;
    final bool fragments = cfg.certificateMatters;
    final bool radius = cfg.radiusMatters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (c.mode != LadderMode.join) ...<Widget>[
          ElCard(child: LadderModeToggle(controller: c)),
          const SizedBox(height: AppSpacing.xs),
        ],
        _PresenterTransport(c),
        const SizedBox(height: AppSpacing.xs),
        ElCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabeledField(
                label: 'Method',
                semanticLabel: 'Authentication method',
                field: AppSelect<LadderMethod>(
                  value: cfg.method,
                  semanticLabel: 'Authentication method',
                  items: <AppSelectItem<LadderMethod>>[
                    for (final LadderMethod m in LadderMethod.values)
                      (m, m.label),
                  ],
                  onChanged: (LadderMethod m) => c.method = m,
                ),
              ),
              if (ttls) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                AppToggle<LadderInner>(
                  label: 'Inner method',
                  semanticLabel: 'Inner method inside the EAP-TTLS tunnel',
                  value: cfg.inner,
                  expand: true,
                  items: <AppToggleItem<LadderInner>>[
                    for (final LadderInner i in LadderInner.values)
                      (i, i.label),
                  ],
                  onChanged: (LadderInner i) => c.inner = i,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              AppToggle<LadderRoam>(
                label: 'Roam mode',
                semanticLabel: 'Roam mode',
                value: cfg.roam,
                expand: true,
                items: <AppToggleItem<LadderRoam>>[
                  for (final LadderRoam r in LadderRoam.values)
                    (r, r.shortLabel),
                ],
                onChanged: (LadderRoam r) => c.roam = r,
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Certificate size and RADIUS time',
          children: <Widget>[
            ElSlider(
              label: 'Certificate fragments per message',
              valueText:
                  '${cfg.certFragments} fragment'
                  '${cfg.certFragments == 1 ? '' : 's'}',
              value: cfg.certFragments.toDouble(),
              min: kMinCertFragments.toDouble(),
              max: kMaxCertFragments.toDouble(),
              divisions: kMaxCertFragments - kMinCertFragments,
              onChanged: fragments ? (double v) => c.certFragments = v : null,
              semanticValue: (double v) =>
                  '${v.round()} fragment${v.round() == 1 ? '' : 's'} per '
                  'certificate message',
            ),
            ElSlider(
              label: 'RADIUS round-trip time (illustrative)',
              valueText: '${cfg.radiusRttMs.round()} ms',
              value: cfg.radiusRttMs,
              min: kMinRadiusRttMs,
              max: kMaxRadiusRttMs,
              divisions: (kMaxRadiusRttMs - kMinRadiusRttMs).round(),
              onChanged: radius ? (double v) => c.radiusRttMs = v : null,
              semanticValue: (double v) => '${v.round()} milliseconds',
            ),
            if (!fragments || !radius)
              Text(
                'No certificate or RADIUS messages in this '
                '${cfg.method.uses8021X ? 'roam mode' : 'method'}.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
        PresenterDisclosure(
          title: 'Readouts, and what a roam skips',
          children: <Widget>[_ReadoutsCard(c)],
        ),
        if (ref != null)
          PresenterDisclosure(
            title: 'Credentials for ${cfg.method.label}',
            children: <Widget>[
              ElRow(label: 'Credential', value: ref.credential),
              ElRow(label: 'Server cert', value: ref.serverCert),
              ElRow(label: 'Client cert', value: ref.clientCert),
            ],
          ),
      ],
    );
  }
}

/// Play, Back, Step, Reset, Show all and speed, for the presenter panel.
class _PresenterTransport extends StatelessWidget {
  const _PresenterTransport(this.c);

  final EapLadderController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: c.togglePlay,
                  icon: Icon(
                    c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    c.playing
                        ? 'Pause'
                        : c.atEnd
                        ? 'Play again'
                        : 'Play',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    minimumSize: const Size.fromHeight(
                      AppSpacing.minTouchTarget,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'Back',
                  semanticLabel: 'Take back the last message',
                  onPressed: c.atStart ? null : c.back,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step',
                  semanticLabel: 'Send the next message',
                  onPressed: c.atEnd ? null : c.step,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: c.atStart ? null : c.reset,
                tooltip: 'Back to the start, nothing sent (R)',
                icon: const Icon(Icons.restart_alt_rounded),
                color: colors.textAccent,
              ),
              Tooltip(
                message: 'Show every message at once',
                child: TextButton.icon(
                  onPressed: c.atEnd ? null : c.showAll,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  icon: const Icon(Icons.unfold_more_rounded),
                  label: const Text('Show all'),
                ),
              ),
              const Spacer(),
              AppToggle<LadderSpeed>(
                semanticLabel: 'Playback speed',
                value: c.speed,
                items: <AppToggleItem<LadderSpeed>>[
                  for (final LadderSpeed s in LadderSpeed.values) (s, s.label),
                ],
                onChanged: (LadderSpeed s) => c.speed = s,
              ),
            ],
          ),
          if (reducedMotion)
            Text(
              'Reduced motion is on: arrows appear without drawing in.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// The presenter panel in Join and Roam: the mode (Roam only, in the
/// ladder), playback, then the Join or Roam settings.
class _JrPresenterPanel extends StatelessWidget {
  const _JrPresenterPanel(this.c);

  final EapLadderController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (c.mode != LadderMode.join) ...<Widget>[
          ElCard(child: LadderModeToggle(controller: c)),
          const SizedBox(height: AppSpacing.xs),
        ],
        _PresenterTransport(c),
        const SizedBox(height: AppSpacing.xs),
        if (c.whyMode) ...<Widget>[
          ScPresenterSettings(
            controller: c,
            leading: AssociationModeSelect(controller: c),
          ),
          PresenterDisclosure(
            title: 'Scan, EAP and 6 GHz',
            children: jrMainSettings(
              context,
              c,
              compact: true,
              groups: const <JrSettingsGroup>{
                JrSettingsGroup.scan,
                JrSettingsGroup.eap,
                JrSettingsGroup.sixGhz,
                JrSettingsGroup.addressCheck,
              },
            ),
          ),
          PresenterDisclosure(
            title: 'Timing',
            children: jrTimingSettings(context, c),
          ),
          PresenterDisclosure(
            title: 'Readouts',
            children: <Widget>[JrReadoutsCard(controller: c)],
          ),
        ] else
          JrPresenterSettings(
            controller: c,
            leading: c.mode == LadderMode.join
                ? AssociationModeSelect(controller: c)
                : null,
          ),
      ],
    );
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

class _TransportCard extends StatelessWidget {
  const _TransportCard(this.c);

  final EapLadderController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final String playLabel = c.playing
        ? 'Pause'
        : c.atEnd
        ? 'Play again'
        : 'Play';
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: c.playing
                  ? 'Pause the ladder'
                  : c.atEnd
                  ? 'Play the ladder again from the start'
                  : 'Play the ladder, one message at a time',
              excludeSemantics: true,
              child: FilledButton.icon(
                onPressed: c.togglePlay,
                icon: Icon(
                  c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(playLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                  textStyle: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'Back',
                  semanticLabel: 'Take back the last message',
                  onPressed: c.atStart ? null : c.back,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step',
                  semanticLabel: 'Send the next message',
                  onPressed: c.atEnd ? null : c.step,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  semanticLabel: 'Back to the start, nothing sent',
                  onPressed: c.atStart ? null : c.reset,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElOutlineButton(
                  icon: Icons.unfold_more_rounded,
                  label: 'Show all',
                  semanticLabel: 'Show every message at once',
                  onPressed: c.atEnd ? null : c.showAll,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<LadderSpeed>(
            label: 'Speed',
            semanticLabel: 'Playback speed',
            value: c.speed,
            items: <AppToggleItem<LadderSpeed>>[
              for (final LadderSpeed s in LadderSpeed.values) (s, s.label),
            ],
            onChanged: (LadderSpeed s) => c.speed = s,
          ),
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reduced motion is on. Arrows appear without drawing in, and '
              'the ladder waits for you: use Step, or press Play.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final EapLadderController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final LadderSequence s = c.sequence;
    final LadderConfig cfg = c.config;
    final LadderSkipped skipped = c.skipped;
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ElSectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xxs),
          ElRow(
            label: 'Over the air',
            value: '${s.airCount} frames',
            valueColor: ladderLegColor(LadderLeg.air, isLight: colors.isLight),
          ),
          ElRow(
            label: 'On the wire',
            value: s.usesRadius
                ? '${s.wireCount} RADIUS messages'
                : 'none (no RADIUS)',
            valueColor: s.usesRadius
                ? ladderLegColor(LadderLeg.wire, isLight: colors.isLight)
                : null,
          ),
          ElRow(label: 'RADIUS round trips', value: '${s.radiusRoundTrips}'),
          ElRow(
            label: 'Estimated time to connect, after the scan (illustrative)',
            value: formatLadderMs(s.estimatedMs),
            emphasize: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${s.afterScan.where((LadderMessage m) => m.leg == LadderLeg.air).length} '
            'frames x ${kAirFrameMs.round()} ms'
            '${s.usesRadius ? ' + ${s.radiusRoundTrips} round trips x ${cfg.radiusRttMs.round()} ms' : ''}'
            '. Client and server processing is not included.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ElSectionLabel(
            cfg.roam == LadderRoam.full
                ? 'Skipped relative to a full authentication'
                : 'Skipped relative to a full authentication '
                      '(${skipped.fewerMessages} fewer messages)',
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final String line in skipped.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: ElNote(icon: Icons.remove_circle_outline, message: line),
            ),
          const SizedBox(height: AppSpacing.xs),
          const ElNote(
            icon: Icons.travel_explore_rounded,
            message:
                'Not counted: the scan for the next AP. In measured handoffs '
                '(802.11b, open authentication; Mishra, Shin and Arbaugh 2003) '
                'the scan was over 90% of the delay. 802.11k neighbor reports '
                'shorten the scan; PMK caching and FT shorten only what this '
                'ladder shows.',
          ),
        ],
      ),
    );
  }
}

// ── Settings ────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard(this.c);

  final EapLadderController c;

  static EapMethod? _reference(LadderMethod m) {
    final String? name = m.eapTypesName;
    if (name == null) return null;
    for (final EapMethod e in EapTypesScreen.methods) {
      if (e.method == name) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final LadderConfig cfg = c.config;
    final EapMethod? ref = _reference(cfg.method);
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    final bool ttls = cfg.method == LadderMethod.eapTtls;
    final bool fragments = cfg.certificateMatters;
    final bool radius = cfg.radiusMatters;
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ElSectionLabel('Settings'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Method',
            semanticLabel: 'Authentication method',
            field: AppSelect<LadderMethod>(
              value: cfg.method,
              semanticLabel: 'Authentication method',
              items: <AppSelectItem<LadderMethod>>[
                for (final LadderMethod m in LadderMethod.values) (m, m.label),
              ],
              onChanged: (LadderMethod m) => c.method = m,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (ref != null) ...<Widget>[
            ElRow(label: 'Credential', value: ref.credential),
            ElRow(label: 'Server cert', value: ref.serverCert),
            ElRow(label: 'Client cert', value: ref.clientCert),
            Text('From the 802.1X / EAP Types reference.', style: note),
          ] else
            Text(
              cfg.method == LadderMethod.psk
                  ? 'A shared passphrase. The PMK is derived from it, so '
                        'there is no RADIUS server and no certificate.'
                  : 'A shared password, proven with SAE commit and confirm '
                        'without sending it. No RADIUS server and no '
                        'certificate.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<LadderInner>(
            label: 'Inner method (EAP-TTLS)',
            semanticLabel: 'Inner method inside the EAP-TTLS tunnel',
            value: ttls ? cfg.inner : LadderInner.mschapv2,
            enabled: ttls,
            items: <AppToggleItem<LadderInner>>[
              for (final LadderInner i in LadderInner.values) (i, i.label),
            ],
            onChanged: (LadderInner i) => c.inner = i,
          ),
          if (!ttls) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              cfg.method == LadderMethod.peap
                  ? 'PEAP here always carries MSCHAPv2 inside its tunnel.'
                  : 'Only EAP-TTLS has a choice of inner method.',
              style: note,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppToggle<LadderRoam>(
            label: 'Roam mode',
            semanticLabel: 'Roam mode',
            value: cfg.roam,
            items: <AppToggleItem<LadderRoam>>[
              for (final LadderRoam r in LadderRoam.values) (r, r.shortLabel),
            ],
            onChanged: (LadderRoam r) => c.roam = r,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(switch (cfg.roam) {
            LadderRoam.full =>
              'First connection, or a roam with nothing cached.',
            LadderRoam.pmkCaching =>
              'Back to an AP that still holds this client\'s PMK. OKC, a '
                  'vendor extension, lets the other APs of one controller '
                  'hold it too.',
            LadderRoam.ftOverAir =>
              'A roam inside an 802.11r mobility domain, after one full '
                  'first connection.',
          }, style: note),
          const SizedBox(height: AppSpacing.sm),
          ElSlider(
            label: 'Certificate size (fragments per certificate message)',
            valueText:
                '${cfg.certFragments} fragment${cfg.certFragments == 1 ? '' : 's'}',
            value: cfg.certFragments.toDouble(),
            min: kMinCertFragments.toDouble(),
            max: kMaxCertFragments.toDouble(),
            divisions: kMaxCertFragments - kMinCertFragments,
            onChanged: fragments ? (double v) => c.certFragments = v : null,
            semanticValue: (double v) =>
                '${v.round()} fragment${v.round() == 1 ? '' : 's'} per '
                'certificate message',
          ),
          Text(
            fragments
                ? 'How many EAP messages one certificate message needs. It '
                      'depends on the certificate chain and the server\'s '
                      'fragment size, so it is a setting here, not a fixed '
                      'count. Each extra fragment costs a round trip.'
                : 'No certificate is sent in this ${cfg.method.uses8021X ? 'roam mode' : 'method'}.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElSlider(
            label: 'RADIUS round-trip time (illustrative)',
            valueText: '${cfg.radiusRttMs.round()} ms',
            value: cfg.radiusRttMs,
            min: kMinRadiusRttMs,
            max: kMaxRadiusRttMs,
            divisions: (kMaxRadiusRttMs - kMinRadiusRttMs).round(),
            onChanged: radius ? (double v) => c.radiusRttMs = v : null,
            semanticValue: (double v) => '${v.round()} milliseconds',
          ),
          Text(
            radius
                ? 'AP to server and back, with the server\'s work. A server '
                      'on the same LAN answers in a few ms; one across a WAN '
                      'or a proxy chain takes longer.'
                : 'No RADIUS messages in this ${cfg.method.uses8021X ? 'roam mode' : 'method'}.',
            style: note,
          ),
        ],
      ),
    );
  }
}
