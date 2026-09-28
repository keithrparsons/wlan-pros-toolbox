// Controls and explainer for the Wi-Fi Classroom tool "Why a Long Wi-Fi
// Password Matters More on WPA2" (wpa2-password).
//
// Wpa2PasswordControls: the security setting (the one main control), the
// password's length and characters, and the guessing buttons. Neither this
// nor the explainer knows about the stage.
//
// Wpa2PasswordExplainer: the lessons, the source, and links to Association,
// Frame by Frame opened on the WPA2 or the WPA3 frames (reused, not
// redrawn), and to the WPA Security reference.
//
// PRESENTER: the explanatory prose drops (the instructor says it) and the
// key names appear beside each control.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/join_roam.dart' show JrConfig, JrSecurity;
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'join_ladder_screen.dart';
import 'wpa2_password_controller.dart';
import 'wpa2_password_parts.dart';

class Wpa2PasswordControls extends StatelessWidget {
  const Wpa2PasswordControls({super.key, required this.controller});
  final Wpa2PasswordController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Wpa2PasswordController k = controller;
    final WpConfig c = k.config;
    final bool prose = !PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return <Widget>[
      AppToggle<WpSecurity>(
        label: prose ? 'Network security' : 'Network security (1, 2, 3)',
        semanticLabel: 'Network security',
        value: c.security,
        expand: true,
        items: <AppToggleItem<WpSecurity>>[
          for (final WpSecurity s in WpSecurity.values) (s, s.short),
        ],
        onChanged: k.setSecurity,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(switch (c.security) {
        WpSecurity.wpa2 =>
          'WPA2-Personal (WPA: Wi-Fi Protected Access), '
              'the pre-shared key (PSK) method.',
        WpSecurity.wpa3 =>
          'WPA3-Personal: SAE, Simultaneous '
              'Authentication of Equals, replaces the pre-shared key.',
        WpSecurity.transition =>
          'WPA3 transition mode: one network name '
              'and one password for both WPA3 and WPA2-only devices.',
      }, style: small()),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      const WpSectionLabel('The password (the same on every setting)'),
      const SizedBox(height: AppSpacing.xs),
      ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                prose ? 'Length' : 'Length (Up, Down)',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Text(
              '${c.length} characters',
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
      Slider(
        value: c.length.toDouble(),
        min: WpConfig.minLength.toDouble(),
        max: WpConfig.maxLength.toDouble(),
        divisions: WpConfig.maxLength - WpConfig.minLength,
        onChanged: (double v) => k.setLength(v.round()),
        activeColor: colors.primary,
        inactiveColor: colors.disabledFill,
        label: '${c.length}',
        semanticFormatterCallback: (double v) =>
            'Password length, ${v.round()} characters',
      ),
      if (prose) Text('A WPA password is 8 to 63 characters.', style: small()),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Characters',
        style: text.bodyMedium?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xxs),
      AppSelect<WpCharset>(
        value: c.charset,
        semanticLabel: 'Characters the password is drawn from',
        items: <AppSelectItem<WpCharset>>[
          for (final WpCharset s in WpCharset.values) (s, s.label),
        ],
        onChanged: k.setCharset,
      ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      const WpSectionLabel('Guessing'),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          FilledButton.icon(
            onPressed: k.togglePlay,
            icon: Icon(k.playing ? Icons.pause : Icons.play_arrow),
            label: Text(
              '${k.playing ? 'Stop guessing' : 'Keep guessing'}'
              '${prose ? '' : ' (Space)'}',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
            ),
          ),
          OutlinedButton.icon(
            onPressed: k.guessOnce,
            icon: const Icon(Icons.skip_next),
            label: Text('Try one guess${prose ? '' : ' (Right)'}'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
            ),
          ),
          TextButton.icon(
            onPressed: k.reset,
            icon: const Icon(Icons.restart_alt),
            label: Text('Reset${prose ? '' : ' (R)'}'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
            ),
          ),
        ],
      ),
      if (prose) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Changing the security starts the count over: it is a different '
          'network. The guesses are drawn slowly so you can follow them; '
          'no speed is implied.',
          style: small(),
        ),
      ],
    ];
  }
}

// ── Explainer ────────────────────────────────────────────────────────────

class Wpa2PasswordExplainer extends StatelessWidget {
  const Wpa2PasswordExplainer({super.key});

  /// The lessons, in order.
  static const List<String> lessons = <String>[
    '1. On WPA2-Personal, anyone in range who records one association (its '
        '4-way handshake) can check password guesses on their own computer. '
        'Nothing limits the guessing but that computer, and the AP never '
        'sees it. The length of the password is the whole defense.',
    '2. On WPA3-Personal, SAE gives a recording nothing to check a guess '
        'against. Each guess has to be a live exchange with the AP, one try '
        'at a time, and every wrong one is a failed authentication the AP '
        'can notice and limit. A good password still matters.',
    '3. WPA3 transition mode lets WPA2-only devices associate with the same '
        'password. One recorded WPA2 association exposes that password to '
        'offline guessing, exactly as on WPA2. WPA3 devices on the network '
        'still keep forward secrecy: their recorded traffic stays '
        'unreadable even if the password is learned.',
    '4. Every extra character multiplies the number of possible passwords '
        'by the number of characters in play. That is the one lever a WPA2 '
        'network has.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    void openLadder(JrSecurity s) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => JoinLadderScreen(initial: JrConfig(security: s)),
        ),
      );
    }

    return WpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WpSectionLabel('What the password is up against'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            'Possible passwords = characters in play ^ length. No time to '
            'crack is given anywhere in this tool: it depends on the '
            "attacker's hardware, so any figure would be invented.",
            style: small(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Source: Wi-Fi Alliance, WPA3 Security Considerations, November '
            '2019 ("Unlike PSK, SAE is resistant to offline dictionary '
            'attacks"; the transition-mode trade-off; forward secrecy).',
            style: small(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'See the frames themselves in Association, Frame by Frame:',
            style: small(),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => openLadder(JrSecurity.psk),
                icon: const Icon(Icons.open_in_new),
                label: const Text('The WPA2 4-way handshake'),
              ),
              TextButton.icon(
                onPressed: () => openLadder(JrSecurity.sae),
                icon: const Icon(Icons.open_in_new),
                label: const Text('The WPA3 SAE exchange'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.wpaSecurity),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open WPA Security'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
