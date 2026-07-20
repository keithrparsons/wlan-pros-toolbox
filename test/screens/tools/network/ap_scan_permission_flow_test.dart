// Nearby AP Scan — the LOCATION PERMISSION FLOW.
//
// Both defects covered here were found by Keith in a live conference
// deployment, in a release-signed build, on a machine whose Location grant had
// been genuinely denied. Neither was reachable from the states the earlier
// gates drove: five gate cycles exercised only `notDetermined` (fresh machine)
// and `authorized` (granted machine), and `denied` — the one state where the
// in-app prompt CANNOT work — was never once driven. That gap is the whole
// reason this file exists, so every test below names the authorization state it
// drives, and all three are driven explicitly.
//
// DEFECT 1 (HIGH) — "Grant Location" was a dead button under `denied`.
//   macOS never re-prompts after a denial: CLLocationManager's
//   requestWhenInUseAuthorization() is a no-op once the status has left
//   `notDetermined`, and WifiInfoChannel.swift's `requestLocationPermission`
//   correctly returns the current bool immediately rather than awaiting a
//   callback that will never fire. The screen, however, read only the BOOLEAN
//   `isLocationAuthorized` and so could not tell "never asked" from "asked and
//   refused" — it rendered the same "Grant Location" button in both, and under
//   `denied` that button was guaranteed to do nothing at all. A control the UI
//   announces as functional but which cannot act is the defect; the copy that
//   instructs a denied user to grant in-app is the same defect in prose,
//   because it tells them to do something the OS forbids.
//
// DEFECT 2 — a FALSE VERDICT in the instant after a successful grant.
//   The screen requested the grant and immediately re-scanned. The grant had
//   not yet propagated to CoreWLAN, so that scan returned unauthorized and the
//   screen rendered "The scan did not run: Location is still not granted" —
//   asserting, with full confidence, the opposite of what the user had just
//   done. It corrected itself seconds later. A user without Keith's priors
//   reads the first verdict and concludes the feature is broken.
//   This is the app blaming the environment for the app's own timing, which is
//   the one lie this app must never tell ([[feedback_app_blames_the_wifi]]).
//
// The fix for BOTH is the same missing input: the native side has always
// exposed the TRISTATE (`locationAuthorizationStatus` →
// authorized/denied/restricted/notDetermined, WifiInfoChannel.swift and
// MainActivity.kt's wifi_info channel), and Dart has always had the typed
// `LocationAuthStatus` for it. The AP-scan screen simply never read it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ap_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A native-shaped scan payload. [locationAuthorized] drives the verdict the
/// snapshot resolves to, exactly as the real channel payload does.
Map<String, Object?> _payload({bool locationAuthorized = false}) =>
    <String, Object?>{
      'poweredOn': true,
      'locationAuthorized': locationAuthorized,
      'scanThrottled': false,
      'accessPoints': <Map<String, Object?>>[
        if (locationAuthorized)
          <String, Object?>{
            'ssid': 'KeithNet',
            'bssid': 'a4:83:e7:00:11:22',
            'rssiDbm': -42,
            'channel': 36,
            'band': '5 GHz',
            'frequencyMhz': 5180,
          },
      ],
    };

/// Records what the screen asked the platform to do, so a test can assert that
/// a button did something rather than merely that it rendered.
class _PermissionSpy {
  int requestCalls = 0;
  int settingsCalls = 0;
  int statusCalls = 0;
  int scanCalls = 0;
}

/// Builds a service pinned to [status].
///
/// [authorizedAfterScans] models the real macOS propagation window: the grant
/// is held (status says `authorized`, the request returned true) but CoreWLAN
/// has not picked it up yet, so the first N scans still come back unauthorized.
/// Setting it to 0 means the very first scan already sees the grant.
ApScanService _service(
  _PermissionSpy spy, {
  required LocationAuthStatus status,
  String platform = 'macos',
  int authorizedAfterScans = 0,
  LocationAuthStatus? statusAfterRequest,
  bool requestGrants = false,
}) {
  LocationAuthStatus current = status;
  return ApScanService(
    platformOverride: platform,
    invoke: (String method, [dynamic args]) async {
      switch (method) {
        case 'scan':
        case 'lastResults':
          spy.scanCalls++;
          final bool authorized =
              current == LocationAuthStatus.authorized &&
                  spy.scanCalls > authorizedAfterScans;
          return _payload(locationAuthorized: authorized);
        case 'isLocationAuthorized':
          return current == LocationAuthStatus.authorized;
        case 'locationAuthorizationStatus':
          spy.statusCalls++;
          return current.name;
        case 'requestLocationPermission':
          spy.requestCalls++;
          if (statusAfterRequest != null) current = statusAfterRequest;
          return requestGrants || current == LocationAuthStatus.authorized;
        case 'openLocationSettings':
          spy.settingsCalls++;
          return true;
      }
      return null;
    },
  );
}

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  /// Zero-delay backoff so the settling window resolves inside a widget test
  /// without wall-clock waiting. The production default is a real backoff.
  const List<Duration> noWait = <Duration>[
    Duration.zero,
    Duration.zero,
    Duration.zero,
  ];

  testWidgets(
    'the Scan action reads as an ENABLED button, not just named '
    '(WCAG 2.2 AA SC 4.1.2)',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(spy, status: LocationAuthStatus.authorized),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      // A Semantics(button: true) without `enabled:` leaves isEnabled unset,
      // which AT announces as a DISABLED button (68d9b93). Once the scan has
      // settled, the idle Scan action is available, so it must read enabled.
      // Removing `enabled:` (the mutation) drops hasEnabledState → red.
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Scan for nearby access points'),
        ),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Scan for nearby access points',
        ),
        reason: 'the idle Scan control must not read as disabled to AT',
      );

      handle.dispose();
    },
  );

  // -------------------------------------------------------------------------
  // DEFECT 1 — the dead "Grant Location" button.
  // -------------------------------------------------------------------------
  group('DEFECT 1 — a control that cannot act is never offered', () {
    // The two not-promptable states. macOS will not re-prompt for either, so
    // in BOTH the in-app grant button is guaranteed to do nothing.
    for (final LocationAuthStatus status in <LocationAuthStatus>[
      LocationAuthStatus.denied,
      LocationAuthStatus.restricted,
    ]) {
      testWidgets(
          '${status.name}: NO "Grant Location" button is rendered at all',
          (WidgetTester tester) async {
        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(spy, status: status),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        // THE DEFECT: this button was rendered under `denied`, and tapping it
        // did nothing — no prompt, no error, no navigation. Keith tapped it
        // repeatedly in the field. A button that cannot act is not offered.
        expect(find.text('Grant Location'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Grant Location'), findsNothing);
      });

      testWidgets(
          '${status.name}: "Open Settings" is present AND is the PRIMARY action',
          (WidgetTester tester) async {
        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(spy, status: status),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        // The ONLY route that can possibly work, so it carries primary weight
        // rather than sitting as the outlined afterthought beside a dead
        // FilledButton.
        expect(
          find.widgetWithText(FilledButton, 'Open Settings'),
          findsOneWidget,
        );

        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();
        expect(spy.settingsCalls, 1);
      });

      testWidgets(
          '${status.name}: the copy never instructs an in-app grant the OS forbids',
          (WidgetTester tester) async {
        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(spy, status: status),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        // "Grant it to list the nearby access points" is an instruction the
        // user cannot carry out from inside the app once the status has left
        // notDetermined. Telling them to do it is the prose form of the dead
        // button.
        expect(find.textContaining('Grant it to list'), findsNothing);

        // It must instead say that this app cannot ask again, and point at the
        // one place the grant can actually be changed.
        expect(find.textContaining('Settings'), findsWidgets);
        expect(find.textContaining('cannot ask again'), findsOneWidget);

        // And it must still lead with the two-kinds-of-null honesty: the scan
        // did not run, so the screen claims nothing about the air.
        expect(find.textContaining('scan could not run'), findsOneWidget);
      });
    }

    testWidgets(
        'notDetermined: "Grant Location" IS offered, and tapping it prompts',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.authorized,
          requestGrants: true,
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      // The counterweight to the tests above: this is the ONE state where the
      // native prompt can genuinely appear, so removing the button here would
      // be its own defect. Keith confirmed the prompt works in this state
      // after a `tccutil reset`.
      expect(find.text('Grant Location'), findsOneWidget);

      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();
      expect(spy.requestCalls, 1);
    });

    testWidgets('the screen actually READS the tristate, not just the boolean',
        (WidgetTester tester) async {
      // The root cause was that neither ap_scan_service.dart nor
      // ap_scan_screen.dart ever called `locationAuthorizationStatus`, so the
      // screen was structurally incapable of telling the three states apart.
      // Asserting the call is what stops a future refactor from quietly
      // reverting to the boolean and passing every copy assertion above by
      // accident.
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(spy, status: LocationAuthStatus.denied),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      expect(spy.statusCalls, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  // DEFECT 2 — the false verdict in the post-grant settling window.
  // -------------------------------------------------------------------------
  group('DEFECT 2 — no authorization-failure verdict right after a grant', () {
    testWidgets(
        'the grant lands but CoreWLAN lags: the screen NEVER says "not granted"',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.authorized,
          requestGrants: true,
          // The first two post-grant scans still report unauthorized — this is
          // exactly the propagation window Keith hit in the field.
          authorizedAfterScans: 4,
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location'));
      // Pump a single frame: this is the instant the old code rendered its
      // confident false negative, before any retry had a chance to correct it.
      await tester.pump();

      // THE DEFECT, verbatim from the field: the app told Keith Location was
      // still not granted seconds after he granted it.
      expect(find.textContaining('still not granted'), findsNothing);
      expect(find.textContaining('did not run'), findsNothing);

      await tester.pumpAndSettle();
      // And it must not have settled into that verdict either.
      expect(find.textContaining('still not granted'), findsNothing);
    });

    testWidgets('the settling window is stated honestly while it resolves',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.authorized,
          requestGrants: true,
          authorizedAfterScans: 4,
        ),
        // A REAL wait, so the test can stop the clock inside the settling
        // window rather than racing the microtask queue to observe it.
        grantSettleBackoff: const <Duration>[Duration(milliseconds: 200)],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location'));
      await tester.pump(); // request resolves, status refreshes, phase=settling
      await tester.pump(const Duration(milliseconds: 50)); // inside the backoff

      // Not a blank, not a false verdict: the screen says the grant landed and
      // that it is waiting on the scan — which is the true description of the
      // state it is actually in.
      expect(find.textContaining('Location is granted'), findsOneWidget);
      expect(find.textContaining('still not granted'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('the retry resolves to the AP list once the grant propagates',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.authorized,
          requestGrants: true,
          authorizedAfterScans: 4,
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();

      // The whole point of waiting instead of asserting: the scan Keith was
      // actually owed does arrive, and the screen shows it.
      expect(find.text('KeithNet'), findsOneWidget);
      expect(find.textContaining('scan could not run'), findsNothing);
    });

    testWidgets(
        'a genuine REFUSAL at the prompt is still reported honestly, not hidden',
        (WidgetTester tester) async {
      // The counterweight to the settling state: suppressing the failure
      // verdict must not become suppressing the TRUTH. A user who clicks Deny
      // at the prompt has genuinely denied it, and the screen owes them the
      // deep-link, not an indefinite "waiting" spinner.
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.denied,
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location'));
      await tester.pumpAndSettle();

      // Now genuinely denied: the button that cannot act is gone, and the one
      // that can is primary.
      expect(find.text('Grant Location'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open Settings'),
        findsOneWidget,
      );
      expect(find.textContaining('cannot ask again'), findsOneWidget);
    });

    testWidgets(
        'authorized but the scan still cannot read: says so WITHOUT claiming '
        'the grant is missing', (WidgetTester tester) async {
      // The terminal state of an exhausted settling window. The status says
      // authorized, so "Location is not granted" would be a false statement
      // about the machine. The screen reports what it actually knows.
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.authorized,
          // Never becomes authorized within any number of scans this test runs.
          authorizedAfterScans: 100000,
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('still not granted'), findsNothing);
      expect(find.textContaining('Grant it to list'), findsNothing);
      expect(find.text('Grant Location'), findsNothing);
      expect(find.textContaining('Location is granted'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Service routing. The widget tests above inject a SINGLE fake for both
  // channel seams, so they cannot tell which channel the tri-state was read
  // from — and on Android that distinction is the difference between a status
  // and a `notImplemented`. These tests inject the two seams SEPARATELY.
  // -------------------------------------------------------------------------
  group('ApScanService.locationAuthorizationStatus — channel routing', () {
    /// Builds a service whose two channel seams are distinguishable.
    ApScanService split(
      String platform, {
      required List<String> apScanCalls,
      required List<String> wifiInfoCalls,
      String? wifiInfoToken,
      bool apScanImplements = false,
    }) =>
        ApScanService(
          platformOverride: platform,
          invoke: (String method, [dynamic args]) async {
            apScanCalls.add(method);
            // The REAL Android ap_scan channel has no such method. Modelling it
            // as implemented would be a fake that is kinder than the platform,
            // and the bug would sail straight through the test.
            if (!apScanImplements && method == 'locationAuthorizationStatus') {
              throw MissingPluginException(
                'No implementation found for method $method',
              );
            }
            return null;
          },
          invokeWifiInfo: (String method, [dynamic args]) async {
            wifiInfoCalls.add(method);
            return wifiInfoToken;
          },
        );

    for (final String os in const <String>['android', 'macos']) {
      test('$os: reads the tri-state from the wifi_info channel', () async {
        final List<String> apScan = <String>[];
        final List<String> wifiInfo = <String>[];
        final ApScanService service = split(
          os,
          apScanCalls: apScan,
          wifiInfoCalls: wifiInfo,
          wifiInfoToken: 'denied',
        );

        expect(
          await service.locationAuthorizationStatus(),
          LocationAuthStatus.denied,
        );

        // MainActivity.kt implements `locationAuthorizationStatus` on the
        // wifi_info channel only; its apScanChannelName handler falls through
        // to `notImplemented`. Routing this call the way the OTHER permission
        // calls are routed would therefore break Android silently — and, worse,
        // fail SAFE to `notDetermined`, which is exactly the state that
        // re-renders the dead "Grant Location" button.
        expect(wifiInfo, contains('locationAuthorizationStatus'));
        expect(apScan, isNot(contains('locationAuthorizationStatus')));
      });
    }

    test('an unimplemented channel degrades to notDetermined, never throws',
        () async {
      final List<String> apScan = <String>[];
      final List<String> wifiInfo = <String>[];
      final ApScanService service = ApScanService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          apScan.add(method);
          return null;
        },
        invokeWifiInfo: (String method, [dynamic args]) async {
          wifiInfo.add(method);
          throw MissingPluginException('No implementation found');
        },
      );

      // A gate card that throws is a gate card that renders nothing at all.
      expect(
        await service.locationAuthorizationStatus(),
        LocationAuthStatus.notDetermined,
      );
    });

    test('an unrecognized native token degrades to notDetermined', () async {
      final ApScanService service = split(
        'macos',
        apScanCalls: <String>[],
        wifiInfoCalls: <String>[],
        wifiInfoToken: 'somethingNewInAFutureOS',
      );
      expect(
        await service.locationAuthorizationStatus(),
        LocationAuthStatus.notDetermined,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The SAME defect family, one step further along: under `denied`, "Open
  // Settings" is the ONLY action on the card. If the deep-link fails to open
  // and the screen says nothing, the last remaining control is itself a dead
  // button.
  // -------------------------------------------------------------------------
  group('a deep-link that does not open is never silent', () {
    testWidgets('macOS: names the manual path when the pane will not open',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(ApScanScreen(
        service: ApScanService(
          platformOverride: 'macos',
          invoke: (String method, [dynamic args]) async {
            switch (method) {
              case 'scan':
              case 'lastResults':
                return _payload();
              case 'locationAuthorizationStatus':
                return 'denied';
              case 'isLocationAuthorized':
                return false;
              // The pane failed to open. The service has always reported this
              // faithfully; the screen used to discard it.
              case 'openLocationSettings':
                return false;
            }
            return null;
          },
        ),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not open the settings page'),
          findsOneWidget);
      // Not just an apology: the route the user must now walk themselves.
      expect(find.textContaining('Privacy & Security'), findsOneWidget);
    });

    testWidgets('a deep-link that DOES open stays quiet',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(spy, status: LocationAuthStatus.denied),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // The counterweight: a working deep-link must not fire an error the user
      // can plainly see is wrong, because they are looking at the open pane.
      expect(find.textContaining('Could not open'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Accessibility and responsive behaviour of the reworked gate card.
  // -------------------------------------------------------------------------
  group('gate card — accessibility and layout', () {
    testWidgets('the denied primary action carries a descriptive semantic label',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(spy, status: LocationAuthStatus.denied),
        grantSettleBackoff: noWait,
      )));
      await tester.pumpAndSettle();

      // "Open Settings" alone does not say WHICH settings or WHY, and it is now
      // the only action on the card, so the label carries the whole task.
      expect(
        find.bySemanticsLabel(
          'Open System Settings to enable Location for this app',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the settling state is announced, not just spun',
        (WidgetTester tester) async {
      final _PermissionSpy spy = _PermissionSpy();
      await tester.pumpWidget(host(ApScanScreen(
        service: _service(
          spy,
          status: LocationAuthStatus.notDetermined,
          statusAfterRequest: LocationAuthStatus.authorized,
          requestGrants: true,
          authorizedAfterScans: 4,
        ),
        grantSettleBackoff: const <Duration>[Duration(milliseconds: 200)],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grant Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // A bare CircularProgressIndicator is invisible to a screen reader. The
      // status text beside it is the accessible carrier of "still working".
      expect(find.text('Checking again…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
    });

    testWidgets('the gate card is keyboard-reachable in every actionable state',
        (WidgetTester tester) async {
      for (final LocationAuthStatus status in <LocationAuthStatus>[
        LocationAuthStatus.notDetermined,
        LocationAuthStatus.denied,
      ]) {
        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(spy, status: status),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        // Scoped to the GATE CARD's own actions. A tree-wide sweep would also
        // pick up the app bar's copy affordance, which is CORRECTLY disabled
        // when there is no scan to copy — a real behaviour, not a defect, and
        // not this card's concern.
        final Iterable<String> labels = <String>[
          if (status == LocationAuthStatus.notDetermined) 'Grant Location',
          'Open Settings',
        ];
        for (final String label in labels) {
          final Finder button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
          );
          expect(button, findsOneWidget, reason: '$status: no "$label" action');
          // Enabled means focusable, and focusable means operable without a
          // pointer. A gate the keyboard cannot clear is a gate for some users.
          expect(
            tester.widget<ButtonStyleButton>(button).enabled,
            isTrue,
            reason: '$status rendered "$label" disabled',
          );
        }
      }
    });

    for (final double width in const <double>[320, 768, 1280]) {
      testWidgets('denied card renders without overflow at ${width}px',
          (WidgetTester tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(spy, status: LocationAuthStatus.denied),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        // The long denied copy plus a primary button is the widest this card
        // ever gets; a phone-width overflow would clip the one instruction
        // that can unblock the user.
        expect(tester.takeException(), isNull);
        expect(find.text('Open Settings'), findsOneWidget);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Cross-platform: the tristate must reach BOTH wired platforms.
  // -------------------------------------------------------------------------
  group('both wired platforms read the tristate', () {
    for (final String os in const <String>['android', 'macos']) {
      testWidgets('$os: denied renders the deep-link path, never the dead button',
          (WidgetTester tester) async {
        final _PermissionSpy spy = _PermissionSpy();
        await tester.pumpWidget(host(ApScanScreen(
          service: _service(
            spy,
            status: LocationAuthStatus.denied,
            platform: os,
          ),
          grantSettleBackoff: noWait,
        )));
        await tester.pumpAndSettle();

        expect(find.text('Grant Location'), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Open Settings'),
          findsOneWidget,
        );
      });
    }
  });
}
