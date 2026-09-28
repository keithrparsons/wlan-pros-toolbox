// LargeScreenGate: the Wi-Fi Classroom's "designed for a larger screen" notice.
//
// Keith, 2026-09-26: "Go with the large-screen notice and Continue anyway."
// As it binds (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/README.md,
// "Large screens first"): tablets and computers are the target. Below the
// presenter threshold a Lab tool first shows this notice; Continue anyway
// shows the tool exactly as it is today.
//
// APPLIED CENTRALLY. [gateWifiLabRoutes] wraps every AppRouter route whose
// catalog entry is a Wi-Fi Classroom SIMULATOR: in the 'wifi-classroom'
// category, on one of the [kWifiClassroomSimulatorSubgroups] shelves. A new
// simulator is gated the moment it is added to the catalog and the route
// table. No screen imports this file.
//
// RE-KEYED 2026-09-26. It keyed on a 'Wi-Fi Classroom' subgroup of Calculators
// & Tools until the simulators became their own home section. The same day the
// Classroom took in the WLAN Pros lessons and handouts, which must NOT be
// gated, so the key is category AND simulator shelf. A test holds every
// Classroom shelf to one of the two sets.
//
// THRESHOLD. The same one the Present button uses ([presenterAvailable]:
// at least [kPresentMinWidth] wide and [kPresentMinHeight] tall). A window at
// or above it never sees the notice and never pays an extra tap.
//
// MEMORY. Continue anyway is remembered for the rest of the app session
// ([largeScreenNoticeDismissed], in memory only, never persisted), so a student
// is asked once, not on every tool. Once a gate has shown its tool it keeps
// showing it: a window shrunk or a phone rotated below the threshold never
// swaps a running simulator back to the notice (that would also throw away
// the tool's state). A notice on screen gives way to the tool by itself if the
// window grows past the threshold.

import 'package:flutter/material.dart';

import '../../data/tool_catalog.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import 'present_button.dart' show presenterAvailable;

/// The catalog category that holds the simulators.
const String kWifiClassroomCategoryId = 'wifi-classroom';

/// The Wi-Fi Classroom shelves whose tools are gated: the simulators.
///
/// The Classroom also holds Guided Lessons and Course Handouts (Keith,
/// 2026-09-26), which read fine on a phone and are NOT gated
/// ([kWifiClassroomUngatedSubgroups]). A test asserts the two sets together
/// cover every Classroom shelf, so a new shelf has to be classified before the
/// suite passes and cannot be ungated by accident.
const Set<String> kWifiClassroomSimulatorSubgroups = <String>{
  'RF and Propagation',
  'Signals and PHY',
  'Airtime and Access',
  'Network Design and Security',
};

/// The Wi-Fi Classroom shelves that stay ungated.
const Set<String> kWifiClassroomUngatedSubgroups = <String>{
  'Guided Lessons',
  'Course Handouts',
};

/// Notice headline.
const String kLargeScreenNoticeTitle = 'Best on a larger screen';

/// Notice body.
const String kLargeScreenNoticeBody =
    'The Wireless Classroom is designed for a tablet or computer screen. On a phone '
    'some views will be cramped.';

/// Primary action: show the tool anyway.
const String kLargeScreenContinueLabel = 'Continue anyway';

/// Secondary action: leave the tool.
const String kLargeScreenBackLabel = 'Go back';

/// True once the user has chosen Continue anyway in this app session.
/// In memory only: a fresh launch asks again.
final ValueNotifier<bool> largeScreenNoticeDismissed = ValueNotifier<bool>(
  false,
);

/// Clears the session memory so each test starts from a fresh launch.
@visibleForTesting
void resetLargeScreenNoticeForTest() {
  largeScreenNoticeDismissed.value = false;
}

/// Every Wi-Fi Classroom simulator: a tool in the 'wifi-classroom' category on
/// one of the [kWifiClassroomSimulatorSubgroups] shelves.
Iterable<ToolEntry> wifiLabTools([List<ToolCategory>? catalog]) sync* {
  for (final ToolCategory c in catalog ?? kToolCategories) {
    if (c.id != kWifiClassroomCategoryId) continue;
    for (final ToolEntry t in c.tools) {
      if (kWifiClassroomSimulatorSubgroups.contains(t.subgroup)) yield t;
    }
  }
}

/// Returns [routes] with every Wi-Fi Classroom tool's builder wrapped in a
/// [LargeScreenGate]. Routes that are not Lab tools pass through untouched.
Map<String, WidgetBuilder> gateWifiLabRoutes(
  Map<String, WidgetBuilder> routes, {
  List<ToolCategory>? catalog,
}) {
  final Map<String, String> labTitles = <String, String>{
    for (final ToolEntry t in wifiLabTools(catalog)) t.routeName: t.title,
  };
  return <String, WidgetBuilder>{
    for (final MapEntry<String, WidgetBuilder> e in routes.entries)
      e.key: labTitles.containsKey(e.key)
          ? (BuildContext _) =>
                LargeScreenGate(toolTitle: labTitles[e.key]!, builder: e.value)
          : e.value,
  };
}

/// Shows [builder]'s tool, or the large-screen notice below the presenter
/// threshold until the user continues.
class LargeScreenGate extends StatefulWidget {
  const LargeScreenGate({
    super.key,
    required this.toolTitle,
    required this.builder,
  });

  /// The tool's catalog title, shown in the notice's AppBar.
  final String toolTitle;

  /// Builds the tool screen. Not called while the notice shows, so a
  /// simulator's controller and timers do not start behind it.
  final WidgetBuilder builder;

  @override
  State<LargeScreenGate> createState() => _LargeScreenGateState();
}

class _LargeScreenGateState extends State<LargeScreenGate> {
  /// Latches true the first time the tool is shown and never goes back.
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: largeScreenNoticeDismissed,
      builder: (BuildContext context, bool dismissed, Widget? _) {
        if (!_revealed &&
            (dismissed || presenterAvailable(MediaQuery.sizeOf(context)))) {
          _revealed = true;
        }
        if (_revealed) return widget.builder(context);
        return LargeScreenNotice(
          toolTitle: widget.toolTitle,
          onContinue: () => largeScreenNoticeDismissed.value = true,
          onBack: () => Navigator.of(context).maybePop(),
        );
      },
    );
  }
}

/// The notice screen itself. Stateless; the gate owns the decision.
class LargeScreenNotice extends StatelessWidget {
  const LargeScreenNotice({
    super.key,
    required this.toolTitle,
    required this.onContinue,
    required this.onBack,
  });

  final String toolTitle;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(toolTitle)),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenEdgeMobile),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.contentMaxWidth,
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          ExcludeSemantics(
                            child: Icon(
                              Icons.devices_outlined,
                              color: colors.textAccent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                kLargeScreenNoticeTitle,
                                style: text.titleLarge?.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        kLargeScreenNoticeBody,
                        style: text.bodyLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: onContinue,
                        child: const Text(kLargeScreenContinueLabel),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton(
                        onPressed: onBack,
                        child: const Text(kLargeScreenBackLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
