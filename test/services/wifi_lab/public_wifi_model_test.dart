// The teaching claims of the Public Wi-Fi Guided Lesson, one test each. The
// numbered claims are listed in lib/services/wifi_lab/public_wifi_model.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/public_wifi_model.dart';

void main() {
  test('1. HTTPS content is sealed on every network type', () {
    for (final PwNetwork n in PwNetwork.values) {
      expect(pwExposure(n, PwTraffic.httpsContent), PwExposure.sealed,
          reason: n.name);
    }
  });

  test('2. Open shows site names and exposes unencrypted traffic', () {
    expect(pwExposure(PwNetwork.open, PwTraffic.siteNames), PwExposure.visible);
    expect(
      pwExposure(PwNetwork.open, PwTraffic.unencrypted),
      PwExposure.readable,
    );
    expect(pwAirEncrypted(PwNetwork.open), isFalse);
  });

  test('3. Enhanced Open seals the air with no password and shows no lock', () {
    const PwNetwork n = PwNetwork.enhancedOpen;
    expect(pwAirEncrypted(n), isTrue);
    expect(pwOwnKey(n), isTrue);
    expect(pwNeedsPassword(n), isFalse);
    expect(pwShowsLock(n), isFalse);
    expect(pwExposure(n, PwTraffic.siteNames), PwExposure.sealed);
    expect(pwExposure(n, PwTraffic.unencrypted), PwExposure.sealed);
  });

  test('4. WPA2-Personal does not hide you from someone with the password', () {
    const PwNetwork n = PwNetwork.wpa2Personal;
    expect(pwShowsLock(n), isTrue);
    expect(pwOwnKey(n), isFalse);
    // To a bystander who holds the password, the air reads as Open.
    for (final PwTraffic t in PwTraffic.values) {
      expect(pwExposure(n, t), pwExposure(PwNetwork.open, t), reason: t.name);
    }
  });

  test('5. WPA3-Personal gives each device its own key', () {
    const PwNetwork n = PwNetwork.wpa3Personal;
    expect(pwOwnKey(n), isTrue);
    expect(pwShowsLock(n), isTrue);
    expect(pwExposure(n, PwTraffic.siteNames), PwExposure.sealed);
    expect(pwExposure(n, PwTraffic.unencrypted), PwExposure.sealed);
  });

  test('6. presence is visible on every type: the header is never encrypted',
      () {
    for (final PwNetwork n in PwNetwork.values) {
      expect(pwExposure(n, PwTraffic.presence), PwExposure.visible,
          reason: n.name);
    }
  });

  test('nothing is ever marked readable except unencrypted traffic', () {
    for (final PwNetwork n in PwNetwork.values) {
      for (final PwTraffic t in PwTraffic.values) {
        if (t != PwTraffic.unencrypted) {
          expect(pwExposure(n, t), isNot(PwExposure.readable),
              reason: '${n.name} ${t.name}');
        }
      }
    }
  });

  test('the two controls resolve to the four network types', () {
    expect(pwNetworkFor(PwKind.open, PwPassword.wpa3), PwNetwork.open);
    expect(
      pwNetworkFor(PwKind.enhancedOpen, PwPassword.wpa2),
      PwNetwork.enhancedOpen,
    );
    expect(
      pwNetworkFor(PwKind.password, PwPassword.wpa2),
      PwNetwork.wpa2Personal,
    );
    expect(
      pwNetworkFor(PwKind.password, PwPassword.wpa3),
      PwNetwork.wpa3Personal,
    );
    expect(pwView(PwNetwork.open).keys.toList(), PwTraffic.values);
  });
}
