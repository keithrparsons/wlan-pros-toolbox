// The Join screen, rendered against the five requirements Keith earned on the
// prototype.
//
// SSIDs ARE DELIBERATELY NOT THE SHIP'S. The live scan that proved the
// (SSID, band) rule also carried two SSIDs containing the vessel name, and a
// repo fixture is the wrong place for those. MUDI is Keith's own travel router
// and is already used in join_network_list_test.dart; everything else here is
// synthetic and chosen to exercise one branch each.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/join_network_screen.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A stand-in Pi. Only the four calls the screen makes are implemented.
class FakePi implements PiBackendClient {
  FakePi({this.joinResult, this.throwOnJoin});

  final PiJoinResult? joinResult;
  final Object? throwOnJoin;

  @override
  Future<List<PiScanInterface>> scanInterfaces() async =>
      const <PiScanInterface>[
        PiScanInterface(name: 'wlan0', driver: 'mt7921u'),
        PiScanInterface(name: 'wlan1', driver: 'mt7921u'),
      ];

  @override
  Future<List<PiScanNet>> scan({String interface = 'wlan0'}) async =>
      <PiScanNet>[
        // THE DEDUPE PROOF, verbatim from Keith's own travel router: the 2.4 GHz
        // BSS is LOUDER and runs DIFFERENT SECURITY from the 5 GHz one.
        const PiScanNet(
            ssid: 'MUDI',
            bssid: 'e6:4b:3c:67:80:89',
            signalDbm: -24,
            freqMhz: 2437,
            keyMgmt: 'wpa-psk'),
        const PiScanNet(
            ssid: 'MUDI',
            bssid: '86:8f:31:56:df:b9',
            signalDbm: -35,
            freqMhz: 5745,
            keyMgmt: 'wpa-psk/sae'),
        // 802.1X: the case that is the MAJORITY of a real enterprise scan.
        const PiScanNet(
            ssid: 'CorpSecure',
            bssid: '7a:49:82:3e:41:60',
            signalDbm: -52,
            freqMhz: 5180,
            keyMgmt: 'wpa-eap'),
        const PiScanNet(
            ssid: 'CorpSecure',
            bssid: '7a:49:82:3e:32:30',
            signalDbm: -61,
            freqMhz: 5180,
            keyMgmt: 'wpa-eap'),
        // Open, which must say why there is no passphrase box.
        const PiScanNet(
            ssid: 'Lobby Guest',
            bssid: '62:49:92:3e:34:30',
            signalDbm: -58,
            freqMhz: 2437,
            keyMgmt: null),
        const PiScanNet(
            ssid: null,
            bssid: '56:49:82:3e:41:60',
            signalDbm: -71,
            freqMhz: 5180,
            keyMgmt: 'wpa-psk/wpa-psk-sha256'),
      ];

  @override
  Future<PiJoinResult> wifiConnect({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async {
    if (throwOnJoin != null) throw throwOnJoin!;
    return joinResult!;
  }

  @override
  Future<PiJoinResult> wifiDisconnect({String? interface}) async =>
      joinResult!;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PiJoinResult connected() => PiJoinResult(
      link: const PiWifiLink(
        interface: 'wlan0',
        associated: true,
        ssid: 'MUDI',
        bssid: '86:8f:31:56:df:b9',
        signalDbm: -35,
        freqMhz: 5745,
        channel: 149,
        widthMhz: 80,
        phyMode: '802.11ax (Wi-Fi 6)',
        txRateMbps: 480.1,
      ),
      requestedSsid: 'MUDI',
      secureTransport: false,
    );

PiJoinResult wrongKey() => PiJoinResult(
      link: const PiWifiLink(
        interface: 'wlan0',
        associated: false,
        reason: 'reached "MUDI" but the handshake was refused. '
            'The passphrase is wrong.',
      ),
      requestedSsid: 'MUDI',
      secureTransport: false,
    );

Future<void> pump(WidgetTester tester, PiBackendClient pi) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(760, 1180),
        textScaler: TextScaler.linear(1.0),
      ),
      child: JoinNetworkScreen(client: pi),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, String slug) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile('goldens/$slug.png'));

void main() {
  testWidgets('idle: action panel above the list, radio picker present',
      (WidgetTester tester) async {
    await pump(tester, FakePi());
    // REQUIREMENT 1: the panel is above the list even before anything is
    // picked, so the user never learns it lives at the bottom.
    expect(find.text('Pick a network below'), findsOneWidget);
    expect(find.text('Radio that scans and joins'), findsOneWidget);
    // THE DEDUPE: MUDI must appear TWICE, once per band.
    expect(find.text('MUDI'), findsNWidgets(2));
    await shot(tester, 'join_idle');
  });

  testWidgets('802.1X: no passphrase box, and it says why',
      (WidgetTester tester) async {
    await pump(tester, FakePi());
    await tester.tap(find.text('CorpSecure').first);
    await tester.pumpAndSettle();
    // REQUIREMENT 2, and this is the copy Keith approved on 2026-08-31.
    expect(find.textContaining('802.1X or OWE'), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'a passphrase box that cannot work must not be offered');
    await shot(tester, 'join_8021x');
  });

  testWidgets('open network: no passphrase box, and it says why',
      (WidgetTester tester) async {
    await pump(tester, FakePi());
    await tester.tap(find.text('Lobby Guest').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('open, so there is no passphrase'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('WPA3 network offers the box', (WidgetTester tester) async {
    await pump(tester, FakePi());
    // The 5 GHz MUDI row is the SECOND one: quieter, and WPA3-SAE.
    await tester.tap(find.text('MUDI').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // The security sits inside an interpolated summary line, so match on a
    // substring rather than the whole string.
    expect(find.textContaining('WPA3-SAE'), findsWidgets);
  });

  testWidgets('connected: the verdict is the largest thing on the card',
      (WidgetTester tester) async {
    await pump(tester, FakePi(joinResult: connected()));
    await tester.tap(find.text('MUDI').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a-real-passphrase');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    // REQUIREMENT 3.
    final Text verdict = tester.widget<Text>(find.text('Connected'));
    expect(verdict.style!.fontSize, 30);
    expect(verdict.style!.fontWeight, FontWeight.w800);
    // REQUIREMENT 4: the BSSID is present, and it is the answer to "which
    // radio did I land on".
    expect(find.text('86:8f:31:56:df:b9'), findsOneWidget);
    // The transport honesty, which the endpoint deliberately cannot enforce.
    expect(find.textContaining('plain HTTP'), findsOneWidget);
    await shot(tester, 'join_connected');
  });

  testWidgets('a wrong passphrase is NOT reported as success',
      (WidgetTester tester) async {
    await pump(tester, FakePi(joinResult: wrongKey()));
    await tester.tap(find.text('MUDI').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong-one');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOneWidget);
    // The Pi's own words distinguish a refused handshake from never reaching
    // the network. Both are failures and they need different next actions.
    expect(find.textContaining('handshake was refused'), findsOneWidget);
    await shot(tester, 'join_wrong_key');
  });

  testWidgets('a hidden network cannot be joined from a list, and says so',
      (WidgetTester tester) async {
    await pump(tester, FakePi());
    // The hidden BSS is the weakest, so it sorts last and a lazy ListView has
    // not built it yet. Scroll it in before tapping.
    await tester.scrollUntilVisible(find.text('Hidden network'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden network'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not broadcast its name'), findsOneWidget);
  });

  testWidgets('a Pi error surfaces the Pi\'s own words, not "HTTP 400"',
      (WidgetTester tester) async {
    await pump(
      tester,
      FakePi(
          throwOnJoin: PiBackendException(
              'wifi-connect failed: psk must be 8-63 characters '
              '(or a 64-char hex PMK)')),
    );
    await tester.tap(find.text('MUDI').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'short');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('8-63 characters'), findsOneWidget);
  });
}
