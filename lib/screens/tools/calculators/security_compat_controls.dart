// Why won't it associate? (spec 43): the mode select, the verdict band, the
// Client card and the Network card for Association, Frame by Frame
// (join-ladder).
//
// The model is lib/services/wifi_lab/security_compat_model.dart; the ladder is
// the Join ladder (eap_ladder_jr_stage.dart), stopped where the association
// fails with the shared failure marker (eap_ladder_failure.dart, spec 42).
// Everything here reads and writes the one EapLadderController.
//
// Wording (Keith, 2026-09-29): associate and association, never join; a
// Wi-Fi 7 association is "a Wi-Fi 7 connection".
//
// COLOR (GL-003 §8.13). The verdict band's hue is a computed verdict: success
// when the pair associates, warning when a Wi-Fi 7 pair falls back to Wi-Fi
// 6, danger when it never tries, is refused or is not offered. The hue tints
// only the band's icon and border, always with the icon's shape and the
// words. Controls follow §8.14: four or more options (client preset, network
// security, client PMF) are Selects; the mode is a Select too, because its
// labels are too long for a phone-width toggle.
//
// States: associates / associates as Wi-Fi 6 / never tries / refused / not
// offered (the verdict band); not found (the scan missed the beacon: the band
// says the client never read the security); custom client (the preset select
// reads Custom); disabled settings with a sentence saying why (PMF outside
// WPA2, H2E only outside the SAE modes). Loading and error are not reachable:
// the model is synchronous and pure.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/join_roam.dart';
import '../../../services/wifi_lab/security_compat_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_parts.dart';

const String kPlayAssociationLabel = 'Play the association';
const String kWhyWontItAssociateLabel = 'Why won\'t it associate?';

/// Play the association, or Why won't it associate?
class AssociationModeSelect extends StatelessWidget {
  const AssociationModeSelect({super.key, required this.controller});

  final EapLadderController controller;

  static const Key selectKey = ValueKey<String>('association-mode-select');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => LabeledField(
        label: 'Mode',
        semanticLabel: 'Mode',
        field: AppSelect<bool>(
          key: selectKey,
          value: controller.whyMode,
          semanticLabel:
              'Mode: play the association, or why won\'t it '
              'associate',
          items: const <AppSelectItem<bool>>[
            (false, kPlayAssociationLabel),
            (true, kWhyWontItAssociateLabel),
          ],
          onChanged: (bool v) => controller.whyMode = v,
        ),
      ),
    );
  }
}

// ── Verdict band ────────────────────────────────────────────────────────────

/// The verdict above the ladder. Headline size in presenter mode.
class ScVerdictBand extends StatelessWidget {
  const ScVerdictBand({super.key, required this.controller});

  final EapLadderController controller;

  static const Key bandKey = ValueKey<String>('sc-verdict-band');

  @override
  Widget build(BuildContext context) {
    final ScVerdict? v = controller.verdict;
    if (v == null) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final bool presenter = PresenterMode.isActive(context);
    final bool fallback = v.wifi6Because != null;
    final (Color hue, IconData icon) = switch (v.outcome) {
      ScOutcome.associates when fallback => (
        colors.statusWarning,
        Icons.warning_amber_rounded,
      ),
      ScOutcome.associates => (
        colors.statusSuccess,
        Icons.check_circle_rounded,
      ),
      ScOutcome.neverTries => (colors.statusDanger, Icons.block_rounded),
      ScOutcome.refused => (colors.statusDanger, Icons.cancel_rounded),
      ScOutcome.notOffered => (
        colors.statusDanger,
        Icons.do_not_disturb_on_rounded,
      ),
    };
    final bool notFound = !controller.jr.found;
    final TextStyle headline = presenter
        ? sc
              .headlineStyle(text.titleLarge ?? const TextStyle())
              .copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)
        : (text.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          );
    final TextStyle? body = text.bodyMedium?.copyWith(
      color: colors.textPrimary,
    );
    final TextStyle? source = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final String label = <String>[
      v.headline,
      if (notFound)
        'But on this scan the beacon was missed, so the client never read the '
            'network\'s security.',
      v.why,
      'Source: ${v.source}',
    ].join('. ').replaceAll('..', '.');
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        key: bandKey,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: hue, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: hue, size: sc.markerSize(presenter ? 32 : 24)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(v.headline, style: headline),
                  if (notFound) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Not found on this scan: the beacon was missed, so the '
                      'client never read the network\'s security. Lengthen '
                      'the passive dwell or use an active scan.',
                      style: body,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxs),
                  Text(v.why, style: body),
                  // On a projector the source line gives its height to the
                  // ladder; it stays in the phone view, the help and the copy.
                  if (!presenter) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text('Source: ${v.source}', style: source),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Client card ─────────────────────────────────────────────────────────────

/// The client: a preset, and a fold with every capability.
class ScClientCard extends StatelessWidget {
  const ScClientCard({super.key, required this.controller, this.card = true});

  final EapLadderController controller;

  /// Draw its own card (false inside the presenter panel).
  final bool card;

  static const Key presetKey = ValueKey<String>('sc-client-preset');

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      if (card) ...<Widget>[
        const ElSectionLabel('Client'),
        const SizedBox(height: AppSpacing.xs),
      ],
      ScClientPresetSelect(controller: controller),
      const SizedBox(height: AppSpacing.xxs),
      PresenterDisclosure(
        title: 'Client capabilities (AKM, ciphers, PMF, bands)',
        children: scCapabilityControls(context, controller),
      ),
    ];
    final Widget col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return card ? ElCard(child: col) : col;
  }
}

/// The client preset select, reading Custom when edited by hand.
class ScClientPresetSelect extends StatelessWidget {
  const ScClientPresetSelect({super.key, required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final ScClientPreset? preset = controller.scPreset;
    return LabeledField(
      label: 'Client',
      semanticLabel: 'Client device',
      field: AppSelect<ScClientPreset?>(
        key: ScClientCard.presetKey,
        value: preset,
        semanticLabel: 'Client device',
        items: <AppSelectItem<ScClientPreset?>>[
          for (final ScClientPreset p in ScClientPreset.values) (p, p.label),
          if (preset == null) (null, 'Custom'),
        ],
        onChanged: (ScClientPreset? p) {
          if (p != null) controller.scPreset = p;
        },
      ),
    );
  }
}

/// Every client capability, as switches and one PMF select.
List<Widget> scCapabilityControls(BuildContext context, EapLadderController c) {
  final AppColorScheme colors = context.colors;
  final TextStyle? note = Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
  final ScClient cl = c.scClient;
  void set(ScClient next) => c.scClient = next;
  return <Widget>[
    const SizedBox(height: AppSpacing.xxs),
    const ElSectionLabel('Key management (AKM) it knows'),
    for (final ScAkm a in ScAkm.values)
      ScSwitchRow(
        title: a.label,
        value: cl.akms.contains(a),
        onChanged: (bool on) => set(cl.withAkm(a, on)),
      ),
    const SizedBox(height: AppSpacing.xs),
    const ElSectionLabel('Ciphers it can do'),
    for (final ScCipher x in ScCipher.values)
      ScSwitchRow(
        title: x.label,
        value: cl.ciphers.contains(x),
        onChanged: (bool on) => set(cl.withCipher(x, on)),
      ),
    const SizedBox(height: AppSpacing.xs),
    LabeledField(
      label: 'PMF (802.11w)',
      semanticLabel: 'Client PMF support',
      field: AppSelect<ScClientPmf>(
        value: cl.pmf,
        semanticLabel: 'Client PMF support',
        items: <AppSelectItem<ScClientPmf>>[
          for (final ScClientPmf p in ScClientPmf.values) (p, p.label),
        ],
        onChanged: (ScClientPmf p) => set(cl.copyWith(pmf: p)),
      ),
    ),
    const SizedBox(height: AppSpacing.xxs),
    Text(
      cl.pmf.readsBits
          ? '${cl.pmf.bits}. The client reads the network\'s bits and does '
                'not try when they cannot work.'
          : 'Older than PMF: it does not know the MFPC and MFPR bits, so it '
                'ignores them and tries anyway.',
      style: note,
    ),
    const SizedBox(height: AppSpacing.xs),
    ScSwitchRow(
      title: 'SAE hash-to-element (H2E)',
      value: cl.h2e,
      onChanged: (bool on) => set(cl.copyWith(h2e: on)),
    ),
    const SizedBox(height: AppSpacing.xs),
    const ElSectionLabel('Radios'),
    for (final JrBand b in JrBand.values)
      ScSwitchRow(
        title: b.label,
        value: cl.bands.contains(b),
        onChanged: (bool on) => set(cl.withBand(b, on)),
      ),
    ScSwitchRow(
      title: 'Wi-Fi 7',
      value: cl.wifi7,
      onChanged: (bool on) => set(cl.copyWith(wifi7: on)),
    ),
    Text(
      'Presets are generic and illustrative: real devices vary by model, '
      'driver and operating system version.',
      style: note,
    ),
  ];
}

// ── Network card ────────────────────────────────────────────────────────────

/// Groups of the network settings, so the presenter panel can fold some.
enum ScNetworkGroup { security, pmf, radio, extras }

/// The network: its security, PMF, band, Wi-Fi 7 AP and H2E only.
List<Widget> scNetworkControls(
  BuildContext context,
  EapLadderController c, {
  Set<ScNetworkGroup> groups = const <ScNetworkGroup>{
    ScNetworkGroup.security,
    ScNetworkGroup.pmf,
    ScNetworkGroup.radio,
    ScNetworkGroup.extras,
  },
  bool compact = false,
}) {
  final AppColorScheme colors = context.colors;
  final TextStyle? note = Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
  final ScNetwork n = c.scNetwork;
  final JrConfig cfg = c.jrConfig;
  final JrPmf pmf = n.pmfBits;
  final bool pmfChoosable = n.security.pmfChoosable;
  final List<List<Widget>> blocks = <List<Widget>>[];

  if (groups.contains(ScNetworkGroup.security)) {
    blocks.add(<Widget>[
      LabeledField(
        label: 'Network security',
        semanticLabel: 'Network security',
        field: AppSelect<ScNetSecurity>(
          value: n.security,
          semanticLabel: 'Network security',
          items: <AppSelectItem<ScNetSecurity>>[
            for (final ScNetSecurity s in ScNetSecurity.values) (s, s.label),
          ],
          onChanged: (ScNetSecurity s) => c.scNetSecurity = s,
        ),
      ),
      if (!compact) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Offers ${n.isOpen ? 'no RSN element' : n.akms.map((ScAkm a) => a.tagged).join(', ')}.'
          '${n.band == JrBand.g6 && !n.security.allowedIn6GHz ? ' Not allowed in 6 GHz.' : ''}',
          style: note,
        ),
      ],
    ]);
  }

  if (groups.contains(ScNetworkGroup.pmf)) {
    blocks.add(<Widget>[
      AppToggle<JrPmf>(
        label: 'PMF (802.11w)',
        semanticLabel: 'Network protected management frames',
        value: pmf,
        enabled: pmfChoosable,
        expand: true,
        items: <AppToggleItem<JrPmf>>[
          for (final JrPmf p in JrPmf.values) (p, p.label),
        ],
        onChanged: (JrPmf p) => c.jrConfig = cfg.copyWith(pmf: p),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        pmfChoosable
            ? '${pmf.bits}.'
            : n.isOpen
            ? 'Off: an open network has no keys to protect frames with.'
            : '${pmf.label}: ${n.security.label} sets ${pmf.bits}.',
        style: note,
      ),
    ]);
  }

  if (groups.contains(ScNetworkGroup.radio)) {
    blocks.add(<Widget>[
      AppToggle<JrBand>(
        label: 'Band',
        semanticLabel: 'Band',
        value: cfg.band,
        expand: true,
        items: <AppToggleItem<JrBand>>[
          for (final JrBand b in JrBand.values) (b, b.label),
        ],
        onChanged: (JrBand b) => c.jrConfig = cfg.copyWith(band: b),
      ),
    ]);
  }

  if (groups.contains(ScNetworkGroup.extras)) {
    blocks.add(<Widget>[
      ScSwitchRow(
        title: 'Wi-Fi 7 AP',
        value: n.wifi7,
        onChanged: (bool on) => c.apWifi7 = on,
      ),
      if (!compact)
        Text(
          'A Wi-Fi 7 AP also enables SAE type 24 and GCMP-256. A Wi-Fi 7 '
          'connection needs them and PMF; without them a Wi-Fi 7 client '
          'associates as Wi-Fi 6.',
          style: note,
        ),
      ScSwitchRow(
        title: 'SAE: hash-to-element (H2E) only',
        value: n.h2eOnly,
        enabled: n.security.usesSae,
        onChanged: (bool on) => c.h2eOnly = on,
      ),
      Text(
        !n.security.usesSae
            ? 'Only for the WPA3-Personal modes.'
            : n.band == JrBand.g6
            ? 'In 6 GHz, H2E is required either way (a Wi-Fi Alliance rule).'
            : 'Advertises BSS membership selector 123.',
        style: note,
      ),
    ]);
  }

  return <Widget>[
    for (int i = 0; i < blocks.length; i++) ...<Widget>[
      if (i > 0) const SizedBox(height: AppSpacing.sm),
      ...blocks[i],
    ],
  ];
}

class ScNetworkCard extends StatelessWidget {
  const ScNetworkCard({super.key, required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ElSectionLabel('Network'),
          const SizedBox(height: AppSpacing.xs),
          ...scNetworkControls(context, controller),
        ],
      ),
    );
  }
}

/// The presenter panel's settings in Why won't it associate?: the client
/// and the network security in view, the rest folded.
class ScPresenterSettings extends StatelessWidget {
  const ScPresenterSettings({
    super.key,
    required this.controller,
    this.leading,
  });

  final EapLadderController controller;

  /// Shown first inside the card (the mode select).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final EapLadderController c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ElCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(height: AppSpacing.sm),
              ],
              ScClientPresetSelect(controller: c),
              const SizedBox(height: AppSpacing.xs),
              ...scNetworkControls(
                context,
                c,
                compact: true,
                groups: const <ScNetworkGroup>{
                  ScNetworkGroup.security,
                  ScNetworkGroup.radio,
                },
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'PMF, Wi-Fi 7 AP and H2E',
          children: scNetworkControls(
            context,
            c,
            compact: true,
            groups: const <ScNetworkGroup>{
              ScNetworkGroup.pmf,
              ScNetworkGroup.extras,
            },
          ),
        ),
        PresenterDisclosure(
          title: 'Client capabilities',
          children: scCapabilityControls(context, c),
        ),
      ],
    );
  }
}

/// A labeled switch row; the whole row toggles.
class ScSwitchRow extends StatelessWidget {
  const ScSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: text.bodyMedium?.copyWith(
                    color: enabled ? colors.textPrimary : colors.textDisabled,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
