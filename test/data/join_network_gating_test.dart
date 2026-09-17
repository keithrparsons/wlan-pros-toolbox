// Join a Network is ungated ONLY where the device can join with its own radio.
//
// These run on macOS, where deviceCanJoinNatively is false, so they pin the
// SAFETY half: everywhere without a native path, the tool still says it needs a
// WLAN Pi. That is the half that would hurt if it broke, because the failure is
// a tile offering a screen that cannot work.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend_selector.dart';

void main() {
  group('the Pi gate survives everywhere the device cannot join itself', () {
    test('this test host cannot join natively, which is what makes the rest '
        'of this group meaningful', () {
      expect(
        deviceCanJoinNatively,
        isFalse,
        reason:
            'these tests run on macOS; if this ever passes, the '
            'assertions below are testing the wrong branch',
      );
    });

    test('join-network still needs a WLAN Pi here', () {
      expect(toolUnavailableOnWeb('join-network'), isTrue);
      expect(
        toolUnavailableReason('join-network'),
        ToolUnavailableReason.needsWlanPi,
      );
    });

    test('join-network is STILL IN kPiOnlyToolIds, not deleted from it', () {
      // Removing it outright would ungate it on iOS and Android too, where
      // nothing can join. The set stays honest; the exception is conditional.
      expect(kPiOnlyToolIds, contains('join-network'));
    });

    test(
      'the exception names ONE tool, so no other Pi-only tool is loosened',
      () {
        for (final String id in kPiOnlyToolIds) {
          if (id == 'join-network') continue;
          expect(
            toolUnavailableOnWeb(id),
            isTrue,
            reason: '$id must keep its Pi gate',
          );
        }
      },
    );

    test('a tool that was never Pi-gated is unaffected', () {
      expect(toolUnavailableReason('shannon-capacity'), isNull);
    });
  });
}
