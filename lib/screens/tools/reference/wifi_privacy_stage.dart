// Wi-Fi privacy myths: the two interactive blocks. Kept apart the way the
// Classroom simulators keep them:
//   - WifiPrivacyController   both inputs, a ChangeNotifier
//   - AddressControls / AddressStage       part 1, the private address
//   - HiddenNameControls / HiddenNameStage part 2, the hidden network name
// The model is lib/services/wifi_lab/wifi_privacy_model.dart.
//
// States (SOP-007 §5): no loading, empty or error state is reachable (bounded
// choices, pure model). Nothing is disabled. Interactive: two AppToggles, each
// with the §8.3 focus ring and Left/Right arrow keys.
//
// COLOR. Whether a router can match the phone is a privacy verdict (GL-003
// §8.15 case 2): Can be matched (warning) or Can't be matched (success), always
// as words in a StatusChip. The filter row is information, not a verdict, so it
// carries the info chip. Nothing rests on color alone.
//
// NO OS NAMES in anything on screen (Keith's clean-room rule): the device is
// "your phone", and the published rotation interval is attributed to "one
// phone maker". The citation lives in the Sources section and in help.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/wifi_privacy_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/status_chip.dart';
import 'lesson_parts.dart';

/// Both of the lesson's inputs. Starts on Off and on a shown name: the
/// settings the myths assume.
class WifiPrivacyController extends ChangeNotifier {
  PmAddressMode _mode = PmAddressMode.off;
  bool _hidden = false;

  PmAddressMode get mode => _mode;
  bool get hidden => _hidden;

  set mode(PmAddressMode v) {
    if (v == _mode) return;
    _mode = v;
    notifyListeners();
  }

  set hidden(bool v) {
    if (v == _hidden) return;
    _hidden = v;
    notifyListeners();
  }
}

String pmModeName(PmAddressMode m) => switch (m) {
  PmAddressMode.off => 'Off',
  PmAddressMode.fixed => 'Fixed',
  PmAddressMode.rotating => 'Rotating',
};

/// One sentence per setting, shown under the control.
String pmModeWhy(PmAddressMode m) => switch (m) {
  PmAddressMode.off =>
    '**Off.** Your phone uses its hardware address on every network, every '
        'time. Any two networks that compare notes can tell it is the same '
        'phone.',
  PmAddressMode.fixed =>
    '**Fixed.** Your phone makes up a different address for each network and '
        'keeps it for that network. Your home router and your usual cafe each '
        'see a steady address, and the two do not match.',
  PmAddressMode.rotating =>
    '**Rotating.** A different address for each network, and a new one on a '
        'schedule. One phone maker publishes the schedule as every two weeks, '
        'so a month later the cafe sees a stranger.',
};

// ─────────────────────────────────────────────────────────────────────────────
// Part 1.
// ─────────────────────────────────────────────────────────────────────────────

class AddressControls extends StatelessWidget {
  const AddressControls({super.key, required this.controller});

  final WifiPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => AppToggle<PmAddressMode>(
        label: 'Private Wi-Fi address',
        value: controller.mode,
        expand: true,
        items: <(PmAddressMode, String)>[
          for (final PmAddressMode m in PmAddressMode.values) (m, pmModeName(m)),
        ],
        onChanged: (PmAddressMode v) => controller.mode = v,
      ),
    );
  }
}

class AddressStage extends StatelessWidget {
  const AddressStage({super.key, required this.controller});

  final WifiPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final PmAddressMode m = controller.mode;
        final bool acrossNetworks = pmLinkedAcrossNetworks(m);
        final bool acrossVisits = pmLinkedAcrossVisits(m);
        final bool admitted = pmFilterAdmitsSecondVisit(m);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              child: LessonRich(pmModeWhy(m), style: lessonBody(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Scene(
              title: 'Two routers, the same day',
              rows: <(String, String)>[
                ('Your home router', pmFormat(pmRecorded(m, PmNetwork.home, 0))),
                ('The cafe router', pmFormat(pmRecorded(m, PmNetwork.cafe, 0))),
              ],
              verdict: acrossNetworks ? "Can be matched" : "Can't be matched",
              kind: acrossNetworks
                  ? StatusChipKind.headsUp
                  : StatusChipKind.good,
              note: acrossNetworks
                  ? 'The same address at home and at the cafe.'
                  : 'Two different addresses. Nothing in them links the two '
                        'networks.',
            ),
            const SizedBox(height: AppSpacing.xs),
            _Scene(
              title: 'One cafe, two visits a month apart',
              rows: <(String, String)>[
                (
                  'First visit',
                  pmFormat(pmRecorded(m, PmNetwork.cafe, 0)),
                ),
                (
                  'A month later',
                  pmFormat(pmRecorded(m, PmNetwork.cafe, kVisitGapDays)),
                ),
              ],
              verdict: acrossVisits ? 'Can be matched' : "Can't be matched",
              kind: acrossVisits ? StatusChipKind.headsUp : StatusChipKind.good,
              note: acrossVisits
                  ? 'The cafe sees the same address and knows the phone came '
                        'back.'
                  : 'The cafe sees a new address and cannot tell it is the '
                        'same phone.',
            ),
            const SizedBox(height: AppSpacing.xs),
            _Scene(
              title: "The cafe's MAC filter, set on the first visit",
              rows: const <(String, String)>[],
              verdict: admitted ? 'Let in' : 'Turned away',
              kind: StatusChipKind.info,
              note: admitted
                  ? 'The address on the list matches, so the phone is let in '
                        'a month later. So is anyone who copies that address '
                        'off the air.'
                  : 'The address has rotated, so the filter no longer '
                        'recognizes the phone. Rotating and MAC filtering do '
                        'not mix.',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Addresses are illustrative. The hardware address is from the '
              'range set aside for documentation, so it belongs to no real '
              'device.',
              style: lessonBody(
                context,
                small: true,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A titled panel: labelled address rows, a verdict chip, and a note.
class _Scene extends StatelessWidget {
  const _Scene({
    required this.title,
    required this.rows,
    required this.verdict,
    required this.kind,
    required this.note,
  });

  final String title;
  final List<(String, String)> rows;
  final String verdict;
  final StatusChipKind kind;
  final String note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle mono =
        (Theme.of(context).extension<AppMonoText>()?.inlineCode ??
                const TextStyle(fontFamily: 'DM Mono'))
            .copyWith(color: colors.textPrimary, fontSize: t.bodyMedium?.fontSize);
    final String spoken = <String>[
      '$title: $verdict.',
      for (final (String who, String addr) in rows) '$who records $addr.',
      note,
    ].join(' ');
    return Semantics(
      label: spoken,
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
                StatusChip(kind: kind, word: verdict),
              ],
            ),
            for (final (String who, String addr) in rows)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 128,
                      child: Text(
                        who,
                        style: lessonBody(
                          context,
                          small: true,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Text(addr, style: mono),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: lessonBody(context, small: true, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Part 2.
// ─────────────────────────────────────────────────────────────────────────────

class HiddenNameControls extends StatelessWidget {
  const HiddenNameControls({super.key, required this.controller});

  final WifiPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => AppToggle<bool>(
        label: 'Hide the network name',
        value: controller.hidden,
        expand: true,
        items: const <(bool, String)>[(false, 'Off'), (true, 'On')],
        onChanged: (bool v) => controller.hidden = v,
      ),
    );
  }
}

class HiddenNameStage extends StatelessWidget {
  const HiddenNameStage({super.key, required this.controller});

  final WifiPrivacyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final bool hidden = controller.hidden;
        final String beacon = pmBeaconName(hidden);
        final String? probe = pmProbeName(hidden);
        final AppColorScheme colors = context.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              child: LessonRich(
                hidden
                    ? '**Hidden.** The access point (AP) stops putting the '
                          'name in its beacons. So your phone has to call out '
                          '"Is $kHomeNetworkName here?" to find it, at home and '
                          'everywhere else it goes.'
                    : '**Shown.** The AP announces the name in its beacons, '
                          'so your phone can listen for it. When your phone '
                          'asks what is nearby, it asks without naming '
                          'anything.',
                style: lessonBody(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _NameCard(
              title: "The AP's beacons, at home",
              line: beacon.isEmpty
                  ? 'Network name: (blank)'
                  : 'Network name: $beacon',
              kind: StatusChipKind.info,
              titleWidth: null,
              verdict: beacon.isEmpty ? 'Name left out' : 'Name announced',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Your phone's probe requests, as it travels",
              style: (Theme.of(context).textTheme.titleSmall ??
                      const TextStyle())
                  .copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final String place in kPmPlaces) ...<Widget>[
              _NameCard(
                title: place,
                line: probe == null
                    ? '"Any networks here?"'
                    : '"Is $probe here?"',
                kind: probe == null
                    ? StatusChipKind.good
                    : StatusChipKind.headsUp,
                verdict: probe == null ? 'Names nothing' : 'Names your network',
              ),
              if (place != kPmPlaces.last) const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Either way, the name crosses the air in the clear each time a '
              'device joins, so anyone listening then learns it. '
              '$kHomeNetworkName is an illustrative name.',
              style: lessonBody(
                context,
                small: true,
                color: colors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({
    required this.title,
    required this.line,
    required this.kind,
    required this.verdict,
    this.titleWidth = 72,
  });

  final String title;
  final String line;

  /// Width that lines the place names up in a column; null for a free title.
  final double? titleWidth;
  final StatusChipKind kind;
  final String verdict;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle mono =
        (Theme.of(context).extension<AppMonoText>()?.inlineCode ??
                const TextStyle(fontFamily: 'DM Mono'))
            .copyWith(color: colors.textPrimary, fontSize: t.bodyMedium?.fontSize);
    return Semantics(
      label: '$title: $verdict. $line',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(left: BorderSide(color: kind.hue(colors), width: 3)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: titleWidth,
              child: Text(
                title,
                style: (t.titleSmall ?? const TextStyle()).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(line, style: mono),
            StatusChip(kind: kind, word: verdict),
          ],
        ),
      ),
    );
  }
}
