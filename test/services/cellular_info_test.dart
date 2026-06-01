// CellularInfo model + CellularInfoBridge tests (TICKET-02).
//
// The model parses the companion Shortcut's JSON payload (case-insensitive keys,
// documented human-readable variants, honest nulls, signal-bar clamping). The
// bridge exercises the method-channel calls and their honest
// MissingPluginException fallbacks. No real native side is involved.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CellularInfo.fromMap', () {
    test('parses the canonical key set', () {
      final info = CellularInfo.fromMap(const <String, dynamic>{
        'carrier': 'Verizon',
        'radioTechnology': '5G NR',
        'signalBars': 4,
        'countryCode': 'US',
        'roaming': false,
      });
      expect(info.carrier, 'Verizon');
      expect(info.radioTechnology, '5G NR');
      expect(info.signalBars, 4);
      expect(info.countryCode, 'US');
      expect(info.roaming, isFalse);
      expect(info.hasAnyData, isTrue);
    });

    test('matches keys case-insensitively and tolerates Shortcut variants', () {
      final info = CellularInfo.fromMap(const <String, dynamic>{
        'Carrier Name': 'AT&T',
        'Radio Technology': 'LTE',
        'Number of Signal Bars': '2',
        'Country Code': 'GB',
        'Is Roaming Abroad?': 'Yes',
      });
      expect(info.carrier, 'AT&T');
      expect(info.radioTechnology, 'LTE');
      expect(info.signalBars, 2);
      expect(info.countryCode, 'GB');
      expect(info.roaming, isTrue);
    });

    test('clamps signal bars to the 0..4 status-bar scale', () {
      expect(
        CellularInfo.fromMap(const <String, dynamic>{'signalBars': 9}).signalBars,
        CellularInfo.maxSignalBars,
      );
      expect(
        CellularInfo.fromMap(const <String, dynamic>{'signalBars': 0}).signalBars,
        0,
      );
    });

    test('missing fields are null (honest blanks, never fabricated)', () {
      final info = CellularInfo.fromMap(const <String, dynamic>{
        'carrier': 'T-Mobile',
      });
      expect(info.carrier, 'T-Mobile');
      expect(info.radioTechnology, isNull);
      expect(info.signalBars, isNull);
      expect(info.countryCode, isNull);
      expect(info.roaming, isNull);
    });

    test('an empty map has no data', () {
      expect(CellularInfo.fromMap(const <String, dynamic>{}).hasAnyData, isFalse);
    });
  });

  group('CellularInfo.fromJsonString', () {
    test('parses a JSON object', () {
      final info = CellularInfo.fromJsonString(
        '{"carrier":"Verizon","signalBars":3}',
      );
      expect(info, isNotNull);
      expect(info!.carrier, 'Verizon');
      expect(info.signalBars, 3);
    });

    test('returns null for an empty / non-object / malformed string', () {
      expect(CellularInfo.fromJsonString(''), isNull);
      expect(CellularInfo.fromJsonString('   '), isNull);
      expect(CellularInfo.fromJsonString('[1,2,3]'), isNull);
      expect(CellularInfo.fromJsonString('not json'), isNull);
    });
  });

  group('CellularInfoBridge', () {
    const MethodChannel channel =
        MethodChannel('com.wlanpros.toolbox/shortcuts_bridge');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('readLatest parses the stored cellular JSON', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'readLatestCellular'
            ? '{"carrier":"Verizon","radioTechnology":"5G NR"}'
            : null;
      });
      final info = await CellularInfoBridge().readLatest();
      expect(info, isNotNull);
      expect(info!.carrier, 'Verizon');
      expect(info.radioTechnology, '5G NR');
    });

    test('readLatest returns null when nothing is stored', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await CellularInfoBridge().readLatest(), isNull);
    });

    test('readLatest returns null when the plugin is missing (off-iOS)',
        () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await CellularInfoBridge().readLatest(), isNull);
    });

    test('hasEverReceivedPayload reflects the native cellular flag', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'hasEverReceivedCellularPayload' ? true : null;
      });
      expect(await CellularInfoBridge().hasEverReceivedPayload(), isTrue);
    });

    test('hasEverReceivedPayload defaults to false off-iOS', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await CellularInfoBridge().hasEverReceivedPayload(), isFalse);
    });

    test('openUrl forwards the url and returns success', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });
      final ok = await CellularInfoBridge().openUrl('https://example.com/x');
      expect(ok, isTrue);
      expect(seen!.method, 'openUrl');
      expect(seen!.arguments, 'https://example.com/x');
    });

    test('openUrl returns false when the plugin is missing (off-iOS)',
        () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await CellularInfoBridge().openUrl('https://x'), isFalse);
    });
  });
}
