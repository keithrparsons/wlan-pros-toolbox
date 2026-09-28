// The teaching claims of the Connected, No Internet lesson, pinned on the
// model so the screen cannot drift from them.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/captive_portal_model.dart';

void main() {
  group('both modes', () {
    for (final CaptiveMode mode in CaptiveMode.values) {
      final List<CaptiveStep> steps = captiveSteps(mode);

      test('$mode walks the same five stages in order', () {
        expect(
          steps.map((CaptiveStep s) => s.stage).toList(),
          CaptiveStage.values,
        );
      });

      test('$mode: the Wi-Fi link is up from association on (full bars is '
          'not the same as online)', () {
        expect(steps.first.wifiLinkUp, isTrue);
        expect(steps.first.internet, InternetAccess.held);
      });

      test('$mode: the internet is held at every step before the sign-in', () {
        for (final CaptiveStep s in steps.takeWhile(
          (CaptiveStep s) => s.stage != CaptiveStage.signIn,
        )) {
          expect(s.internet, InternetAccess.held, reason: s.title);
        }
      });

      test('$mode: Wi-Fi Calling cannot connect until the sign-in is done', () {
        for (final CaptiveStep s in steps) {
          final bool afterSignIn = s.stage.index >= CaptiveStage.signIn.index;
          expect(s.wifiCallingCanConnect, afterSignIn, reason: s.title);
        }
      });

      test('$mode: the sign-in sheet opens at the check step', () {
        final CaptiveStep check = steps[CaptiveStage.check.index];
        expect(check.signInSheetOpen, isTrue);
        expect(steps[CaptiveStage.address.index].signInSheetOpen, isFalse);
        expect(steps.last.signInSheetOpen, isFalse);
      });
    }
  });

  test('the person sees the same thing either way (Apple: the experience '
      'looks the same)', () {
    final List<CaptiveStep> a = captiveSteps(CaptiveMode.announced);
    final List<CaptiveStep> b = captiveSteps(CaptiveMode.intercepted);
    for (int i = 0; i < a.length; i++) {
      expect(a[i].onScreen, b[i].onScreen, reason: a[i].title);
      expect(a[i].signInSheetOpen, b[i].signInSheetOpen, reason: a[i].title);
    }
  });

  test('announced: option 114 arrives with the address, and nothing is '
      'intercepted', () {
    final List<CaptiveStep> steps = captiveSteps(CaptiveMode.announced);
    final CaptiveStep address = steps[CaptiveStage.address.index];
    expect(address.announcesPortal, isTrue);
    expect(address.reply, contains('option 114'));
    expect(steps.any((CaptiveStep s) => s.replyIsInterception), isFalse);
    expect(steps[CaptiveStage.check.index].sent, contains('HTTPS'));
  });

  test('intercepted: no announcement, and the probe comes back as the '
      'sign-in page', () {
    final List<CaptiveStep> steps = captiveSteps(CaptiveMode.intercepted);
    expect(steps.any((CaptiveStep s) => s.announcesPortal), isFalse);
    final CaptiveStep check = steps[CaptiveStage.check.index];
    expect(check.replyIsInterception, isTrue);
    expect(check.reply, contains('sign-in page'));
    expect(
      steps.where((CaptiveStep s) => s.replyIsInterception),
      hasLength(1),
    );
  });

  test('no step names an operating system or a vendor (Pax guard: the '
      'lesson stays on the generic probe)', () {
    final RegExp banned = RegExp(
      r'\b(iOS|macOS|Android|Apple|Google|Windows|iPhone|Pixel|Samsung)\b',
    );
    for (final CaptiveMode mode in CaptiveMode.values) {
      for (final CaptiveStep s in captiveSteps(mode)) {
        for (final String text in <String>[
          s.title,
          s.sent,
          s.reply,
          s.onScreen,
          s.explanation,
        ]) {
          expect(banned.hasMatch(text), isFalse, reason: text);
        }
      }
    }
  });
}
