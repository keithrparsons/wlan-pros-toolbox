// ChromeOS / ARC-VM — the UI half of the honest-null net.
//
// The service suite (test/services/network/chromeos_arc_test.dart) proves the
// untrustworthy VALUES never reach the widget layer. This suite proves the other
// half of Keith's instruction — "Explain, don't just hide" — actually lands on
// screen:
//
//   * the notice renders on ChromeOS, and renders NOTHING anywhere else;
//   * the suppressed rows carry their REASON, not a bare "Unavailable" (a blank
//     row with no explanation reads as a broken tool, which is the failure mode
//     that made users distrust the whole app);
//   * no ChromeOS copy ever blames Android for a ChromeOS ceiling;
//   * the Wi-Fi Information screen shows the real, ONC-defined fields (SSID,
//     BSSID, channel, band) — the fix is a scalpel, not a hammer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/services/network/chromeos_arc.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart'
    show WifiInfoAdapter, WifiInfoSource;
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus;
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/chromeos_arc_notice.dart';

/// The exact ConnectedAp the Android adapter produces INSIDE ARC: the ONC fields
/// real, the untrustworthy five null, `isChromeOs` set.
const ConnectedAp _arcReading = ConnectedAp(
  ssid: 'Lincoln-Staff',
  bssid: 'a4:83:e7:00:11:22',
  channel: 44,
  band: '5 GHz',
  rssiDbm: null,
  noiseDbm: null,
  snrDb: null,
  txRateMbps: null,
  rxRateMbps: null,
  standard: null,
  channelWidthMhz: null,
  rxRateAvailable: false,
  channelWidthAvailable: false,
  securityAvailable: true,
  isChromeOs: true,
);

/// A normal Android phone: real RF everywhere.
const ConnectedAp _phoneReading = ConnectedAp(
  ssid: 'WLANPros',
  bssid: 'a4:83:e7:00:11:22',
  channel: 44,
  band: '5 GHz',
  rssiDbm: -52,
  txRateMbps: 866,
  rxRateMbps: 866,
  standard: '802.11ax (Wi-Fi 6)',
  channelWidthMhz: 80,
  rxRateAvailable: true,
  channelWidthAvailable: true,
  securityAvailable: true,
);

class _FakeAdapter implements WifiInfoAdapter {
  const _FakeAdapter(this.ap);
  final ConnectedAp ap;

  @override
  Future<ConnectedAp> fetch() async => ap;
  @override
  bool get gatesNameBehindPermission => false;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => false;
  @override
  String get platformLabel => 'fake';
}

Widget _host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

Future<void> _pumpWifiInfo(WidgetTester tester, ConnectedAp ap) async {
  await tester.binding.setSurfaceSize(const Size(560, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(WifiInfoScreen(
    sourceOverride: WifiInfoSource.androidWifiManager,
    macAdapter: _FakeAdapter(ap),
  )));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ToolHelpLoader.ensureLoaded();
  });

  tearDown(() => ChromeOsArc.debugSetIsChromeOs(null));

  // =========================================================================
  group('ChromeOsArcNotice', () {
    testWidgets('renders NOTHING off ChromeOS — zero footprint on every other '
        'platform', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const Scaffold(body: ChromeOsArcNotice(isChromeOsOverride: false)),
      ));
      expect(find.text(ChromeOsArc.noticeHeadline), findsNothing);
      expect(find.byType(SizedBox), findsWidgets); // the shrink-wrapped nothing
    });

    testWidgets('on ChromeOS it states WHAT is hidden and WHY',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const Scaffold(
          body: ChromeOsArcNotice(
            isChromeOsOverride: true,
            stillTrue: ChromeOsArc.stillTrueWifi,
          ),
        ),
      ));
      expect(find.text(ChromeOsArc.noticeHeadline), findsOneWidget);
      expect(find.text(ChromeOsArc.noticeBody), findsOneWidget);
      // …and, critically, what the user CAN still trust. Without this the notice
      // reads as "the app is broken here" rather than "these four fields are".
      expect(find.text(ChromeOsArc.stillTrueWifi), findsOneWidget);
    });

    testWidgets(
        'the meaning is carried by WORDS, never by color alone (WCAG 2.2 SC '
        '1.4.1) — and the card is one merged semantics node',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        const Scaffold(
          body: ChromeOsArcNotice(
            isChromeOsOverride: true,
            stillTrue: ChromeOsArc.stillTrueWifi,
          ),
        ),
      ));
      // The headline is a real string in the tree, so a screen reader (and a
      // colorblind user) gets the meaning without relying on the info hue.
      expect(
        find.bySemanticsLabel(RegExp(ChromeOsArc.noticeHeadline)),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  // =========================================================================
  group('Wi-Fi Information on ChromeOS', () {
    testWidgets('the notice appears above the cards',
        (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(true);
      await _pumpWifiInfo(tester, _arcReading);
      expect(find.byType(ChromeOsArcNotice), findsOneWidget);
      expect(find.text(ChromeOsArc.noticeHeadline), findsOneWidget);
    });

    testWidgets(
        'every suppressed row states its REASON — a blank row with no '
        'explanation reads as a broken tool', (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(true);
      await _pumpWifiInfo(tester, _arcReading);

      // RSSI — the headline suppression. This is the row that used to show a
      // dBm reconstructed from a percentage.
      expect(find.text(ChromeOsArc.signalReason), findsOneWidget);
      // Noise + SNR.
      expect(find.text(ChromeOsArc.noiseReason), findsOneWidget);
      expect(find.text(ChromeOsArc.snrReason), findsOneWidget);
      // Tx + Rx rate (both rows carry the same reason).
      expect(find.text(ChromeOsArc.rateReason), findsNWidgets(2));
      // Channel width.
      expect(find.text(ChromeOsArc.channelWidthReason), findsOneWidget);
      // 802.11 standard.
      expect(find.text(ChromeOsArc.standardReason), findsOneWidget);
    });

    testWidgets(
        'no ChromeOS row blames ANDROID or macOS for a ChromeOS ceiling — a '
        'Chromebook user sent hunting an Android fix is a bug',
        (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(true);
      await _pumpWifiInfo(tester, _arcReading);

      // These are the pre-existing Android/macOS ceiling strings. On a Chromebook
      // every one of them would be a wrong claim about the wrong OS.
      expect(find.textContaining('no noise-floor API'), findsNothing,
          reason: 'the Android noise note leaked onto ChromeOS');
      expect(find.textContaining('not exposed on macOS'), findsNothing,
          reason: 'the macOS Rx note leaked onto ChromeOS — this fires off '
              'rxRateAvailable, which is now ALSO false on ChromeOS');
      expect(find.textContaining("Not exposed by Android"), findsNothing);
      expect(find.textContaining("this device's Android link"), findsNothing);
      // "Not reported for this network" implies ANOTHER network might report the
      // width. On ChromeOS none ever will — it is an OS ceiling, not a per-net
      // miss. Saying otherwise is a lie of implication.
      expect(find.text('Not reported for this network'), findsNothing,
          reason: 'channel width on ChromeOS is a permanent OS ceiling, not a '
              'per-network miss');
    });

    testWidgets('the REAL, ONC-defined fields still render — scalpel, not hammer',
        (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(true);
      await _pumpWifiInfo(tester, _arcReading);

      expect(find.text('Lincoln-Staff'), findsWidgets, reason: 'SSID is real');
      expect(find.text('a4:83:e7:00:11:22'), findsWidgets,
          reason: 'BSSID is real');
      expect(find.text('44'), findsWidgets, reason: 'channel is real');
      expect(find.text('5 GHz'), findsWidgets, reason: 'band is real');
    });

    testWidgets('no dBm value is rendered anywhere on ChromeOS',
        (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(true);
      await _pumpWifiInfo(tester, _arcReading);
      // A negative-number dBm reading is the exact artifact we refuse to ship.
      expect(find.textContaining(RegExp(r'-\d+\s*dBm')), findsNothing);
    });
  });

  // =========================================================================
  // SOP-007 §8 — verify at mobile / tablet / desktop before handing to Vera.
  // The notice carries the longest body copy in the app's network screens, so it
  // is the most likely thing to overflow on a narrow Chromebook-in-tablet-mode
  // window. Flutter surfaces a RenderFlex overflow as a test failure, so an
  // unguarded Row/Column here fails LOUDLY rather than shipping a clipped card.
  // =========================================================================
  group('responsive — the notice lays out at every breakpoint', () {
    for (final (String name, double width) in <(String, double)>[
      ('mobile', 360),
      ('tablet', 768),
      ('desktop', 1280),
    ]) {
      testWidgets('$name ($width px): no overflow, all copy present',
          (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_host(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: const <Widget>[
                  ChromeOsArcNotice(
                    isChromeOsOverride: true,
                    stillTrue: ChromeOsArc.stillTrueConnection,
                  ),
                  ChromeOsArcNotice(
                    isChromeOsOverride: true,
                    stillTrue: ChromeOsArc.stillTrueWifi,
                  ),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the notice overflowed at $name width — a clipped honesty '
                'notice is worse than none, because the reader gets half a '
                'sentence and no reason');
        expect(find.text(ChromeOsArc.noticeHeadline), findsNWidgets(2));
        expect(find.text(ChromeOsArc.stillTrueConnection), findsOneWidget);
      });
    }
  });

  // =========================================================================
  group('Wi-Fi Information on a normal Android phone — untouched', () {
    testWidgets('no notice, and every real RF value renders',
        (WidgetTester tester) async {
      ChromeOsArc.debugSetIsChromeOs(false);
      await _pumpWifiInfo(tester, _phoneReading);

      expect(find.byType(ChromeOsArcNotice), findsNothing,
          reason: 'a real phone must never see the ChromeOS notice');
      // Not one ChromeOS reason may appear on a device that is not a Chromebook.
      for (final String reason in <String>[
        ChromeOsArc.signalReason,
        ChromeOsArc.noiseReason,
        ChromeOsArc.snrReason,
        ChromeOsArc.rateReason,
        ChromeOsArc.channelWidthReason,
        ChromeOsArc.standardReason,
      ]) {
        expect(find.text(reason), findsNothing,
            reason: 'a real phone must not be told about a ChromeOS ceiling');
      }
      // _MetricRow renders "<value> <unit>" as ONE Text, so assert the combined
      // string — the real RF must survive this change untouched.
      expect(find.text('-52 dBm'), findsWidgets,
          reason: 'a real phone still shows its real, measured dBm');
      expect(find.text('866 Mbps'), findsWidgets, reason: 'real link rate');
      expect(find.text('80 MHz'), findsWidgets, reason: 'real channel width');
      expect(find.text('802.11ax (Wi-Fi 6)'), findsWidgets,
          reason: 'real 802.11 standard');
    });
  });
}
