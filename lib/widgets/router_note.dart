// Plain notes for routers that ignore probes sent to themselves. The traceroute
// case: hop 1 (usually the user's router) never answers but hops beyond it do. Without the note, a user
// reads the silent first hop as a broken router or broken Wi-Fi, which is the
// wrong conclusion: the later answers prove the router forwarded the probes.
// Routers commonly drop or rate-limit ICMP addressed to their own control
// plane while forwarding transit traffic normally. Routers may rate-limit the
// ICMP errors traceroute relies on (RFC 1812 §4.3.2.8 for IPv4, RFC 4443
// §2.4(f) for IPv6), and many also filter them by policy. Idea credited to
// https://octomon.dev/understand.

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

const String firstHopSilentNote =
    'The first hop, usually your router, did not answer, but hops past it '
    'did. Many routers are set to ignore traceroute and ping probes sent to '
    'themselves while still passing your traffic. On its own, this is not a '
    'fault.';

/// [hopAnswered] lists, in hop order starting at hop 1, whether each hop
/// answered at least one probe.
bool firstHopSilentButPathAnswers(List<bool> hopAnswered) =>
    hopAnswered.isNotEmpty &&
    !hopAnswered.first &&
    hopAnswered.skip(1).any((bool answered) => answered);

const String routerIgnoresPingNote =
    'This is your router, and it did not answer. Many routers are set to '
    'ignore pings sent to themselves while still passing your traffic, so on '
    'its own this is not a fault. To check the path past it, run Traceroute.';

/// True when [target] is the device's router and it has answered none of at
/// least 3 pings. One or two lost pings are too few to call it a pattern.
bool routerSilentToPing({
  required String target,
  required String? gatewayIp,
  required int sent,
  required int received,
}) =>
    gatewayIp != null &&
    target.trim() == gatewayIp &&
    sent >= 3 &&
    received == 0;

/// Informational styling on purpose: this is reassurance, not an alarm.
class RouterNote extends StatelessWidget {
  const RouterNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
