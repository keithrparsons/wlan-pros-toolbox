// WPA Security — read-only reference of Wi-Fi security modes and the advanced
// features that distinguish them. Data ported verbatim from the rf-tools-pwa
// `wpa` tool (WPA_MODES + WPA_FEATURES in www/app.js).
//
// This is a static reference table: there is no input, no fetch, no async work.
// The only "state" is success — the bundled data always renders. There is no
// loading / error / empty / disabled state because nothing is loaded, can fail,
// can be empty, or can be toggled. (SOP-007 §5: states are handled by being
// structurally impossible here, not skipped.) Fully offline, every platform.
//
// Matches the port_reference_screen idiom: Scaffold + AppBar (toolbarHeight 64),
// SafeArea(top: false), LayoutBuilder breakpoint at 720, ConstrainedBox capped
// at calculatorMaxWidth, SingleChildScrollView of cards, tokens only.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// One row of the security-modes table. Field data verbatim from PWA
/// `WPA_MODES`; the verdict color is mapped to a GL-003 §8.13 status token.
///
/// `statusColor` is one of the four §8.13 semantic status tokens, chosen by the
/// verdict's *meaning* (danger / warning / success / info) rather than reproducing
/// the PWA's raw Material hues — those failed WCAG 2.2 SC 1.4.11 (3:1 non-text)
/// as chip borders on the dark #222222 card (Vera F-01). All four §8.13 tokens
/// clear 3:1 on surface1 with margin. The status word always accompanies the
/// color (never color-only), satisfying SC 1.4.1.
@immutable
class WpaMode {
  const WpaMode({
    required this.mode,
    required this.category,
    required this.encryption,
    required this.keyMethod,
    required this.pmf,
    required this.statusTone,
    required this.status,
  });

  /// Display name, e.g. "WPA3-Personal".
  final String mode;

  /// Grouping, e.g. "Personal" / "Enterprise" / "Legacy" / "Open".
  final String category;

  /// Cipher / encryption suite.
  final String encryption;

  /// Key-establishment method (PSK, SAE, 802.1X + EAP, ...).
  final String keyMethod;

  /// Protected Management Frames support: "No" / "Opt" / "Req".
  final String pmf;

  /// Verdict tone for the status word. Resolved to a §8.13/§8.20.1 status color
  /// at render via [statusToneColor]; never a baked Color (theme-dependent).
  final StatusTone statusTone;

  /// Deployment verdict, e.g. "Recommended" / "Do not deploy".
  final String status;
}

/// One row of the advanced-features table. Verbatim from PWA `WPA_FEATURES`.
@immutable
class WpaFeature {
  const WpaFeature({
    required this.feature,
    required this.appliesTo,
    required this.description,
  });

  /// Feature name, e.g. "SAE (Simultaneous Authentication of Equals)".
  final String feature;

  /// Which modes the feature applies to.
  final String appliesTo;

  /// What the feature does.
  final String description;
}

class WpaSecurityScreen extends StatelessWidget {
  const WpaSecurityScreen({super.key});

  /// Security modes, in PWA order. Public-static for testing.
  ///
  /// Status colors are the GL-003 §8.13 semantic tokens, mapped from each row's
  /// deployment verdict (see the per-row comments below).
  static const List<WpaMode> modes = <WpaMode>[
    WpaMode(
      mode: 'WEP',
      category: 'Legacy',
      encryption: 'RC4 (broken)',
      keyMethod: 'Static key',
      pmf: 'No',
      statusTone: StatusTone.danger,
      status: 'Do not deploy',
    ),
    WpaMode(
      mode: 'WPA (WPA1)',
      category: 'Legacy',
      encryption: 'TKIP',
      keyMethod: 'PSK / 802.1X',
      pmf: 'No',
      statusTone: StatusTone.danger,
      status: 'Deprecated',
    ),
    WpaMode(
      mode: 'WPA2-Personal',
      category: 'Personal',
      encryption: 'AES-CCMP (128-bit)',
      keyMethod: 'PSK passphrase',
      pmf: 'Opt',
      statusTone: StatusTone.warning,
      status: 'Acceptable',
    ),
    WpaMode(
      mode: 'WPA3-Personal',
      category: 'Personal',
      encryption: 'AES-CCMP (128-bit)',
      keyMethod: 'SAE',
      pmf: 'Req',
      statusTone: StatusTone.success,
      status: 'Recommended',
    ),
    WpaMode(
      mode: 'Enhanced Open',
      category: 'Open',
      encryption: 'OWE (AES-CCMP)',
      keyMethod: 'None (auto)',
      pmf: 'Req',
      statusTone: StatusTone.info,
      status: 'Open networks',
    ),
    WpaMode(
      mode: 'WPA2-Enterprise',
      category: 'Enterprise',
      encryption: 'AES-CCMP (128-bit)',
      keyMethod: '802.1X + EAP',
      pmf: 'Opt',
      statusTone: StatusTone.info,
      status: 'Enterprise std',
    ),
    WpaMode(
      mode: 'WPA3-Enterprise',
      category: 'Enterprise',
      encryption: 'GCMP-256 (192-bit)',
      keyMethod: '802.1X + EAP',
      pmf: 'Req',
      statusTone: StatusTone.success,
      status: 'Recommended',
    ),
  ];

  /// Advanced features, in PWA order. Public-static for testing.
  static const List<WpaFeature> features = <WpaFeature>[
    WpaFeature(
      feature: 'SAE (Simultaneous Authentication of Equals)',
      appliesTo: 'WPA3-Personal',
      description:
          'Replaces PSK 4-way handshake. Forward secrecy. Resistant '
          'to offline dictionary attacks even if the passphrase is short.',
    ),
    WpaFeature(
      feature: 'PMF — Protected Management Frames',
      appliesTo: 'Optional: WPA2 · Required: WPA3',
      description:
          'Encrypts deauth and disassociation frames (802.11w). '
          'Prevents deauth flood attacks.',
    ),
    WpaFeature(
      feature: 'OWE — Opportunistic Wireless Encryption',
      appliesTo: 'Enhanced Open only',
      description:
          'Encrypts open-network sessions without a password. No '
          'authentication, but eavesdropping is prevented.',
    ),
    WpaFeature(
      feature: 'Forward Secrecy',
      appliesTo: 'WPA3-Personal (SAE), WPA3-Enterprise',
      description:
          'Session keys are ephemeral. Captured traffic cannot be '
          'decrypted retroactively even if the passphrase is later compromised.',
    ),
    WpaFeature(
      feature: '192-bit Security Mode',
      appliesTo: 'WPA3-Enterprise only',
      description:
          'GCMP-256 + HMAC-SHA-384 + ECDH/ECDSA-384. Required for '
          'government and classified deployments.',
    ),
    WpaFeature(
      feature: 'WPA3 mandatory on 6 GHz',
      appliesTo: 'All Wi-Fi 6E / Wi-Fi 7',
      description:
          '6 GHz band requires WPA3 or OWE. WPA2 and older protocols '
          'are not permitted on 6 GHz.',
    ),
    WpaFeature(
      feature: '802.1X / RADIUS roles',
      appliesTo: 'WPA2/WPA3-Enterprise',
      description:
          'Supplicant (client) → Authenticator (AP) → Authentication '
          'Server (RADIUS). EAP tunnel carries credential exchange.',
    ),
  ];

  static const String _intro =
      'WPA security modes, encryption standards, and '
      'advanced feature reference for enterprise WLAN design.';

  /// Expand the terse PMF token for the clipboard, matching the on-screen
  /// long form (the visible value uses _ModeRow._pmfLong, kept in sync here).
  static String _pmfLong(String pmf) {
    switch (pmf) {
      case 'No':
        return 'Not supported';
      case 'Opt':
        return 'Optional';
      case 'Req':
        return 'Required';
      default:
        return pmf;
    }
  }

  /// §8.16 copy payload — both reference blocks as TSV. Static data, so always
  /// enabled. Two sections (subtitle + header + rows): the security modes and
  /// the advanced features. Each mode's deployment verdict (the §8.13
  /// status-hued chip on-screen) is carried as the worded Status cell — the
  /// status word is the clipboard carrier of the color (§8.16 verdict-word
  /// rule).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('WPA Security')
      ..writeln()
      ..writeln('Security modes')
      ..writeln(
        <String>[
          'Mode',
          'Category',
          'Encryption',
          'Key method',
          'PMF',
          'Status',
        ].join(tab),
      );
    for (final WpaMode m in modes) {
      buf.writeln(
        <String>[
          m.mode,
          m.category,
          m.encryption,
          m.keyMethod,
          _pmfLong(m.pmf),
          m.status,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Advanced features')
      ..writeln(<String>['Feature', 'Applies to', 'Description'].join(tab));
    for (final WpaFeature f in features) {
      buf.writeln(<String>[f.feature, f.appliesTo, f.description].join(tab));
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WPA Security'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(
                    toolId: 'wpa-security',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wpa-security'))
                    const SizedBox(height: AppSpacing.md),
                  _IntroText(text: _intro),
                  const SizedBox(height: AppSpacing.sm),
                  _SectionCard(
                    title: 'Security modes',
                    children: <Widget>[
                      for (final WpaMode m in modes) _ModeRow(mode: m),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SectionCard(
                    title: 'Advanced features',
                    children: <Widget>[
                      for (final WpaFeature f in features)
                        _FeatureRow(feature: f),
                    ],
                  ),
                  ToolHelpFooter(toolId: 'wpa-security'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IntroText extends StatelessWidget {
  const _IntroText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.labelMedium?.copyWith(color: colors.textSecondary),
    );
  }
}

/// A titled card wrapping a list of data rows, separated by hairline dividers.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(height: 1, thickness: 1, color: colors.border),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: t.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows,
        ],
      ),
    );
  }
}

/// One security-mode entry: name + category header, a verdict chip, then the
/// encryption / key-method / PMF attribute lines.
class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.mode});

  final WpaMode mode;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          '${mode.mode}, ${mode.category}. Encryption '
          '${mode.encryption}. Key method ${mode.keyMethod}. '
          'Protected Management Frames ${_pmfLong(mode.pmf)}. '
          'Status ${mode.status}.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        mode.mode,
                        style: t.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        mode.category,
                        style: t.labelSmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatusChip(
                  label: mode.status,
                  color: colors.statusToneColor(mode.statusTone),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _Attr(label: 'Encryption', value: mode.encryption),
            _Attr(label: 'Key method', value: mode.keyMethod),
            _Attr(label: 'PMF', value: _pmfLong(mode.pmf)),
          ],
        ),
      ),
    );
  }

  // Expand the terse PMF token for both the visible value and screen readers.
  static String _pmfLong(String pmf) {
    switch (pmf) {
      case 'No':
        return 'Not supported';
      case 'Opt':
        return 'Optional';
      case 'Req':
        return 'Required';
      default:
        return pmf;
    }
  }
}

/// A label · value attribute line shared by the mode rows.
class _Attr extends StatelessWidget {
  const _Attr({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: t.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: t.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verdict chip. The 1px border takes the GL-003 §8.13 status token; a subtle
/// tint band uses the same token at 12% alpha. The verdict word renders in
/// textPrimary, so color is never the sole carrier of meaning (SC 1.4.1), and
/// the §8.13 border clears SC 1.4.11 (3:1 non-text) on surface1.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: t.labelMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One advanced-feature entry: name, applies-to line, then the description.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final WpaFeature feature;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          '${feature.feature}. Applies to ${feature.appliesTo}. '
          '${feature.description}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              feature.feature,
              style: t.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              feature.appliesTo,
              style: t.labelSmall?.copyWith(color: colors.textAccent),
            ),
            const SizedBox(height: 2),
            Text(
              feature.description,
              style: t.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
