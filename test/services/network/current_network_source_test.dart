// The fallback must not be silent - the sandbox honesty contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';

void main() {
  group('linkMayBeWrong: the gate for the visible warning', () {
    const NetworkSuggestion routed = NetworkSuggestion(
      cidr: '192.168.8.0/24',
      gatewayIp: '192.168.8.1',
      deviceIp: '192.168.8.233',
      maskWasReal: true,
      source: NetworkSource.routingTable,
      multiHomed: true,
    );
    const NetworkSuggestion fallbackMulti = NetworkSuggestion(
      cidr: '192.168.8.0/24',
      gatewayIp: '192.168.8.1',
      deviceIp: '192.168.8.134',
      maskWasReal: true,
      source: NetworkSource.wifiInterface,
      multiHomed: true,
    );
    const NetworkSuggestion fallbackSingle = NetworkSuggestion(
      cidr: '192.168.8.0/24',
      gatewayIp: '192.168.8.1',
      deviceIp: '192.168.8.134',
      maskWasReal: true,
      source: NetworkSource.wifiInterface,
      multiHomed: false,
    );

    test('the routing table answered, so there is nothing to warn about', () {
      expect(routed.linkMayBeWrong, isFalse);
    });

    test('THE CASE THAT MATTERS: fell back AND more than one link exists', () {
      // The App Store Mac with an Ethernet adapter. The probe was denied, the
      // plugin matched on the name en0, and the user is looking at the Wi-Fi
      // subnet while plugged into something else.
      expect(fallbackMulti.linkMayBeWrong, isTrue);
      expect(fallbackMulti.linkWarning, isNotEmpty);
      expect(fallbackMulti.linkWarning, contains('cable'));
    });

    test('a PHONE is not warned, because the plugin is right there', () {
      // An iPhone has no wired NIC to confuse the read. Warning here would be
      // noise, and noise is how a real warning stops being read.
      expect(fallbackSingle.linkMayBeWrong, isFalse);
    });

    test('no cidr means no warning: there is nothing to be wrong about', () {
      expect(
        const NetworkSuggestion(
          cidr: null,
          gatewayIp: null,
          deviceIp: null,
          maskWasReal: false,
          source: NetworkSource.wifiInterface,
          multiHomed: true,
        ).linkMayBeWrong,
        isFalse,
      );
    });

    test('the NONE constant claims nothing about its source', () {
      expect(NetworkSuggestion.none.source, NetworkSource.none);
      expect(NetworkSuggestion.none.linkMayBeWrong, isFalse);
    });

    test('an unstamped suggestion claims nothing either way', () {
      // Every injected reader (all tests, and the Pi path) leaves the source
      // unset. That must not read as a verified link OR as a warning.
      const NetworkSuggestion s = NetworkSuggestion(
        cidr: '10.0.0.0/24',
        gatewayIp: '10.0.0.1',
        deviceIp: '10.0.0.5',
        maskWasReal: true,
      );
      expect(s.source, NetworkSource.none);
      expect(s.linkMayBeWrong, isFalse);
    });
  });

  group('the two honesty flags are independent', () {
    test('an assumed prefix and an unverified link are different problems', () {
      const NetworkSuggestion both = NetworkSuggestion(
        cidr: '192.168.8.0/24',
        gatewayIp: '192.168.8.1',
        deviceIp: '192.168.8.134',
        maskWasReal: false,
        source: NetworkSource.wifiInterface,
        multiHomed: true,
      );
      // "we guessed the size of your network" and "we may have named the wrong
      // network" can both be true, and a UI collapsing them into one hint
      // would drop half the message.
      expect(both.isAssumedPrefix, isTrue);
      expect(both.linkMayBeWrong, isTrue);
    });
  });
}
