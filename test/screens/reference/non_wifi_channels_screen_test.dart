// Tests for the Non-Wi-Fi Wireless Channels reference screen.
//
// Two layers (mirrors wifi_channels_screen_test.dart):
//  1. Data assertions against the public consts the UI renders — locking the
//     values to Pax's verified research brief
//     (Deliverables/2026-06-02-wireless-channels-reference/data-brief.md). The
//     load-bearing check is the BLE non-linear index→frequency mapping: the
//     advertising channels 37/38/39 must sit at 2402/2426/2480 MHz, NOT at the
//     positions a naive 2402 + 2·index formula would put them (the common BLE
//     chart bug the brief warns about).
//  2. One widget test in a phone viewport — pumps the screen, asserts the title
//     and a couple of representative rows render without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/non_wifi_channels_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('LoRaWAN dataset', () {
    test('ships the verified region plans', () {
      final Set<String> plans = NonWifiChannelsScreen.loraWanPlans
          .map((LoraWanPlan p) => p.plan)
          .toSet();
      // Verified plans the brief says to ship.
      expect(
        plans,
        containsAll(<String>['EU868', 'US915', 'AU915', 'AS923', 'IN865',
            'KR920']),
      );
    });

    test('CN470 / CN779 / RU864 are flagged verify; the rest are not', () {
      final Set<String> verify = NonWifiChannelsScreen.loraWanPlans
          .where((LoraWanPlan p) => p.verify)
          .map((LoraWanPlan p) => p.plan)
          .toSet();
      expect(verify, <String>{'CN470', 'CN779', 'RU864'});
    });

    test('US915 range is 902-928 MHz', () {
      final LoraWanPlan us = NonWifiChannelsScreen.loraWanPlans
          .firstWhere((LoraWanPlan p) => p.plan == 'US915');
      expect(us.rangeMhz, '902-928');
    });
  });

  group('IEEE 802.15.4 dataset', () {
    test('three bands: 868 MHz, 915 MHz, 2.4 GHz', () {
      expect(
        NonWifiChannelsScreen.ieee802154Bands
            .map((Ieee802154Band b) => b.band),
        <String>['868 MHz', '915 MHz', '2.4 GHz'],
      );
    });

    test('2.4 GHz band is worldwide, channels 11-26', () {
      final Ieee802154Band b = NonWifiChannelsScreen.ieee802154Bands
          .firstWhere((Ieee802154Band b) => b.band == '2.4 GHz');
      expect(b.channels, '11-26');
      expect(b.region, 'Worldwide');
      expect(b.centers, '2405-2480 MHz');
    });

    test('868 and 915 MHz bands are region-restricted', () {
      final Ieee802154Band b868 = NonWifiChannelsScreen.ieee802154Bands
          .firstWhere((Ieee802154Band b) => b.band == '868 MHz');
      final Ieee802154Band b915 = NonWifiChannelsScreen.ieee802154Bands
          .firstWhere((Ieee802154Band b) => b.band == '915 MHz');
      expect(b868.region, 'Europe');
      expect(b915.region, contains('Americas'));
    });
  });

  group('Bluetooth LE dataset', () {
    test('40 channels total: 3 advertising + 37 data', () {
      expect(NonWifiChannelsScreen.bleChannels, hasLength(40));
      final int adv = NonWifiChannelsScreen.bleChannels
          .where((BleChannel c) => c.kind == 'Advertising')
          .length;
      final int data = NonWifiChannelsScreen.bleChannels
          .where((BleChannel c) => c.kind == 'Data')
          .length;
      expect(adv, 3);
      expect(data, 37);
    });

    test('advertising channels 37/38/39 sit at 2402/2426/2480 MHz', () {
      int freqOf(int index) => NonWifiChannelsScreen.bleChannels
          .firstWhere((BleChannel c) => c.index == index)
          .freqMhz;
      expect(freqOf(37), 2402);
      expect(freqOf(38), 2426);
      expect(freqOf(39), 2480);
    });

    test('index→frequency is NON-LINEAR (the naive formula would be wrong)', () {
      // A naive chart would place index 38 at 2402 + 2·38 = 2478 MHz. The real
      // BLE mapping interleaves the advertising channels, so 38 is 2426 MHz.
      final int freq38 = NonWifiChannelsScreen.bleChannels
          .firstWhere((BleChannel c) => c.index == 38)
          .freqMhz;
      expect(freq38, isNot(2402 + 2 * 38));
      expect(freq38, 2426);
    });

    test('data channel piecewise mapping holds (0-10 and 11-36)', () {
      int freqOf(int index) => NonWifiChannelsScreen.bleChannels
          .firstWhere((BleChannel c) => c.index == index)
          .freqMhz;
      // Data 0-10: f = 2404 + 2·index.
      for (int i = 0; i <= 10; i++) {
        expect(freqOf(i), 2404 + 2 * i, reason: 'data index $i');
      }
      // Data 11-36: f = 2406 + 2·index.
      for (int i = 11; i <= 36; i++) {
        expect(freqOf(i), 2406 + 2 * i, reason: 'data index $i');
      }
    });

    test('rows are in ascending physical-frequency order', () {
      final List<int> freqs = NonWifiChannelsScreen.bleChannels
          .map((BleChannel c) => c.freqMhz)
          .toList();
      final List<int> sorted = <int>[...freqs]..sort();
      expect(freqs, sorted);
      // No frequency outside the 2402-2480 MHz BLE band.
      expect(freqs.first, 2402);
      expect(freqs.last, 2480);
    });
  });

  group('Bluetooth Classic dataset', () {
    test('declares 79 channels, 1 MHz spacing, global', () {
      final Map<String, String> facts = <String, String>{
        for (final (String k, String v)
            in NonWifiChannelsScreen.bluetoothClassicFacts)
          k: v,
      };
      expect(facts['Channels'], '79');
      expect(facts['Spacing'], '1 MHz');
      expect(facts['Region'], contains('Global'));
    });
  });

  group('Zigbee dataset', () {
    test('runs on 802.15.4 ch 11-26 at 2.4 GHz', () {
      final Map<String, String> facts = <String, String>{
        for (final (String k, String v) in NonWifiChannelsScreen.zigbeeFacts)
          k: v,
      };
      expect(facts['2.4 GHz band'], contains('11-26'));
      expect(facts['Common 2.4 GHz picks'], contains('convention'));
    });
  });

  group('NonWifiChannelsScreen widget', () {
    testWidgets('renders title and representative rows in a phone viewport', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NonWifiChannelsScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Non-Wi-Fi Wireless Channels'), findsOneWidget);
        // Technology section headings.
        expect(find.text('LoRaWAN'), findsWidgets);
        expect(find.text('Bluetooth LE'), findsWidgets);
        expect(find.text('Zigbee'), findsWidgets);
        // A verified BLE advertising frequency renders.
        expect(find.text('2402'), findsWidgets);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths', (
      WidgetTester tester,
    ) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const NonWifiChannelsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}
