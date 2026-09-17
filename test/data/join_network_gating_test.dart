// Join a Network is offered ONLY where something present can actually join.
//
// REWRITTEN 2026-09-17 when macOS native join landed. The previous version
// asserted the opposite on this host and FAILED LOUDLY the moment the Mac
// gained a native path, which is exactly what it was written to do. Its
// precondition test said so in as many words. This version asserts the new
// truth rather than being edited until it went green.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend_selector.dart';

void main() {
  group('this host joins with its own radio', () {
    test('precondition: macOS is a native join platform', () {
      expect(
        deviceCanJoinNatively,
        isTrue,
        reason:
            'these tests run on macOS, which Keith scoped in on '
            '2026-09-06; if this ever goes false the assertions below are '
            'testing the wrong branch',
      );
    });

    test('join-network is NOT flagged unavailable here', () {
      expect(toolUnavailableOnWeb('join-network'), isFalse);
      expect(toolUnavailableReason('join-network'), isNull);
    });

    test('it is STILL IN kPiOnlyToolIds, not deleted from it', () {
      // Deleting it would ungate it on iOS and Android too, where nothing can
      // join, and the tile would offer a screen that cannot work. The set stays
      // honest; the exception is conditional and names one tool.
      expect(kPiOnlyToolIds, contains('join-network'));
    });

    test('no OTHER Pi-only tool was loosened by the exception', () {
      for (final String id in kPiOnlyToolIds) {
        if (id == 'join-network') continue;
        expect(
          toolUnavailableOnWeb(id),
          isTrue,
          reason: '$id must keep its Pi gate',
        );
      }
    });

    test('a tool that was never Pi-gated is unaffected', () {
      expect(toolUnavailableReason('shannon-capacity'), isNull);
    });
  });
}
