// The controls for the Join and Roam ladders (spec 21b): readouts and
// settings over the shared EapLadderController.
//
// Roam is a mode of the 802.1X and EAP Ladder (eap-ladder). Join is its own
// tool, Association, Frame by Frame (join-ladder, Keith 2026-09-26),
// which drives the same controller in Join mode; both read these widgets, so
// the two tools cannot drift apart.
//
// Control types follow GL-003 §8.14: four or more options (security, roam
// method, EAP method) are a Select; two or three (band, scan type, 6 GHz
// discovery, address check, PMF, inner method) are AppToggles. A setting
// that changes nothing for the chosen options is disabled with a sentence
// saying why. ACD and DNAv4 are spelled out wherever they first appear.
//
// Every time is a labeled, illustrative input: no published measurement
// breaks a typical join down by phase (brief §1). Published roam figures are
// shown only as labeled context (brief §2), never as the model's output.

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
import 'eap_ladder_palette.dart';
import 'eap_ladder_parts.dart';

/// The row for [m] in the app's 802.1X / EAP Types reference, or null.
EapMethod? eapTypesRow(LadderMethod m) {
  final String? name = m.eapTypesName;
  if (name == null) return null;
  for (final EapMethod e in EapTypesScreen.methods) {
    if (e.method == name) return e;
  }
  return null;
}

/// Authenticate or Roam, for the 802.1X and EAP Ladder. (Join is its own
/// tool and has no mode toggle.)
class LadderModeToggle extends StatelessWidget {
  const LadderModeToggle({super.key, required this.controller});

  final EapLadderController controller;

  static const List<LadderMode> modes = <LadderMode>[
    LadderMode.authenticate,
    LadderMode.roam,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => AppToggle<LadderMode>(
        label: 'Mode',
        semanticLabel: 'Ladder mode: authenticate, or roam between two APs',
        value: controller.mode == LadderMode.join
            ? LadderMode.authenticate
            : controller.mode,
        expand: true,
        items: <AppToggleItem<LadderMode>>[
          for (final LadderMode m in modes) (m, m.label),
        ],
        onChanged: (LadderMode m) => controller.mode = m,
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class JrReadoutsCard extends StatelessWidget {
  const JrReadoutsCard({super.key, required this.controller});

  final EapLadderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final JrSequence s = controller.jr;
    final bool roam = s.mode == LadderMode.roam;
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    final List<String> wire = <String>[
      if (s.radiusCount > 0) '${s.radiusCount} RADIUS',
      if (s.lanCount > 0) '${s.lanCount} LAN',
      if (s.dsCount > 0) '${s.dsCount} AP to AP',
    ];
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
          ElRow(label: 'Management frames', value: '${s.managementCount}'),
          ElRow(
            label: 'Data frames (EAPOL, EAPOL-Key, IP)',
            value: '${s.dataCount}',
          ),
          ElRow(
            label: 'On the wire',
            value: s.wireCount == 0
                ? 'none'
                : '${s.wireCount} packets (${wire.join(', ')})',
            valueColor: s.wireCount == 0
                ? null
                : ladderLegColor(LadderLeg.wire, isLight: colors.isLight),
          ),
          if (s.radiusRoundTrips > 0)
            ElRow(label: 'RADIUS round trips', value: '${s.radiusRoundTrips}'),
          const SizedBox(height: AppSpacing.xs),
          ElSectionLabel(roam ? 'Time by part' : 'Time by phase'),
          if (roam)
            for (final RoamBar b in RoamBar.values)
              ElRow(label: b.label, value: formatJrMs(s.roamTotals[b]!))
          else
            for (final JrClock c in JrClock.joinClocks)
              if (s.clockTotals[c]! > 0)
                ElRow(
                  label: c == JrClock.addressCheck
                      ? 'Address check '
                            '(${s.config.addressCheck.shortLabel})'
                      : c.label,
                  value: formatJrMs(s.clockTotals[c]!),
                ),
          ElRow(
            label: roam
                ? 'Roam total (illustrative)'
                : controller.whyMode && s.failed
                ? 'Time until it stops (illustrative)'
                : 'Total time to associate, to the first useful packet '
                      '(illustrative)',
            value: formatJrMs(s.totalMs),
            emphasize: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            roam
                ? 'Built from the settings: scan dwell, frame time, RADIUS '
                      'round trips x round-trip time, crypto time, and AP to '
                      'AP time over the DS.'
                : 'Built from the settings. No published measurement breaks a '
                      'typical association down by phase, so each phase is an '
                      'input, not a claim.',
            style: note,
          ),
          if (roam && controller.roamSkipped != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            ElSectionLabel(
              s.config.roamMethod == JrRoamMethod.full
                  ? 'Skipped relative to a full 802.1X roam'
                  : 'Skipped relative to a full 802.1X roam '
                        '(${controller.roamSkipped!.fewerMessages} fewer '
                        'messages)',
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (final String line in controller.roamSkipped!.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: ElNote(icon: Icons.remove_circle_outline, message: line),
              ),
            const SizedBox(height: AppSpacing.xs),
            const ElSectionLabel('Published figures (context only)'),
            const SizedBox(height: AppSpacing.xxs),
            const ElNote(
              icon: Icons.menu_book_rounded,
              message:
                  'RFC 5169: an EAP-TLS run needs at least 3, typically 4 or '
                  'more, round trips.',
            ),
            const SizedBox(height: AppSpacing.xxs),
            ElNote(
              icon: Icons.science_outlined,
              message:
                  'FT over the air: ${formatJrMs(kFtOverAirCaptureMs)}. FT '
                  'over the DS: ${formatJrMs(kFtOverDsCaptureMs)}, from FT '
                  'Action Request to Reassociation Response. One lab capture '
                  'each (single capture), not a typical figure.',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Settings ────────────────────────────────────────────────────────────────

/// Which settings a card shows: the main choices, or the timing sliders.
enum JrSettingsPart { main, timing }

class JrSettingsCard extends StatelessWidget {
  const JrSettingsCard({
    super.key,
    required this.controller,
    this.parts = const <JrSettingsPart>{
      JrSettingsPart.main,
      JrSettingsPart.timing,
    },
    this.card = true,
    this.groups = kAllJrSettingsGroups,
  });

  final EapLadderController controller;
  final Set<JrSettingsPart> parts;

  /// Which of the main settings to show.
  final Set<JrSettingsGroup> groups;

  /// Draw its own card (false inside a presenter disclosure).
  final bool card;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      if (parts.contains(JrSettingsPart.main)) ...<Widget>[
        if (card) ...<Widget>[
          const ElSectionLabel('Settings'),
          const SizedBox(height: AppSpacing.xs),
        ],
        ...jrMainSettings(context, controller, groups: groups),
      ],
      if (parts.contains(JrSettingsPart.timing)) ...<Widget>[
        if (parts.contains(JrSettingsPart.main))
          const SizedBox(height: AppSpacing.sm),
        if (card) ...<Widget>[
          const ElSectionLabel('Timing (illustrative inputs)'),
          const SizedBox(height: AppSpacing.xs),
        ],
        ...jrTimingSettings(context, controller),
      ],
    ];
    final Widget col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return card ? ElCard(child: col) : col;
  }
}

/// Groups of the main Join and Roam settings, so the presenter panel can put
/// some in view and fold the rest.
enum JrSettingsGroup {
  /// Security (Join) or roam method (Roam), with its notes.
  choice,

  /// EAP method, inner method and certificate size, when 802.1X runs.
  eap,

  /// PMF (802.11w).
  pmf,

  /// Band.
  radio,

  /// Scan type (active or passive).
  scan,

  /// How a 6 GHz AP is found.
  sixGhz,

  /// ACD or DNAv4 (Join only).
  addressCheck,
}

/// Every group of the main Join and Roam settings.
const Set<JrSettingsGroup> kAllJrSettingsGroups = <JrSettingsGroup>{
  JrSettingsGroup.choice,
  JrSettingsGroup.eap,
  JrSettingsGroup.pmf,
  JrSettingsGroup.radio,
  JrSettingsGroup.scan,
  JrSettingsGroup.sixGhz,
  JrSettingsGroup.addressCheck,
};

/// The main choices for Join or Roam, in [groups].
List<Widget> jrMainSettings(
  BuildContext context,
  EapLadderController c, {
  bool compact = false,
  Set<JrSettingsGroup> groups = kAllJrSettingsGroups,
}) {
  final AppColorScheme colors = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  final TextStyle? note = text.bodySmall?.copyWith(color: colors.textTertiary);
  final JrConfig cfg = c.jrConfig;
  final bool roam = c.mode == LadderMode.roam;
  // Why won't it associate? (spec 43) draws what the pair negotiates, not the
  // Join mode's security setting.
  final JrSecurity sec = roam
      ? JrSecurity.dot1x
      : c.whyMode
      ? c.jr.security
      : cfg.effectiveSecurity;
  final bool dot1x = roam
      ? cfg.roamMethod == JrRoamMethod.full
      : sec == JrSecurity.dot1x;
  void set(JrConfig next) => c.jrConfig = next;
  final EapMethod? ref = eapTypesRow(cfg.eapMethod);
  final bool six = cfg.band == JrBand.g6;
  final JrPmf pmf = cfg.pmfFor(sec);
  final bool pmfChoosable = cfg.pmfChoosable(sec);

  final List<List<Widget>> blocks = <List<Widget>>[];

  if (groups.contains(JrSettingsGroup.choice)) {
    blocks.add(<Widget>[
      if (roam) ...<Widget>[
        LabeledField(
          label: 'Roam method',
          semanticLabel: 'Roam method',
          field: AppSelect<JrRoamMethod>(
            value: cfg.roamMethod,
            semanticLabel: 'Roam method',
            items: <AppSelectItem<JrRoamMethod>>[
              for (final JrRoamMethod r in JrRoamMethod.values)
                (r, r.shortLabel),
            ],
            onChanged: (JrRoamMethod r) => set(cfg.copyWith(roamMethod: r)),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(switch (cfg.roamMethod) {
          JrRoamMethod.full =>
            'Nothing cached: EAP runs again with the RADIUS server, then the '
                '4-way handshake.',
          JrRoamMethod.pmkCaching =>
            'Back to an AP that still holds this client\'s PMK: the PMKID in '
                'the Reassociation Request replaces EAP.',
          JrRoamMethod.okc =>
            'OKC: the same frames as PMK caching, with the PMKID computed for '
                'the new AP from the same PMK. A vendor extension, not IEEE; '
                'Apple\'s own key caching is not compatible with it.',
          JrRoamMethod.ftOverAir =>
            '802.11r: four frames straight to the target AP, with the 4-way '
                'handshake folded in.',
          JrRoamMethod.ftOverDs =>
            '802.11r over the DS: FT Action frames go to the current AP, '
                'which forwards them to the target over the wire; then '
                'Reassociation with the target.',
        }, style: note),
        if (!compact) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Roam is drawn for an 802.1X network. FT and key caching exist '
            'for personal networks too; the frames that change are the same.',
            style: note,
          ),
        ],
      ] else ...<Widget>[
        LabeledField(
          label: 'Security',
          semanticLabel: 'Network security',
          field: AppSelect<JrSecurity>(
            value: sec,
            semanticLabel: 'Network security',
            items: <AppSelectItem<JrSecurity>>[
              for (final JrSecurity s in JrSecurity.values)
                if (!six || s.allowedIn6GHz) (s, s.label),
            ],
            onChanged: (JrSecurity s) => set(cfg.copyWith(security: s)),
          ),
        ),
        if (cfg.securityForcedBy6GHz && !compact) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '6 GHz requires WPA3 or OWE with PMF, so '
            '${cfg.security.label} is drawn as ${sec.label}.',
            style: note,
          ),
        ],
      ],
    ]);
  }

  if (groups.contains(JrSettingsGroup.eap) && dot1x) {
    blocks.add(<Widget>[
      LabeledField(
        label: 'EAP method',
        semanticLabel: 'EAP method',
        field: AppSelect<LadderMethod>(
          value: cfg.eapMethod,
          semanticLabel: 'EAP method',
          items: <AppSelectItem<LadderMethod>>[
            for (final LadderMethod m in LadderMethod.values)
              if (m.uses8021X) (m, m.label),
          ],
          onChanged: (LadderMethod m) => set(cfg.copyWith(eapMethod: m)),
        ),
      ),
      if (cfg.eapMethod == LadderMethod.eapTtls) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        AppToggle<LadderInner>(
          label: 'Inner method (EAP-TTLS)',
          semanticLabel: 'Inner method inside the EAP-TTLS tunnel',
          value: cfg.inner,
          items: <AppToggleItem<LadderInner>>[
            for (final LadderInner i in LadderInner.values) (i, i.label),
          ],
          onChanged: (LadderInner i) => set(cfg.copyWith(inner: i)),
        ),
      ],
      if (ref != null && !compact) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        ElRow(label: 'Credential', value: ref.credential),
        ElRow(label: 'Client cert', value: ref.clientCert),
        Text('From the 802.1X / EAP Types reference.', style: note),
      ],
      const SizedBox(height: AppSpacing.xs),
      ElSlider(
        label: 'Certificate size (fragments per certificate message)',
        valueText:
            '${cfg.certFragments} fragment${cfg.certFragments == 1 ? '' : 's'}',
        value: cfg.certFragments.toDouble(),
        min: kMinCertFragments.toDouble(),
        max: kMaxCertFragments.toDouble(),
        divisions: kMaxCertFragments - kMinCertFragments,
        onChanged: (double v) => set(cfg.copyWith(certFragments: v.round())),
        semanticValue: (double v) =>
            '${v.round()} fragment${v.round() == 1 ? '' : 's'} per '
            'certificate message',
      ),
    ]);
  }

  if (groups.contains(JrSettingsGroup.pmf)) {
    blocks.add(<Widget>[
      AppToggle<JrPmf>(
        label: 'PMF (802.11w)',
        semanticLabel: 'Protected management frames',
        value: pmf,
        enabled: pmfChoosable,
        expand: true,
        items: <AppToggleItem<JrPmf>>[
          for (final JrPmf p in JrPmf.values) (p, p.label),
        ],
        onChanged: (JrPmf p) => set(cfg.copyWith(pmf: p)),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        pmfChoosable
            ? '${pmf.bits}. PMF protects deauthentication, disassociation and '
                  'robust Action frames once keys exist; never beacons, '
                  'probes, authentication or association.'
            : switch (sec) {
                JrSecurity.open =>
                  'Off: an open network has no keys to protect frames with.',
                _ when six => 'Required: 6 GHz requires PMF.',
                _ => 'Required: ${sec.label} requires PMF.',
              },
        style: note,
      ),
    ]);
  }

  // Band and scan share one block (8 px apart) when both are shown, as
  // before the groups were split for Why won't it associate?.
  final Widget scanToggle = AppToggle<JrScanType>(
    label: 'Scan',
    semanticLabel: 'Scan type: active probes, or passive listening',
    value: cfg.scanType,
    expand: true,
    items: <AppToggleItem<JrScanType>>[
      for (final JrScanType t in JrScanType.values) (t, t.label),
    ],
    onChanged: (JrScanType t) => set(cfg.copyWith(scanType: t)),
  );
  if (groups.contains(JrSettingsGroup.radio)) {
    blocks.add(<Widget>[
      AppToggle<JrBand>(
        label: 'Band',
        semanticLabel: 'Band',
        value: cfg.band,
        expand: true,
        items: <AppToggleItem<JrBand>>[
          for (final JrBand b in JrBand.values) (b, b.label),
        ],
        onChanged: (JrBand b) => set(cfg.copyWith(band: b)),
      ),
      if (groups.contains(JrSettingsGroup.scan)) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        scanToggle,
      ],
    ]);
  } else if (groups.contains(JrSettingsGroup.scan)) {
    blocks.add(<Widget>[scanToggle]);
  }

  if (groups.contains(JrSettingsGroup.sixGhz)) {
    blocks.add(<Widget>[
      AppToggle<JrSixGhzDiscovery>(
        label: '6 GHz discovery',
        semanticLabel: 'How the client finds a 6 GHz AP',
        value: cfg.sixGhz,
        enabled: six,
        expand: true,
        items: <AppToggleItem<JrSixGhzDiscovery>>[
          for (final JrSixGhzDiscovery d in JrSixGhzDiscovery.values)
            (d, d.shortLabel),
        ],
        onChanged: (JrSixGhzDiscovery d) => set(cfg.copyWith(sixGhz: d)),
      ),
      const SizedBox(height: AppSpacing.xxs),
      if (compact &&
          !roam &&
          !c.whyMode &&
          cfg.securityForcedBy6GHz) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '6 GHz requires WPA3 or OWE with PMF, so '
          '${cfg.security.label} is drawn as ${sec.label}.',
          style: note,
        ),
      ],
      Text(
        six
            ? '${cfg.sixGhz.label}.'
            : 'Only for 6 GHz: probes go only to the 15 PSCs, or RNR in a '
                  '2.4 or 5 GHz beacon names the 6 GHz AP.',
        style: note,
      ),
    ]);
  }

  if (groups.contains(JrSettingsGroup.addressCheck) && !roam) {
    blocks.add(<Widget>[
      AppToggle<JrAddressCheck>(
        label: 'Address check',
        semanticLabel:
            'Address check: Address Conflict Detection (ACD), or Detecting '
            'Network Attachment (DNAv4)',
        value: cfg.addressCheck,
        expand: true,
        items: <AppToggleItem<JrAddressCheck>>[
          for (final JrAddressCheck a in JrAddressCheck.values)
            (a, a.shortLabel),
        ],
        onChanged: (JrAddressCheck a) => set(cfg.copyWith(addressCheck: a)),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        cfg.addressCheck == JrAddressCheck.acd
            ? '${JrAddressCheck.acd.label}: three ARP probes 1 to 2 s apart, '
                  'then an announcement. It can take several seconds.'
            : '${JrAddressCheck.dnav4.label}: one unicast ARP to the gateway '
                  'it remembers, under 10 ms.',
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

/// The timing sliders for Join or Roam.
List<Widget> jrTimingSettings(BuildContext context, EapLadderController c) {
  final AppColorScheme colors = context.colors;
  final TextStyle? note = Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
  final JrConfig cfg = c.jrConfig;
  final bool roam = c.mode == LadderMode.roam;
  final JrSecurity sec = c.whyMode ? c.jr.security : cfg.effectiveSecurity;
  final bool eap = roam
      ? cfg.roamMethod == JrRoamMethod.full
      : sec == JrSecurity.dot1x;
  final bool crypto = roam
      ? cfg.roamMethod == JrRoamMethod.full
      : sec != JrSecurity.open && sec != JrSecurity.psk;
  final bool active = cfg.scanType == JrScanType.active;
  void set(JrConfig next) => c.jrConfig = next;
  String ms(double v) => formatJrMs(v);

  return <Widget>[
    ElSlider(
      label: 'Active dwell per channel',
      valueText: ms(cfg.activeDwellMs),
      value: cfg.activeDwellMs,
      min: kMinActiveDwellMs,
      max: kMaxActiveDwellMs,
      divisions: ((kMaxActiveDwellMs - kMinActiveDwellMs) / 5).round(),
      onChanged: active
          ? (double v) => set(cfg.copyWith(activeDwellMs: v.roundToDouble()))
          : null,
      semanticValue: (double v) => '${v.round()} milliseconds per channel',
    ),
    ElSlider(
      label: 'Passive dwell per channel',
      valueText: ms(cfg.passiveDwellMs),
      value: cfg.passiveDwellMs,
      min: kMinPassiveDwellMs,
      max: kMaxPassiveDwellMs,
      divisions: ((kMaxPassiveDwellMs - kMinPassiveDwellMs)).round(),
      onChanged: (double v) =>
          set(cfg.copyWith(passiveDwellMs: v.roundToDouble())),
      semanticValue: (double v) => '${v.round()} milliseconds per channel',
    ),
    Text(
      'Defaults are one real example (Linux mac80211: about 30 ms active, '
      '111 ms passive); many drivers scan in firmware with their own dwell. '
      'Passive dwell also applies to DFS channels in an active scan. A dwell '
      'under ${ms(kFirstBeaconOffsetMs)} misses the AP\'s beacon here.',
      style: note,
    ),
    const SizedBox(height: AppSpacing.xs),
    ElSlider(
      label: 'Time per frame over the air',
      valueText: ms(cfg.frameMs),
      value: cfg.frameMs,
      min: kMinFrameMs,
      max: kMaxFrameMs,
      divisions: ((kMaxFrameMs - kMinFrameMs) / 0.5).round(),
      onChanged: (double v) =>
          set(cfg.copyWith(frameMs: (v * 2).roundToDouble() / 2)),
      semanticValue: (double v) => '${v.toStringAsFixed(1)} milliseconds',
    ),
    Text(
      'One frame with its wait for the medium and its ACK. This sets the '
      '4-way handshake too: four frames.',
      style: note,
    ),
    const SizedBox(height: AppSpacing.xs),
    ElSlider(
      label: 'RADIUS round-trip time',
      valueText: ms(cfg.radiusRttMs),
      value: cfg.radiusRttMs,
      min: kMinRadiusRttMs,
      max: kMaxRadiusRttMs,
      divisions: (kMaxRadiusRttMs - kMinRadiusRttMs).round(),
      onChanged: eap
          ? (double v) => set(cfg.copyWith(radiusRttMs: v.roundToDouble()))
          : null,
      semanticValue: (double v) => '${v.round()} milliseconds',
    ),
    ElSlider(
      label: 'Crypto time (public-key work)',
      valueText: ms(cfg.cryptoMs),
      value: cfg.cryptoMs,
      min: kMinCryptoMs,
      max: kMaxCryptoMs,
      divisions: ((kMaxCryptoMs - kMinCryptoMs) / 5).round(),
      onChanged: crypto
          ? (double v) => set(cfg.copyWith(cryptoMs: v.roundToDouble()))
          : null,
      semanticValue: (double v) => '${v.round()} milliseconds',
    ),
    Text(
      eap || crypto
          ? 'Authentication time = EAP round trips x RADIUS time + crypto '
                'time + the 4-way handshake. Crypto covers TLS, SAE or OWE.'
          : 'No RADIUS server and no public-key work with this '
                '${roam ? 'roam method' : 'security'}.',
      style: note,
    ),
    if (roam) ...<Widget>[
      const SizedBox(height: AppSpacing.xs),
      ElSlider(
        label: 'AP to AP round trip, over the DS',
        valueText: ms(cfg.dsRttMs),
        value: cfg.dsRttMs,
        min: kMinDsRttMs,
        max: kMaxDsRttMs,
        divisions: (kMaxDsRttMs - kMinDsRttMs).round(),
        onChanged: cfg.roamMethod == JrRoamMethod.ftOverDs
            ? (double v) => set(cfg.copyWith(dsRttMs: v.roundToDouble()))
            : null,
        semanticValue: (double v) => '${v.round()} milliseconds',
      ),
      if (cfg.roamMethod != JrRoamMethod.ftOverDs)
        Text('Only FT over the DS crosses between the APs.', style: note),
    ] else ...<Widget>[
      const SizedBox(height: AppSpacing.xs),
      ElSlider(
        label: 'Wired LAN round trip (DHCP, gateway, DNS)',
        valueText: ms(cfg.lanRttMs),
        value: cfg.lanRttMs,
        min: kMinLanRttMs,
        max: kMaxLanRttMs,
        divisions: (kMaxLanRttMs - kMinLanRttMs).round(),
        onChanged: (double v) => set(cfg.copyWith(lanRttMs: v.roundToDouble())),
        semanticValue: (double v) => '${v.round()} milliseconds',
      ),
      ElSlider(
        label: 'Address Conflict Detection: wait before the first probe',
        valueText: ms(cfg.acdProbeWaitMs),
        value: cfg.acdProbeWaitMs,
        min: 0,
        max: kMaxAcdProbeWaitMs,
        divisions: (kMaxAcdProbeWaitMs / 50).round(),
        onChanged: cfg.addressCheck == JrAddressCheck.acd
            ? (double v) => set(cfg.copyWith(acdProbeWaitMs: v.roundToDouble()))
            : null,
        semanticValue: (double v) => '${v.round()} milliseconds',
      ),
      ElSlider(
        label: 'Address Conflict Detection: time between probes',
        valueText: ms(cfg.acdSpacingMs),
        value: cfg.acdSpacingMs,
        min: kMinAcdSpacingMs,
        max: kMaxAcdSpacingMs,
        divisions: ((kMaxAcdSpacingMs - kMinAcdSpacingMs) / 50).round(),
        onChanged: cfg.addressCheck == JrAddressCheck.acd
            ? (double v) => set(cfg.copyWith(acdSpacingMs: v.roundToDouble()))
            : null,
        semanticValue: (double v) => '${v.round()} milliseconds',
      ),
      Text(
        cfg.addressCheck == JrAddressCheck.acd
            ? 'RFC 5227 picks these at random (0 to 1 s, then 1 to 2 s) and '
                  'then waits ${ms(kAcdAnnounceWaitMs)} more: 4 to 7 s in all.'
            : 'The two Address Conflict Detection settings apply only when '
                  'the address check is ACD.',
        style: note,
      ),
    ],
  ];
}

/// Presenter panel settings for Join or Roam: the main choices in view, the
/// rest in disclosures, so the panel fits without scrolling.
class JrPresenterSettings extends StatelessWidget {
  const JrPresenterSettings({
    super.key,
    required this.controller,
    this.leading,
  });

  final EapLadderController controller;

  /// Shown first inside the settings card (Join: the mode select).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final EapLadderController c = controller;
    final bool roam = c.mode == LadderMode.roam;
    final bool dot1x = roam
        ? c.jrConfig.roamMethod == JrRoamMethod.full
        : c.jrConfig.effectiveSecurity == JrSecurity.dot1x;
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
              ...jrMainSettings(
                context,
                c,
                compact: true,
                // Join folds the address check to make room for the mode
                // select (spec 43); Roam has no address check.
                groups: const <JrSettingsGroup>{
                  JrSettingsGroup.choice,
                  JrSettingsGroup.radio,
                  JrSettingsGroup.scan,
                },
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: roam
              ? (dot1x ? 'EAP method, PMF and 6 GHz' : 'PMF and 6 GHz')
              : dot1x
              ? 'EAP method, PMF, 6 GHz and address check'
              : 'PMF, 6 GHz and address check',
          children: jrMainSettings(
            context,
            c,
            compact: true,
            groups: const <JrSettingsGroup>{
              JrSettingsGroup.eap,
              JrSettingsGroup.pmf,
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
      ],
    );
  }
}
