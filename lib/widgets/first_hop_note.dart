// A plain note for the common traceroute pattern where hop 1 (usually the
// user's router) never answers but hops beyond it do. Without the note, a user
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

/// Informational styling on purpose: this is reassurance, not an alarm.
class FirstHopNote extends StatelessWidget {
  const FirstHopNote({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              firstHopSilentNote,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
