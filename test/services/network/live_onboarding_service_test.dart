// LiveOnboardingService — unit tests for the one-time first-run gate.
//
// The service owns ONE honest signal (the persisted "onboarding seen" flag) and
// composes it with the caller-supplied hasEverReceivedPayload signal to decide
// whether the unmissable first-run "enable live Wi-Fi" sheet should fire. These
// tests drive it through the injected SharedPreferences store seam so no real
// platform channel is touched, and cover:
//   * brand-new user (never received a payload, never seen the sheet) → SHOW;
//   * a user who has the Shortcut working (ever-received) → never show, even if
//     the sheet was never persisted (the honest App Group signal wins);
//   * a user already shown the sheet → never show again (one-time);
//   * markOnboardingSeen persists so a second call resolves false;
//   * a storage READ failure degrades to "treat as seen" (never spam the sheet);
//   * a storage WRITE failure is swallowed (no crash).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';

/// A store getter that always throws, modeling a broken SharedPreferences.
Future<SharedPreferences> _throwingStore() =>
    throw StateError('storage unavailable');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiveOnboardingService — composite gate', () {
    test('brand-new user (never received, never seen) → SHOW', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final svc = LiveOnboardingService(getStore: SharedPreferences.getInstance);

      expect(await svc.hasSeenOnboarding(), isFalse);
      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: false),
        isTrue,
      );
    });

    test(
        'a user with the Shortcut working (ever-received) never onboards — the '
        'honest App Group signal wins even when the seen-flag was never set',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final svc = LiveOnboardingService(getStore: SharedPreferences.getInstance);

      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: true),
        isFalse,
      );
    });

    test('a user already shown the sheet never sees it again (one-time)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final svc = LiveOnboardingService(getStore: SharedPreferences.getInstance);

      expect(await svc.hasSeenOnboarding(), isTrue);
      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: false),
        isFalse,
      );
    });

    test('markOnboardingSeen persists → a later shouldShow resolves false',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final svc = LiveOnboardingService(getStore: SharedPreferences.getInstance);

      // First open: SHOW.
      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: false),
        isTrue,
      );
      // The screen marks it seen the instant the sheet is presented.
      await svc.markOnboardingSeen();
      // Second open (still no payload): never again.
      expect(await svc.hasSeenOnboarding(), isTrue);
      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: false),
        isFalse,
      );
    });
  });

  group('LiveOnboardingService — cross-screen latch (the re-prompt bug)', () {
    // Regression for the iOS bug where installing the "WLAN Pros Live" Shortcut
    // from one live tool left OTHER live tools prompting to install it AGAIN in
    // the window before the first Live payload arrived. The fix marks the global
    // seen-flag the moment the user taps "I've added it" (onInstalled), so any
    // other screen — represented here by a SECOND service instance over the same
    // persisted store — treats onboarding as done immediately, with no payload.
    test(
        'after onInstalled marks seen on screen A, screen B does not auto-prompt '
        '(hasEverReceivedPayload still false)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Screen A: brand-new user opens a live tool and would be onboarded.
      final screenA =
          LiveOnboardingService(getStore: SharedPreferences.getInstance);
      expect(
        await screenA.shouldShowOnboarding(hasEverReceivedPayload: false),
        isTrue,
      );

      // User taps "I've added it" → onInstalled persists the global flag.
      await screenA.markOnboardingSeen();

      // Screen B is a DIFFERENT instance (a different live screen) sharing the
      // same persisted store, opened before any Live payload has arrived.
      final screenB =
          LiveOnboardingService(getStore: SharedPreferences.getInstance);
      expect(
        await screenB.shouldShowOnboarding(hasEverReceivedPayload: false),
        isFalse,
        reason: 'second live tool must not re-prompt before first payload',
      );
    });
  });

  group('LiveOnboardingService — storage faults degrade safely', () {
    test('a READ failure resolves to "seen" so a broken store never nags',
        () async {
      final svc = LiveOnboardingService(getStore: _throwingStore);

      expect(await svc.hasSeenOnboarding(), isTrue);
      expect(
        await svc.shouldShowOnboarding(hasEverReceivedPayload: false),
        isFalse,
      );
    });

    test('a WRITE failure is swallowed (no throw)', () async {
      final svc = LiveOnboardingService(getStore: _throwingStore);

      await expectLater(svc.markOnboardingSeen(), completes);
    });
  });
}
