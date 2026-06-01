// Cellular Information screen — widget tests (TICKET-02).
//
// The tool selects its data source per platform behind a seam, so the tests
// drive each source explicitly via [CellularInfoScreen.sourceOverride] plus an
// injected fake bridge — no real platform channel is touched.
//
// Covers the state matrix from SOP-007 §5:
//   * iOS source: needs-install empty state, one-shot success cards (the five
//     fields), and the honest signal-bars footnote.
//   * macOS / unsupported native: the explicit "not available on this platform"
//     state (hard requirement — never a silent empty).
//   * web source: download-the-app fallback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/cellular_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_bridge.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A fake iOS Shortcuts bridge: returns a queued reading + install flag without
/// a platform channel.
class _FakeBridge implements CellularInfoBridge {
  _FakeBridge({this.everReceived = false, this.latest});

  bool everReceived;
  CellularInfo? latest;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;

  @override
  Future<CellularInfo?> readLatest() async => latest;

  @override
  Future<bool> openUrl(String url) async => true;
}

CellularInfo _sample() => const CellularInfo(
      carrier: 'Verizon',
      radioTechnology: '5G NR',
      signalBars: 3,
      countryCode: 'US',
      roaming: false,
    );

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

  group('CellularInfoScreen — iOS source', () {
    testWidgets('needs-install empty state offers Install Shortcut',
        (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: false),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No cellular data yet'), findsOneWidget);
      expect(find.text('Install Shortcut'), findsOneWidget);
    });

    testWidgets('success shows the five fields and the signal footnote',
        (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(everReceived: true, latest: _sample()),
        ),
      ));
      await tester.pumpAndSettle();

      // The four card titles.
      expect(find.text('Carrier'), findsWidgets);
      expect(find.text('Radio'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);

      // The values.
      expect(find.text('Verizon'), findsOneWidget);
      expect(find.text('5G NR'), findsOneWidget);
      expect(find.text('US'), findsOneWidget);
      expect(find.text('No'), findsOneWidget); // roaming = false

      // Signal bars render as "N of 4" — NEVER a dBm/RSRP value. The bar value
      // text must be exactly "3 of 4"; no bar value carries a dBm/RSRP unit.
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('3 dBm'), findsNothing);
      expect(find.text('-3 dBm'), findsNothing);
      expect(find.textContaining('RSRP: '), findsNothing);

      // The honest footnote stating bars are the only signal indicator.
      expect(
        find.textContaining('Apple does not expose a raw signal reading'),
        findsOneWidget,
      );
    });

    testWidgets('missing fields render an honest Unavailable', (tester) async {
      await tester.pumpWidget(host(
        CellularInfoScreen(
          sourceOverride: CellularInfoSource.iosShortcuts,
          iosBridge: _FakeBridge(
            everReceived: true,
            latest: const CellularInfo(carrier: 'AT&T'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AT&T'), findsOneWidget);
      // Radio Technology / Country Code / Roaming all absent -> Unavailable.
      expect(find.text('Unavailable'), findsWidgets);
    });
  });

  group('CellularInfoScreen — platform fallbacks', () {
    testWidgets(
        'macOS / unsupported native shows the explicit not-available state',
        (tester) async {
      await tester.pumpWidget(host(
        const CellularInfoScreen(
          sourceOverride: CellularInfoSource.unsupported,
        ),
      ));
      await tester.pumpAndSettle();
      // Hard requirement: an unmistakable warning, not a silent empty.
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
      expect(find.text('Cellular is not available here'), findsOneWidget);
      expect(
        find.textContaining('requires an iPhone with a cellular connection'),
        findsOneWidget,
      );
    });

    testWidgets('web shows the download-the-app fallback', (tester) async {
      await tester.pumpWidget(host(
        const CellularInfoScreen(sourceOverride: CellularInfoSource.web),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkUnavailableView), findsOneWidget);
    });
  });

  group('CellularInfoSourceResolver', () {
    test('iOS resolves to the Shortcuts source', () {
      expect(
        CellularInfoSourceResolver.resolve(platformOverride: TargetPlatform.iOS),
        CellularInfoSource.iosShortcuts,
      );
    });

    test('macOS resolves to unsupported (no cellular radio)', () {
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.macOS,
        ),
        CellularInfoSource.unsupported,
      );
    });

    test('Android and Windows resolve to unsupported', () {
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.android,
        ),
        CellularInfoSource.unsupported,
      );
      expect(
        CellularInfoSourceResolver.resolve(
          platformOverride: TargetPlatform.windows,
        ),
        CellularInfoSource.unsupported,
      );
    });
  });
}
