import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';

void main() {
  group('WifiSecurityClassifier — token mapping', () {
    test('null and blank tokens classify to null (no row to render)', () {
      expect(WifiSecurityClassifier.classify(null), isNull);
      expect(WifiSecurityClassifier.classify(''), isNull);
      expect(WifiSecurityClassifier.classify('   '), isNull);
    });

    test('shared tokens map across platforms', () {
      expect(WifiSecurityClassifier.classify('open'), WifiSecurity.open);
      expect(WifiSecurityClassifier.classify('none'), WifiSecurity.open);
      expect(WifiSecurityClassifier.classify('wep'), WifiSecurity.wep);
      expect(WifiSecurityClassifier.classify('dynamicWEP'), WifiSecurity.wep);
      expect(WifiSecurityClassifier.classify('owe'), WifiSecurity.owe);
      expect(
        WifiSecurityClassifier.classify('oweTransition'),
        WifiSecurity.owe,
      );
      expect(WifiSecurityClassifier.classify('unknown'), WifiSecurity.unknown);
    });

    test('iOS COARSE tokens map to the coarse cases — never a specific WPA3', () {
      // This is the Truthfulness-Audit guard: iOS .personal must NOT become a
      // WPA2/WPA3-specific label.
      final WifiSecurity? personal =
          WifiSecurityClassifier.classify('personal');
      expect(personal, WifiSecurity.personalCoarse);
      expect(personal!.isPersonalCoarse, isTrue);
      expect(personal.label, 'Personal (WPA/WPA2/WPA3-PSK)');
      expect(personal.label.contains('WPA3 Personal'), isFalse);

      final WifiSecurity? enterprise =
          WifiSecurityClassifier.classify('enterprise');
      expect(enterprise, WifiSecurity.enterpriseCoarse);
      expect(enterprise!.isEnterpriseCoarse, isTrue);
    });

    test('macOS FINE Personal tokens map to specific cases', () {
      expect(
        WifiSecurityClassifier.classify('wpaPersonal'),
        WifiSecurity.wpaPersonal,
      );
      expect(
        WifiSecurityClassifier.classify('wpaPersonalMixed'),
        WifiSecurity.wpaPersonal,
      );
      expect(
        WifiSecurityClassifier.classify('wpa2Personal'),
        WifiSecurity.wpa2Personal,
      );
      expect(
        WifiSecurityClassifier.classify('wpa3Personal'),
        WifiSecurity.wpa3Personal,
      );
      expect(
        WifiSecurityClassifier.classify('wpa3Transition'),
        WifiSecurity.wpa3Transition,
      );
    });

    test('macOS FINE Enterprise tokens map to specific cases', () {
      expect(
        WifiSecurityClassifier.classify('wpaEnterprise'),
        WifiSecurity.wpaEnterprise,
      );
      expect(
        WifiSecurityClassifier.classify('wpaEnterpriseMixed'),
        WifiSecurity.wpaEnterprise,
      );
      expect(
        WifiSecurityClassifier.classify('wpa2Enterprise'),
        WifiSecurity.wpa2Enterprise,
      );
      expect(
        WifiSecurityClassifier.classify('wpa3Enterprise'),
        WifiSecurity.wpa3Enterprise,
      );
    });

    test('classification is case-insensitive', () {
      expect(WifiSecurityClassifier.classify('WPA2PERSONAL'),
          WifiSecurity.wpa2Personal);
      expect(WifiSecurityClassifier.classify('Open'), WifiSecurity.open);
    });

    test('an unrecognized token maps to unknown, never a guess', () {
      expect(
        WifiSecurityClassifier.classify('wpa9quantum'),
        WifiSecurity.unknown,
      );
    });

    test('coarse flags are false for the fine macOS cases', () {
      expect(WifiSecurity.wpa3Personal.isPersonalCoarse, isFalse);
      expect(WifiSecurity.wpa2Enterprise.isEnterpriseCoarse, isFalse);
    });

    test('label() returns the human label or null', () {
      expect(WifiSecurityClassifier.label('wpa3Transition'),
          'WPA2/WPA3 Transition');
      expect(WifiSecurityClassifier.label(null), isNull);
    });
  });
}
