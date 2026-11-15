import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/widgets/router_note.dart';

void main() {
  group('firstHopSilentButPathAnswers', () {
    test('true when hop 1 is silent and a later hop answers', () {
      expect(firstHopSilentButPathAnswers(<bool>[false, true]), isTrue);
      expect(firstHopSilentButPathAnswers(<bool>[false, false, true]), isTrue);
    });

    test('false when hop 1 answers', () {
      expect(firstHopSilentButPathAnswers(<bool>[true, true]), isFalse);
      expect(firstHopSilentButPathAnswers(<bool>[true, false]), isFalse);
    });

    test('false when nothing past hop 1 answers', () {
      expect(firstHopSilentButPathAnswers(<bool>[false]), isFalse);
      expect(firstHopSilentButPathAnswers(<bool>[false, false]), isFalse);
    });

    test('false with no hops yet', () {
      expect(firstHopSilentButPathAnswers(<bool>[]), isFalse);
    });
  });

  group('routerSilentToPing', () {
    bool silent(String target, String? gateway, int sent, int received) =>
        routerSilentToPing(
          target: target,
          gatewayIp: gateway,
          sent: sent,
          received: received,
        );

    test('true when the router got 3 or more pings and answered none', () {
      expect(silent('192.168.1.1', '192.168.1.1', 3, 0), isTrue);
      expect(silent(' 192.168.1.1 ', '192.168.1.1', 10, 0), isTrue);
    });

    test('false when the router answered any ping', () {
      expect(silent('192.168.1.1', '192.168.1.1', 10, 1), isFalse);
    });

    test('false for a target that is not the router', () {
      expect(silent('1.1.1.1', '192.168.1.1', 10, 0), isFalse);
      expect(silent('192.168.1.1', null, 10, 0), isFalse);
    });

    test('false until 3 pings have gone unanswered', () {
      expect(silent('192.168.1.1', '192.168.1.1', 2, 0), isFalse);
    });
  });
}
