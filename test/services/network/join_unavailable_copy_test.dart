// The two unavailable states must never collapse into one.
//
// 1.9.0 said "Coming to this device" on every platform. That came true on macOS
// and Windows. On iOS it never will, and on Android it is not coming in this
// release, so shipping it again would have been a promise known to be false as
// it was made. These tests exist so it cannot come back.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend_selector.dart';

String _ios() =>
    joinUnavailableBody(isWeb: false, isIOS: true, isAndroid: false);
String _android() =>
    joinUnavailableBody(isWeb: false, isIOS: false, isAndroid: true);
String _other() =>
    joinUnavailableBody(isWeb: false, isIOS: false, isAndroid: false);

void main() {
  group('the false promise is gone', () {
    test('no platform is told this is "coming to this device"', () {
      for (final String body in <String>[_ios(), _android(), _other()]) {
        expect(body.toLowerCase(), isNot(contains('coming to this device')));
      }
      for (final String title in <String>[
        joinUnavailableTitle(isWeb: false, isIOS: true, isAndroid: false),
        joinUnavailableTitle(isWeb: false, isIOS: false, isAndroid: true),
        joinUnavailableTitle(isWeb: false, isIOS: false, isAndroid: false),
      ]) {
        expect(title.toLowerCase(), isNot(contains('coming to this device')));
      }
    });
  });

  group('iOS: permanent, and NOT the app\'s fault', () {
    test('says the OS is the reason, not the app', () {
      expect(_ios(), contains('iOS does not let an app'));
    });

    test('does NOT promise it is being built or coming', () {
      final String b = _ios().toLowerCase();
      expect(b, isNot(contains('being built')));
      expect(b, isNot(contains('not yet')));
      expect(b, isNot(contains('is coming')));
    });

    test('says plainly it is not expected to change', () {
      expect(_ios(), contains('not expected to change'));
    });
  });

  group('Android: scoped out, NOT impossible', () {
    test('does NOT claim it cannot be done', () {
      final String b = _android().toLowerCase();
      expect(b, isNot(contains('cannot')));
      expect(b, isNot(contains('not possible')));
      expect(b, isNot(contains('does not let')));
    });

    test('says it IS possible and has not been ruled out', () {
      expect(_android(), contains('possible on Android'));
      expect(_android(), contains('not been ruled out'));
    });

    test('scopes the absence to THIS release, not forever', () {
      expect(_android(), contains('not part of this release'));
    });
  });

  group('the two are genuinely different sentences', () {
    test('iOS and Android bodies do not match', () {
      expect(_ios(), isNot(equals(_android())));
    });

    test('iOS and Android titles do not match', () {
      expect(
        joinUnavailableTitle(isWeb: false, isIOS: true, isAndroid: false),
        isNot(
          equals(
            joinUnavailableTitle(isWeb: false, isIOS: false, isAndroid: true),
          ),
        ),
      );
    });

    test(
      'the iOS reason never appears in the Android copy, and vice versa',
      () {
        expect(_android(), isNot(contains('iOS does not let an app')));
        expect(_ios(), isNot(contains('not been ruled out')));
      },
    );
  });

  group('every case still tells the user what DOES work', () {
    test('all three point at the WLAN Pi', () {
      for (final String body in <String>[_ios(), _android(), _other()]) {
        expect(body, contains('WLAN Pi'));
        expect(body, contains('Every other tool works normally here.'));
      }
    });
  });
}
