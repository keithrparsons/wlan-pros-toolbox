// MEDIUM-2: THE PROGRESS CARD SAT FROZEN AT 100% FOR UP TO EIGHT SECONDS.
//
// `onDone` does `await linkFuture.timeout(8s)` BEFORE it flips `_running` false, and
// the progress card is gated on `_running`. So after the measurement stream closes —
// the run is DONE, every byte is spent — the user watches a full bar and a stale
// phase caption for longer than the upload stage took.
//
// KEITH'S "STILL WORKING" SIGHTING IS NOT CLAIMED AS THIS. Vera could not reproduce
// that and refused to claim she had; her hypothesis died to her own test (the last
// frame is `phase=complete fraction=1.00 indeterminate=false`). Inventing a culprit
// for an unreproduced report is how a fake fix ships. This is a DIFFERENT defect,
// one I can see in the code and reproduce here. Whether it is HIS defect is unproven
// and is not asserted.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The Wi-Fi link read that NEVER LANDS — the shape that makes `onDone` sit waiting
/// after the measurement has already finished. A real one: a macOS CoreWLAN read
/// that hangs (`_readLink` caps it at 5 s, and `onDone` then waits up to 8 s).
///
/// EVERY permission method is implemented, and that is load-bearing: `_readLink`
/// calls `nameAuthorizationStatus()` BEFORE `fetch()`, inside a `try`. A
/// `noSuchMethod` there throws, the catch returns null, and the link read completes
/// INSTANTLY — so the stall never happens and the test passes against the unfixed
/// code for the wrong reason. (It did. That is why they are here.)
class _NeverLandsAdapter implements WifiInfoAdapter {
  final Completer<ConnectedAp> _never = Completer<ConnectedAp>();
  @override
  Future<ConnectedAp> fetch() => _never.future;
  @override
  String get platformLabel => 'stalled';
  @override
  bool get gatesNameBehindPermission => false;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDns implements DnsProbeService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeNetDetails implements NetworkDetailsService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeIpGeo implements IpGeoService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets(
    'while the link read is outstanding the card says what it is DOING, not 100%',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final MockQualityClient quality = MockQualityClient();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            autoStart: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _NeverLandsAdapter(),
            dnsProbeService: _FakeDns(),
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            enableCloudApps: false,
            enableLiveSampling: false,
            qualityClient: quality,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Run. macOS is never metered, so this fires with no consent tap.
      await tester.tap(find.text('Check My Connection'));
      // Let the (mock) measurement stream close. Its `onDone` now awaits the link
      // read, which will NEVER land — so we are parked in the 8 s window.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final Finder caption = find.text('Reading your Wi-Fi link');
      expect(
        caption,
        findsOneWidget,
        reason: 'the measurement is DONE and the link read is not. Say that, rather '
            'than holding a dead 100% bar for up to 8 seconds.',
      );

      // Let the 5 s read timeout (and the 8 s onDone ceiling) expire so the run
      // completes and the tree tears down cleanly (no pending timers).
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      expect(
        find.text('Reading your Wi-Fi link'),
        findsNothing,
        reason: 'the finishing state must clear once the result renders',
      );
    },
  );
}
