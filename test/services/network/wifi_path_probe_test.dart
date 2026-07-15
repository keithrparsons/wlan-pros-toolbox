// MethodChannelWifiPathProbe — the native payload boundary.
//
// WHY THIS FILE EXISTS (round-4 review, K25). Every line of this class survived the
// full 4,181-test suite when mutated. The whole class was zero-coverage, and one of
// its lines is genuinely dangerous:
//
//     if (payload['available'] != true) return null;   // wifi_path_probe.dart
//
// DELETE THAT LINE and an HONEST-UNAVAILABLE payload — the one the native side sends
// when its NWPathMonitor has not reported a path yet, i.e. on COLD START — parses
// into `WifiPathFacts(usesWifi: false, wifiSatisfied: false, wifiInterfacePresent:
// false)`. That is the exact shape [WifiConnectionService] reads as a DEFINITIVE
// `notOnWifi`.
//
// So a connected user, on Wi-Fi, opening the app before the monitor's first callback
// lands, would be told they have no Wi-Fi and have their live link torn down. That is
// the round-2 bug class — a false negative manufactured from missing data — sitting
// one edit away, held correct by nothing but the line itself.
//
// `available: false` means "iOS DID NOT ANSWER". It is not a verdict, and it must
// never become one. It has to arrive in Dart as `null`, so the caller falls back.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

const MethodChannel _channel =
    MethodChannel('com.wlanpros.toolbox/wifi_security');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Scripts the native side's reply to `getWifiPath`. [reply] of null models a
  /// channel that answers with nothing.
  void scriptNative(Object? reply, {bool throwIt = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      expect(call.method, 'getWifiPath');
      if (throwIt) throw PlatformException(code: 'boom');
      return reply;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  const MethodChannelWifiPathProbe probe = MethodChannelWifiPathProbe();

  group('the honest-unavailable payload must NEVER become a verdict (K25)', () {
    test('available:false -> null, NOT a no-Wi-Fi verdict', () async {
      // THE COLD-START PAYLOAD. The native monitor had not reported a path before
      // its deadline, so it answered honestly rather than guessing.
      scriptNative(<String, Object?>{
        'available': false,
        'usesWifi': false,
        'wifiSatisfied': false,
        'wifiInterfacePresent': false,
      });

      expect(
        await probe.read(),
        isNull,
        reason: 'available:false means "iOS did not answer". If this parses into '
            'WifiPathFacts(false,false,false) instead of null, the service reads it '
            'as a DEFINITIVE notOnWifi and tells a connected user on cold start that '
            'they have no Wi-Fi. That is a false negative built out of missing data '
            '— the exact class of bug this whole effort exists to delete.',
      );
    });

    test('a MISSING `available` key -> null (never assume it answered)', () async {
      scriptNative(<String, Object?>{'usesWifi': true});
      expect(await probe.read(), isNull);
    });

    test('a null reply -> null', () async {
      scriptNative(null);
      expect(await probe.read(), isNull);
    });

    test('a thrown platform error -> null, never a verdict', () async {
      // MissingPluginException off iOS lands here too.
      scriptNative(null, throwIt: true);
      expect(await probe.read(), isNull);
    });
  });

  group('an available payload parses its three facts faithfully', () {
    test('available:true carries the facts through', () async {
      scriptNative(<String, Object?>{
        'available': true,
        'usesWifi': true,
        'wifiSatisfied': true,
        'wifiInterfacePresent': true,
      });

      final WifiPathFacts? facts = await probe.read();
      expect(facts, isNotNull);
      expect(facts!.usesWifi, isTrue);
      expect(facts.wifiSatisfied, isTrue);
      expect(facts.wifiInterfacePresent, isTrue);
    });

    test('each fact is read INDEPENDENTLY (no field is wired to another)',
        () async {
      // Without this, three separate `payload['x'] == true` reads could all be
      // sourced from one key and every test above would still pass. Each flag is
      // given a distinct value so a crossed wire is visible.
      scriptNative(<String, Object?>{
        'available': true,
        'usesWifi': false,
        'wifiSatisfied': false,
        'wifiInterfacePresent': true, // the radio-on-unassociated shape
      });

      final WifiPathFacts? facts = await probe.read();
      expect(facts, isNotNull);
      expect(facts!.usesWifi, isFalse);
      expect(facts.wifiSatisfied, isFalse);
      expect(facts.wifiInterfacePresent, isTrue);
    });

    test('a missing flag reads FALSE, never true (absence is not a Wi-Fi link)',
        () async {
      scriptNative(<String, Object?>{'available': true});
      final WifiPathFacts? facts = await probe.read();
      expect(facts, isNotNull);
      expect(facts!.usesWifi, isFalse);
      expect(facts.wifiSatisfied, isFalse);
      expect(facts.wifiInterfacePresent, isFalse);
    });
  });
}
