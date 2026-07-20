// Tests for the PRODUCTION channel resolver, resolveUpdateChannel().
//
// WHY THIS FILE EXISTS: every test in app_update_service_test.dart injects a
// fake `resolveChannel`, so the real resolver had zero coverage. A gate mutated
// iOS/Android to `githubReleases` — the exact "App Store install told to
// sideload a .dmg" outcome the spec forbids — and the whole suite still passed.
// These tests target the real function so that mutation dies here.
//
// The platform is driven through `debugDefaultTargetPlatformOverride`, which is
// what `defaultTargetPlatform` reads, so this exercises the genuine switch
// rather than a restatement of it.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/app_update_service.dart';
import 'package:wlan_pros_toolbox/services/update/update_platform_io.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('resolveUpdateChannel — store platforms must NEVER get a GitHub link',
      () {
    test('iOS is store-managed', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(resolveUpdateChannel(), UpdateChannel.managedByStore);
      // Stated twice deliberately: the failure mode this guards against is the
      // value being githubReleases, so name it.
      expect(resolveUpdateChannel(), isNot(UpdateChannel.githubReleases));
    });

    test('Android is store-managed', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(resolveUpdateChannel(), UpdateChannel.managedByStore);
      expect(resolveUpdateChannel(), isNot(UpdateChannel.githubReleases));
    });
  });

  group('resolveUpdateChannel — direct-download platforms', () {
    test('Windows checks GitHub Releases', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(resolveUpdateChannel(), UpdateChannel.githubReleases);
    });

    test('macOS without a Mac App Store receipt checks GitHub Releases', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      // The host running this suite is a Developer ID / dev build, so the
      // receipt probe reports false and the resolver must take the direct
      // branch. Asserted against the probe rather than hardcoded, so this stays
      // true if it is ever run from inside a store-installed bundle.
      final bool hasReceipt = macHasAppStoreReceipt();
      expect(
        resolveUpdateChannel(),
        hasReceipt ? UpdateChannel.managedByStore : UpdateChannel.githubReleases,
      );
    });
  });

  group('resolveUpdateChannel — platforms with no defined channel', () {
    test('Linux claims nothing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(resolveUpdateChannel(), UpdateChannel.none);
    });

    test('Fuchsia claims nothing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      expect(resolveUpdateChannel(), UpdateChannel.none);
    });
  });

  group('resolveUpdateChannel — every platform is decided', () {
    test('no TargetPlatform falls through, and only two get GitHub', () {
      final Map<TargetPlatform, UpdateChannel> resolved =
          <TargetPlatform, UpdateChannel>{};
      for (final TargetPlatform p in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = p;
        resolved[p] = resolveUpdateChannel();
      }
      expect(resolved.length, TargetPlatform.values.length);

      // The security-relevant invariant: the set of platforms allowed to be
      // pointed at a GitHub download is exactly {macOS (direct), windows}.
      final Set<TargetPlatform> github = resolved.entries
          .where((MapEntry<TargetPlatform, UpdateChannel> e) =>
              e.value == UpdateChannel.githubReleases)
          .map((MapEntry<TargetPlatform, UpdateChannel> e) => e.key)
          .toSet();
      expect(
        github,
        macHasAppStoreReceipt()
            ? <TargetPlatform>{TargetPlatform.windows}
            : <TargetPlatform>{TargetPlatform.macOS, TargetPlatform.windows},
        reason: 'a store platform must never resolve to githubReleases',
      );
    });
  });

  group('kIsWeb', () {
    test('web never checks', () {
      // This suite runs on the VM, so kIsWeb is false here and the web branch
      // cannot be reached by overriding the target platform. Assert the
      // precondition honestly rather than pretending to cover the branch: the
      // web path is covered by the conditional-import stub, whose
      // fetchLatestRelease throws rather than silently returning a verdict.
      expect(kIsWeb, isFalse,
          reason: 'these tests run on the VM; see the web stub for that branch');
    });
  });

  group('macHasAppStoreReceipt', () {
    test('returns a bool and never throws on this host', () {
      expect(macHasAppStoreReceipt, returnsNormally);
      expect(macHasAppStoreReceipt(), isA<bool>());
    });

    test('reports false for a Developer ID / dev bundle', () {
      // The bundle running this suite is not store-installed, so the probe must
      // report false. If this ever fails while running from a normal dev
      // checkout, the probe has started producing false positives, which would
      // silently disable the update check for direct-download users.
      expect(macHasAppStoreReceipt(), isFalse);
    });
  });
}
