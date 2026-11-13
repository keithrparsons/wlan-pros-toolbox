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
}
