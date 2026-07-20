// Wi-Fi Information — the Location permission gate, driven across ALL FOUR
// authorization states.
//
// WHY THIS FILE EXISTS. wifi_info_screen.dart rendered a "Grant Location"
// button in every unauthorized state. macOS never re-prompts for Location once
// the status has left `notDetermined`, and Android will not re-prompt after a
// permanent denial, so under `denied` / `restricted` that button was guaranteed
// to do nothing at all: no prompt, no error, no navigation. Keith hit exactly
// this on the AP scan screen in a live deployment and clicked it repeatedly.
// The screen has held the tri-state `_nameAuth` the whole time and simply never
// consulted it. The defect is the unconsulted state, not the button
// ([[feedback_ui_rendered_a_decision_it_lacked]]).
//
// WHY IT SURVIVED, AND WHAT THIS FILE FIXES ABOUT THAT. The fakes in
// wifi_info_screen_test.dart collapse authorization to a single bool and can
// therefore only ever return `authorized` or `notDetermined` (:174, :212).
// `denied` and `restricted` were NEVER driven on this screen by any test in the
// tree. A missing state has no name, so no test drives it, and the suite stays
// green precisely BECAUSE the bit is missing. The fake below takes an explicit
// [LocationAuthStatus] so every state the platform has is a state a test can
// drive, and all four are driven here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A name-gated snapshot: connected, RF details readable, SSID/BSSID withheld
/// by the OS permission gate. This is the exact shape that renders the Location
/// card.
ConnectedAp _gatedSample() => ConnectedAp.fromWifiInfo(
      const WifiInfo(
        interfaceName: 'en0',
        ssid: null,
        bssid: null,
        rssiDbm: -50,
        noiseDbm: -95,
        snrDb: 45,
        txRateMbps: 866,
        phyMode: '802.11ax',
        channel: 36,
        channelWidthMhz: 80,
        band: '5 GHz',
        countryCode: 'US',
        hardwareAddress: 'a4:83:e7:aa:bb:cc',
        poweredOn: true,
        locationAuthorized: false,
      ),
    );

/// A gated adapter whose authorization is an explicit TRI-STATE, not a bool.
///
/// The pre-existing fakes derive the status from a single `_granted` flag, so
/// they can only express `authorized` / `notDetermined`. That is the whole
/// reason `denied` shipped unnoticed. This one takes the status directly, so
/// `denied` and `restricted` are drivable states rather than states with no
/// name.
class _AuthStateAdapter implements WifiInfoAdapter {
  _AuthStateAdapter({
    required this.status,
    this.androidLike = false,
  });

  /// The tri-state the native side reports. Set per test.
  final LocationAuthStatus status;

  /// Whether this adapter stands in for the Android source. Only affects the
  /// platform label; the source itself is chosen via `sourceOverride`.
  final bool androidLike;

  int grantCalls = 0;
  int openSettingsCalls = 0;

  @override
  String get platformLabel => androidLike ? 'Android' : 'macOS CoreWLAN';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async => _gatedSample();

  @override
  Future<bool> requestNamePermission() async {
    grantCalls++;
    // Models the real OS behavior under a non-promptable status: the request
    // returns immediately, nothing is shown to the user, and the answer does
    // not change. This is what made the button dead.
    return status == LocationAuthStatus.authorized;
  }

  @override
  Future<bool> currentNameAuthorization() async =>
      status == LocationAuthStatus.authorized;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => status;

  @override
  Future<bool> openNamePermissionSettings() async {
    openSettingsCalls++;
    return true;
  }
}

/// The real refusal journey: `notDetermined` until the prompt is answered, then
/// `denied` forever.
///
/// This is the ONLY way to reach the post-grant call site under a
/// non-promptable status, because that branch requires a grant attempt, and a
/// grant attempt requires a promptable starting state. A fake pinned to a
/// single status cannot express it, so the guard on that call site would
/// otherwise be untested.
class _DenyOnPromptAdapter implements WifiInfoAdapter {
  LocationAuthStatus _status = LocationAuthStatus.notDetermined;
  int grantCalls = 0;
  int openSettingsCalls = 0;

  @override
  String get platformLabel => 'Android';

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async => _gatedSample();

  @override
  Future<bool> requestNamePermission() async {
    grantCalls++;
    // The user said no. On Android this is the "Don't ask again" terminal state;
    // on macOS every denial is terminal. Either way the OS stops asking.
    _status = LocationAuthStatus.denied;
    return false;
  }

  @override
  Future<bool> currentNameAuthorization() async =>
      _status == LocationAuthStatus.authorized;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => _status;

  @override
  Future<bool> openNamePermissionSettings() async {
    openSettingsCalls++;
    return true;
  }
}

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  // The macOS path arms a periodic CoreWLAN poll; a live periodic timer never
  // lets pumpAndSettle settle. Matches the sibling suite's setUp/tearDown.
  setUp(() {
    WifiInfoScreen.macPollEnabled = false;
  });
  tearDown(() {
    WifiInfoScreen.macPollEnabled = true;
  });

  Future<_AuthStateAdapter> pumpAt(
    WidgetTester tester,
    LocationAuthStatus status, {
    WifiInfoSource source = WifiInfoSource.macosCoreWlan,
  }) async {
    final adapter = _AuthStateAdapter(
      status: status,
      androidLike: source == WifiInfoSource.androidWifiManager,
    );
    await tester.pumpWidget(host(
      WifiInfoScreen(sourceOverride: source, macAdapter: adapter),
    ));
    await tester.pumpAndSettle();
    return adapter;
  }

  group('Wi-Fi Information Location gate — the four platform states', () {
    // ---------------------------------------------------------------- state 1
    testWidgets(
        'notDetermined (PROMPTABLE): the in-app Grant Location button renders, '
        'because this is the one state where the OS can still show a prompt',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(find.text('Grant Location'), findsOneWidget);
      expect(find.text('Open Location Settings'), findsOneWidget);
    });

    testWidgets(
        'notDetermined: Settings stays the SECONDARY (outlined) action, because '
        'the in-app grant is the faster route when it can work', (tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(
        find.widgetWithText(OutlinedButton, 'Open Location Settings'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Open Location Settings'),
        findsNothing,
      );
    });

    // ---------------------------------------------------------------- state 2
    testWidgets(
        'DENIED: the dead button is GONE. No in-app grant is offered, because '
        'macOS will not re-prompt and the request would do nothing',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(find.text('Grant Location'), findsNothing);
    });

    testWidgets(
        'DENIED: Open Location Settings is the SOLE action and is PRIMARY '
        '(filled), because it is the only route that can work', (tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(
        find.widgetWithText(FilledButton, 'Open Location Settings'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Open Location Settings'),
        findsNothing,
      );
    });

    testWidgets(
        'DENIED: the deep-link still routes to the adapter, so the one '
        'remaining control is not itself dead', (tester) async {
      final adapter = await pumpAt(tester, LocationAuthStatus.denied);

      expect(adapter.openSettingsCalls, 0);
      await tester.tap(find.text('Open Location Settings'));
      await tester.pumpAndSettle();
      expect(adapter.openSettingsCalls, 1);
    });

    testWidgets(
        'DENIED: the COPY changes too. It states the app cannot ask again and '
        'names where the switch lives, instead of telling a denied user to '
        'grant something the OS forbids', (tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(find.textContaining('cannot ask again'), findsOneWidget);
      expect(find.textContaining('System Settings'), findsWidgets);
    });

    testWidgets(
        'DENIED: the grant control is gone from the SEMANTICS tree too, not '
        'merely from the pixels. A screen reader must not be offered a route '
        'the OS forbids either', (tester) async {
      final adapter = await pumpAt(tester, LocationAuthStatus.denied);

      // Asserting `grantCalls == 0` alone would be a test that cannot fail:
      // nothing taps, so it passes on the UNFIXED code too. The assertion that
      // carries weight is that the affordance does not exist at all.
      expect(find.bySemanticsLabel('Grant Location permission'), findsNothing);
      expect(adapter.grantCalls, 0);
    });

    // ---------------------------------------------------------------- state 3
    testWidgets(
        'RESTRICTED (MDM / parental policy): treated exactly like denied. No '
        'in-app grant, because the user is not permitted to answer a prompt',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.restricted);

      expect(find.text('Grant Location'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open Location Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
        'RESTRICTED: the copy does not instruct an in-app grant either',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.restricted);

      expect(find.textContaining('cannot ask again'), findsOneWidget);
    });

    // ---------------------------------------------------------------- state 4
    testWidgets(
        'AUTHORIZED: no Location card at all. The screen never blames a '
        'permission the app actually holds', (tester) async {
      await pumpAt(tester, LocationAuthStatus.authorized);

      expect(find.text('Grant Location'), findsNothing);
      expect(find.text('Open Location Settings'), findsNothing);
      expect(find.textContaining('cannot ask again'), findsNothing);
    });

    // ------------------------------------------------------------ Android arm
    testWidgets(
        'Android DENIED (permanently denied): same guard. Android cannot '
        're-prompt after "Don\'t ask again", so no in-app grant renders',
        (tester) async {
      await pumpAt(
        tester,
        LocationAuthStatus.denied,
        source: WifiInfoSource.androidWifiManager,
      );

      expect(find.text('Grant Location'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open App Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Android notDetermined: the grant DOES render, so the guard is not a '
        'blanket removal of the in-app path on Android', (tester) async {
      await pumpAt(
        tester,
        LocationAuthStatus.notDetermined,
        source: WifiInfoSource.androidWifiManager,
      );

      expect(find.text('Grant Location'), findsOneWidget);
    });

    // --------------------------------------------------- the post-grant branch
    //
    // THE SECOND CALL SITE. `_buildLocationCard` has two `_LocationCard` call
    // sites, and the post-grant one (reached once `_locationGrantAttempted` is
    // set) re-offered the in-app grant on Android. Reaching it requires actually
    // TAPPING Grant, which requires starting at `notDetermined`. A test that
    // merely starts at `denied` never enters this branch at all, and a guard
    // here would survive with the suite still green. So this drives the real
    // user journey: prompt shown, user taps Deny, status transitions.
    testWidgets(
        'POST-GRANT: user taps Grant and DENIES the prompt. The screen must not '
        're-offer the in-app grant, which is the exact loop Keith hit in the '
        'field (click, nothing, click, nothing, forever)', (tester) async {
      final adapter = _DenyOnPromptAdapter();
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();

      // Starting state is promptable, so the grant is correctly offered.
      expect(find.text('Grant Location'), findsOneWidget);

      // The user taps it and denies the system prompt.
      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();
      expect(adapter.grantCalls, 1);

      // The status is now `denied`. The OS will not ask again, so the button
      // that would ask again must be gone. Before the fix it rendered here and
      // could be tapped forever with no prompt and no error.
      expect(find.text('Grant Location'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open App Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
        'POST-GRANT: the copy after a refusal says the app cannot ask again, '
        'rather than inviting another tap on a control that is gone',
        (tester) async {
      final adapter = _DenyOnPromptAdapter();
      await tester.pumpWidget(host(
        WifiInfoScreen(
          sourceOverride: WifiInfoSource.androidWifiManager,
          macAdapter: adapter,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot ask again'), findsOneWidget);
    });

    // -------------------------------------------------------- semantics / a11y
    testWidgets(
        'DENIED: the Settings button announces itself as the enabling action, '
        'so assistive tech gets the same primary route the eye does',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.denied);

      expect(
        find.bySemanticsLabel(
          'Open macOS Location Services settings to enable Location for this app',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'notDetermined: the grant button keeps its own semantics label',
        (tester) async {
      await pumpAt(tester, LocationAuthStatus.notDetermined);

      expect(
        find.bySemanticsLabel('Grant Location permission'),
        findsOneWidget,
      );
    });
  });
}
