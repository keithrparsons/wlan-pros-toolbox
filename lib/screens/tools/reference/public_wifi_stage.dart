// Public Wi-Fi lesson: the interactive block. Three pieces, kept apart the way
// the Classroom simulators keep them:
//   - PublicWifiController  the one input (network type), a ChangeNotifier
//   - PublicWifiControls    the network-type control
//   - PublicWifiStage       the trip drawing and what the bystander can see
// The model is lib/services/wifi_lab/public_wifi_model.dart.
//
// States (SOP-007 §5): no loading, empty or error state is reachable: the
// input is a bounded choice and the model is pure arithmetic over enums. The
// WPA2 / WPA3 choice is DISABLED unless Password is picked, and says why in
// words. Every control is a design-system AppToggle / AppSelect with the §8.3
// focus ring.
//
// COLOR. What the bystander gets from each kind of traffic is a verdict
// (GL-003 §8.15 case 2), so it takes the §8.13 status hues, always beside the
// verdict word in a StatusChip: Can read it (danger), Can see it (warning),
// Sealed (success). Nothing rests on color alone.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/public_wifi_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/status_chip.dart';
import '../labeled_field.dart';
import 'lesson_parts.dart';

/// The lesson's one input. Starts on Open, the case most people picture.
class PublicWifiController extends ChangeNotifier {
  PwKind _kind = PwKind.open;
  PwPassword _password = PwPassword.wpa2;

  PwKind get kind => _kind;
  PwPassword get password => _password;
  PwNetwork get network => pwNetworkFor(_kind, _password);

  set kind(PwKind v) {
    if (v == _kind) return;
    _kind = v;
    notifyListeners();
  }

  set password(PwPassword v) {
    if (v == _password) return;
    _password = v;
    notifyListeners();
  }
}

/// The display name of each network type, as the lesson spells it.
String pwNetworkName(PwNetwork n) => switch (n) {
  PwNetwork.open => 'Open',
  PwNetwork.enhancedOpen => 'Enhanced Open',
  PwNetwork.wpa2Personal => 'WPA2-Personal',
  PwNetwork.wpa3Personal => 'WPA3-Personal',
};

// ─────────────────────────────────────────────────────────────────────────────
// Controls.
// ─────────────────────────────────────────────────────────────────────────────

/// Network type, then (for Password) WPA2 or WPA3. A three-segment toggle
/// where it fits; below that width the same three choices as a select, so
/// "Enhanced Open" never truncates.
class PublicWifiControls extends StatelessWidget {
  const PublicWifiControls({super.key, required this.controller});

  final PublicWifiController controller;

  static const List<(PwKind, String)> _kinds = <(PwKind, String)>[
    (PwKind.open, 'Open'),
    (PwKind.enhancedOpen, 'Enhanced Open'),
    (PwKind.password, 'Password'),
  ];

  /// The narrowest width at which the three segments show whole.
  static const double toggleMinWidth = 440;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final bool password = controller.kind == PwKind.password;
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Widget kind = c.maxWidth >= toggleMinWidth
                ? AppToggle<PwKind>(
                    label: 'Network type',
                    value: controller.kind,
                    items: _kinds,
                    expand: true,
                    onChanged: (PwKind v) => controller.kind = v,
                  )
                : LabeledField(
                    label: 'Network type',
                    field: AppSelect<PwKind>(
                      semanticLabel: 'Network type',
                      value: controller.kind,
                      items: _kinds,
                      onChanged: (PwKind v) => controller.kind = v,
                    ),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                kind,
                const SizedBox(height: AppSpacing.sm),
                AppToggle<PwPassword>(
                  label: 'Password security',
                  value: controller.password,
                  enabled: password,
                  expand: true,
                  items: const <(PwPassword, String)>[
                    (PwPassword.wpa2, 'WPA2'),
                    (PwPassword.wpa3, 'WPA3'),
                  ],
                  onChanged: (PwPassword v) => controller.password = v,
                ),
                if (!password) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Pick Password to compare WPA2 and WPA3.',
                    style: lessonBody(
                      context,
                      small: true,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage.
// ─────────────────────────────────────────────────────────────────────────────

/// The trip drawing, the network's three facts, and what the person next to
/// you can see, for the controller's network.
class PublicWifiStage extends StatelessWidget {
  const PublicWifiStage({super.key, required this.controller});

  final PublicWifiController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final PwNetwork n = controller.network;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _TripDrawing(network: n),
            const SizedBox(height: AppSpacing.sm),
            _Facts(network: n),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: LessonRich(pwWhy(n), style: lessonBody(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            LessonSub('What the person next to you can see on ${pwNetworkName(n)}'),
            const SizedBox(height: AppSpacing.xs),
            for (final PwTraffic t in PwTraffic.values) ...<Widget>[
              _TrafficRow(network: n, traffic: t),
              if (t != PwTraffic.values.last)
                const SizedBox(height: AppSpacing.xs),
            ],
          ],
        );
      },
    );
  }
}

/// One sentence on why the network behaves as it does.
String pwWhy(PwNetwork n) => switch (n) {
  PwNetwork.open =>
    '**Open.** Wi-Fi encrypts nothing on the air. HTTPS still seals what is '
        'inside secure sites, so what shows is the site names and anything '
        'sent without encryption.',
  PwNetwork.enhancedOpen =>
    '**Enhanced Open.** Still no password, but each device gets its own key '
        'as it joins (Opportunistic Wireless Encryption, OWE). A listener gets '
        'only scrambled frames. Your network list still shows no lock.',
  PwNetwork.wpa2Personal =>
    "**WPA2-Personal.** Every device's key comes from the one shared "
        'password. A stranger without it reads nothing. The person next to '
        'you has it, and if they record your device joining, they can work '
        'out your key and read the air as if it were Open.',
  PwNetwork.wpa3Personal =>
    '**WPA3-Personal.** Each device gets its own key through a password '
        'exchange called SAE (Simultaneous Authentication of Equals). Knowing '
        'the password does not let someone who only listens work out yours.',
};

/// The verdict word and chip kind for an exposure.
(String, StatusChipKind) pwVerdict(PwExposure e) => switch (e) {
  PwExposure.readable => ('Can read it', StatusChipKind.issue),
  PwExposure.visible => ('Can see it', StatusChipKind.headsUp),
  PwExposure.sealed => ('Sealed', StatusChipKind.good),
};

/// The row title for a kind of traffic.
String pwTrafficTitle(PwTraffic t) => switch (t) {
  PwTraffic.presence => 'That your device is here',
  PwTraffic.siteNames => 'Which sites you visit',
  PwTraffic.httpsContent => 'What you read and type on a secure site',
  PwTraffic.unencrypted => 'Anything sent without encryption',
};

/// The row's explanation, for this traffic on this network.
String pwTrafficDetail(PwNetwork n, PwTraffic t) {
  final PwExposure e = pwExposure(n, t);
  switch (t) {
    case PwTraffic.presence:
      return 'Every Wi-Fi frame starts with a header that is never encrypted: '
          "the device's hardware (MAC, media access control) address, and how "
          'much it sends and when.';
    case PwTraffic.httpsContent:
      return 'Pages, passwords, card numbers and messages on HTTPS sites are '
          'sealed from your device all the way to the website, on every '
          'network.';
    case PwTraffic.siteNames:
      return e == PwExposure.sealed
          ? 'The name lookups happen inside the Wi-Fi encryption, so a '
                'listener gets only scrambled frames.'
          : 'Your device looks each name up (DNS, the Domain Name System) and '
                'tells each secure site which name it wants (SNI, Server Name '
                'Indication). Both travel outside the HTTPS seal.';
    case PwTraffic.unencrypted:
      if (e == PwExposure.sealed) {
        return 'Inside the Wi-Fi encryption, so a listener gets only '
            'scrambled frames.';
      }
      return n == PwNetwork.open
          ? 'An app or page that skips HTTPS sends plain text, and an Open '
                'network adds no encryption of its own.'
          : 'An app or page that skips HTTPS sends plain text, and the person '
                "next to you can undo this network's encryption.";
  }
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.network, required this.traffic});

  final PwNetwork network;
  final PwTraffic traffic;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final (String word, StatusChipKind kind) = pwVerdict(
      pwExposure(network, traffic),
    );
    final String title = pwTrafficTitle(traffic);
    final String detail = pwTrafficDetail(network, traffic);
    return Semantics(
      label: '$title: $word. $detail',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(left: BorderSide(color: kind.hue(colors), width: 3)),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  style: (t.titleSmall ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                StatusChip(kind: kind, word: word),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              detail,
              style: lessonBody(context, small: true, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password, lock icon, and key: the three things that differ between the
/// types, each in words.
class _Facts extends StatelessWidget {
  const _Facts({required this.network});

  final PwNetwork network;

  @override
  Widget build(BuildContext context) {
    final String key = !pwAirEncrypted(network)
        ? 'None'
        : pwOwnKey(network)
        ? 'Your own'
        : 'From the shared password';
    final List<(String, String)> facts = <(String, String)>[
      ('Password to join', pwNeedsPassword(network) ? 'Yes' : 'No'),
      ('Lock in the network list', pwShowsLock(network) ? 'Yes' : 'No'),
      ('Wi-Fi key', key),
    ];
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final (String label, String value) in facts)
          Semantics(
            label: '$label: $value',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: colors.border),
              ),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '$label  ',
                      style: TextStyle(color: colors.textTertiary),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                style: t.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

/// Your device, the access point and the website in a row, with the two seals
/// drawn under the stretch each one covers: Wi-Fi encryption from the device
/// to the AP, HTTPS from the device to the website. The bystander sits under
/// the air.
class _TripDrawing extends StatelessWidget {
  const _TripDrawing({required this.network});

  final PwNetwork network;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle small = (t.bodySmall ?? const TextStyle()).copyWith(
      color: colors.textSecondary,
      height: 1.3,
    );

    Widget node(String label) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface3,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: small.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    Widget gap(String label) => Center(
      child: Text(label, textAlign: TextAlign.center, style: small),
    );

    Widget band({
      required String label,
      required Color edge,
      required Color fill,
      required IconData icon,
    }) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge, width: 2),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: edge),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              label,
              style: small.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );

    final bool air = pwAirEncrypted(network);
    final bool own = pwOwnKey(network);
    final Widget wifiBand = !air
        ? band(
            label: 'No Wi-Fi encryption on the air',
            edge: colors.borderStrong,
            fill: colors.surface2,
            icon: Icons.lock_open,
          )
        : own
        ? band(
            label: 'Wi-Fi encryption, a key of your own',
            edge: colors.statusSuccess,
            fill: colors.statusSuccessFill,
            icon: Icons.lock,
          )
        : band(
            label: 'Wi-Fi encryption, key from the shared password',
            edge: colors.statusWarning,
            fill: colors.statusWarningFill,
            icon: Icons.key,
          );

    final String spoken =
        'Drawing. Your device talks over the air to the access point, which '
        'reaches the website over the internet. HTTPS seals secure-site '
        'content from your device to the website. '
        '${!air ? 'There is no Wi-Fi encryption on the air.' : own ? 'Wi-Fi encryption covers the air with a key of your own.' : 'Wi-Fi encryption covers the air with a key from the shared password.'} '
        'The person next to you listens to the air.';

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 4, child: node('Your device')),
                  Expanded(flex: 3, child: gap('air')),
                  Expanded(flex: 4, child: node('Access point (AP)')),
                  Expanded(flex: 3, child: gap('internet')),
                  Expanded(flex: 4, child: node('Website')),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(flex: 11, child: wifiBand),
                const Spacer(flex: 7),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            band(
              label: 'HTTPS seal, your device to the website',
              edge: colors.statusSuccess,
              fill: colors.statusSuccessFill,
              icon: Icons.https,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                const Spacer(flex: 2),
                Expanded(
                  flex: 9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.hearing, size: 16, color: colors.textSecondary),
                      const SizedBox(width: AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          'The person next to you listens here',
                          style: small,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 7),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
