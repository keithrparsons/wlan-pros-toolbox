// Tests for the About-screen update check.
//
// Two halves:
//   1. ReleaseVersion — the comparator. The headline case is 1.10.0 > 1.9.0,
//      which a string compare gets backwards and which would tell a user on the
//      newest build to "update" to an older one.
//   2. AppUpdateService — every failure mode must degrade to `unknown`, never to
//      `upToDate`. A false "you are up to date" is the one answer this feature
//      must never invent.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/app_update_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';

/// A release payload shaped like the live GitHub response (verified against
/// `gh api repos/walnprosgithub/toolbox-wlanpros-site/releases/latest`, which
/// returns tag_name `v1.8.1` and an html_url on the releases/tag/ path).
Map<String, dynamic> releaseJson(String tag) => <String, dynamic>{
      'tag_name': tag,
      'html_url':
          'https://github.com/walnprosgithub/toolbox-wlanpros-site/releases/tag/$tag',
      'name': 'WLAN Pros Toolbox (macOS)',
    };

/// Build a service pinned to the direct-download channel with a scripted
/// fetcher and a clean preference store.
AppUpdateService serviceWith(ReleaseFetcher fetcher) => AppUpdateService(
      fetcher: fetcher,
      resolveChannel: () => UpdateChannel.githubReleases,
      getStore: SharedPreferences.getInstance,
    );

void main() {
  setUp(() {
    // Fresh, empty store per test so a cached answer never leaks across tests.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ReleaseVersion.tryParse', () {
    test('parses a plain version', () {
      final ReleaseVersion? v = ReleaseVersion.tryParse('1.8.1');
      expect(v, isNotNull);
      expect(v!.components, <int>[1, 8, 1]);
      expect(v.preRelease, isNull);
    });

    test('accepts a leading v or V, as git tags carry', () {
      expect(ReleaseVersion.tryParse('v1.8.1')?.toString(), '1.8.1');
      expect(ReleaseVersion.tryParse('V1.8.1')?.toString(), '1.8.1');
    });

    test('tolerates surrounding whitespace', () {
      expect(ReleaseVersion.tryParse('  v1.8.1  ')?.toString(), '1.8.1');
    });

    test('discards +build metadata, which is not part of precedence', () {
      final ReleaseVersion? v = ReleaseVersion.tryParse('1.8.1+26071901');
      expect(v?.components, <int>[1, 8, 1]);
      expect(ReleaseVersion.tryParse('1.8.1+26071901'),
          ReleaseVersion.tryParse('1.8.1'));
    });

    test('splits a pre-release tail', () {
      final ReleaseVersion? v = ReleaseVersion.tryParse('1.9.0-beta.1');
      expect(v?.components, <int>[1, 9, 0]);
      expect(v?.preRelease, 'beta.1');
    });

    test('accepts a two-component version', () {
      expect(ReleaseVersion.tryParse('1.8')?.components, <int>[1, 8]);
    });

    test('returns null for malformed or missing input instead of throwing', () {
      for (final String? bad in <String?>[
        null,
        '',
        '   ',
        'v',
        'latest',
        'not-a-version',
        '1.8.x',
        '1..8',
        '1.8.',
        '.1.8',
        '-1.8',
        '1.8.1.2.3', // more components than we accept
        '99999999999.0.0', // absurdly long component
        '1.٨.1', // non-ASCII digits must not be reinterpreted
      ]) {
        expect(ReleaseVersion.tryParse(bad), isNull, reason: 'input: $bad');
      }
    });
  });

  group('ReleaseVersion.compareTo', () {
    test('1.10.0 is NEWER than 1.9.0 (the string-compare trap)', () {
      final ReleaseVersion a = ReleaseVersion.tryParse('1.10.0')!;
      final ReleaseVersion b = ReleaseVersion.tryParse('1.9.0')!;
      expect(a.compareTo(b), greaterThan(0));
      expect(b.compareTo(a), lessThan(0));
      // Confirm the naive comparison really would have been wrong.
      expect('1.10.0'.compareTo('1.9.0'), lessThan(0));
    });

    test('1.9.0 is newer than 1.8.10', () {
      expect(
        ReleaseVersion.tryParse('1.9.0')!
            .compareTo(ReleaseVersion.tryParse('1.8.10')!),
        greaterThan(0),
      );
    });

    test('2.0.0 is newer than 1.99.99', () {
      expect(
        ReleaseVersion.tryParse('2.0.0')!
            .compareTo(ReleaseVersion.tryParse('1.99.99')!),
        greaterThan(0),
      );
    });

    test('equal versions compare equal regardless of a v prefix', () {
      expect(
        ReleaseVersion.tryParse('v1.8.1')!
            .compareTo(ReleaseVersion.tryParse('1.8.1')!),
        0,
      );
    });

    test('missing trailing components read as zero: 1.8 == 1.8.0', () {
      expect(
        ReleaseVersion.tryParse('1.8')!
            .compareTo(ReleaseVersion.tryParse('1.8.0')!),
        0,
      );
      expect(
        ReleaseVersion.tryParse('1.8.1')!
            .compareTo(ReleaseVersion.tryParse('1.8')!),
        greaterThan(0),
      );
    });

    test('a pre-release ranks below the matching final release', () {
      expect(
        ReleaseVersion.tryParse('1.9.0-beta.1')!
            .compareTo(ReleaseVersion.tryParse('1.9.0')!),
        lessThan(0),
      );
      expect(
        ReleaseVersion.tryParse('1.9.0')!
            .compareTo(ReleaseVersion.tryParse('1.9.0-beta.1')!),
        greaterThan(0),
      );
    });

    test('a pre-release of a higher version still outranks a lower final', () {
      expect(
        ReleaseVersion.tryParse('1.9.0-beta.1')!
            .compareTo(ReleaseVersion.tryParse('1.8.1')!),
        greaterThan(0),
      );
    });
  });

  group('AppUpdateService — verdicts', () {
    test('same version reports up to date', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => releaseJson('v1.8.1'),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.upToDate);
    });

    test('newer published version reports an update with version and URL',
        () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => releaseJson('v1.9.0'),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.updateAvailable);
      expect(r.latestVersion, '1.9.0');
      expect(r.releaseUrl, contains('releases/tag/v1.9.0'));
    });

    test('1.10.0 published against 1.9.0 running is an update, not up to date',
        () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => releaseJson('v1.10.0'),
      ).check(currentVersion: '1.9.0');
      expect(r.status, AppUpdateStatus.updateAvailable);
      expect(r.latestVersion, '1.10.0');
    });

    test('a running build AHEAD of the release feed reports up to date',
        () async {
      // A local/dev build newer than the last published tag must not be told to
      // "update" backwards.
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => releaseJson('v1.8.1'),
      ).check(currentVersion: '1.9.0');
      expect(r.status, AppUpdateStatus.upToDate);
    });
  });

  group('AppUpdateService — failure modes all degrade to unknown', () {
    test('offline (SocketException surfaced as a transport error)', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.transport,
          'Could not reach the lookup API: Network is unreachable.',
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
      expect(r.latestVersion, isNull);
    });

    test('DNS blocked', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.transport,
          'Failed host lookup: api.github.com',
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('timeout', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.timeout,
          'The lookup timed out after 8s.',
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('rate limited (unauthenticated GitHub allows 60 req/hr/IP)', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.rateLimited,
          'rate limited',
          statusCode: 429,
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('HTTP 404 (repo renamed, or no release published yet)', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.httpStatus,
          'The lookup API returned HTTP 404.',
          statusCode: 404,
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('malformed JSON body', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw const JsonHttpException(
          JsonHttpErrorKind.badJson,
          'The lookup API returned a response that was not valid JSON.',
        ),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('valid JSON but no tag_name field', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => <String, dynamic>{'name': 'a release'},
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('tag_name present but not a string', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => <String, dynamic>{'tag_name': 42},
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('tag_name present but unparseable', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => releaseJson('nightly'),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('an unexpected non-JsonHttpException still degrades quietly', () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => throw StateError('anything at all'),
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.unknown);
    });

    test('an unparseable RUNNING version claims nothing', () async {
      bool fetched = false;
      final AppUpdateResult r = await serviceWith((Duration _) async {
        fetched = true;
        return releaseJson('v1.9.0');
      }).check(currentVersion: 'unknown');
      expect(r.status, AppUpdateStatus.unknown);
      expect(fetched, isFalse, reason: 'no point spending a request');
    });

    test('a missing html_url falls back to the releases page, not failure',
        () async {
      final AppUpdateResult r = await serviceWith(
        (Duration _) async => <String, dynamic>{'tag_name': 'v1.9.0'},
      ).check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.updateAvailable);
      expect(r.releaseUrl, kReleasesPageUrl);
    });
  });

  group('AppUpdateService — channel policy', () {
    test('a store-managed build never checks and never links to GitHub',
        () async {
      bool fetched = false;
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          fetched = true;
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.managedByStore,
        getStore: SharedPreferences.getInstance,
      );
      final AppUpdateResult r = await svc.check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.notApplicable);
      expect(r.releaseUrl, isNull);
      expect(fetched, isFalse, reason: 'no network call on a store build');
    });

    test('web (channel none) never checks', () async {
      bool fetched = false;
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          fetched = true;
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.none,
        getStore: SharedPreferences.getInstance,
      );
      final AppUpdateResult r = await svc.check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.notApplicable);
      expect(fetched, isFalse);
    });
  });

  group('AppUpdateService — caching', () {
    test('a second check inside the TTL does not hit the network', () async {
      int calls = 0;
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          calls++;
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: SharedPreferences.getInstance,
      );
      final AppUpdateResult a = await svc.check(currentVersion: '1.8.1');
      final AppUpdateResult b = await svc.check(currentVersion: '1.8.1');
      expect(calls, 1);
      expect(a.status, AppUpdateStatus.updateAvailable);
      expect(b.status, AppUpdateStatus.updateAvailable);
      expect(b.latestVersion, '1.9.0');
    });

    test('an expired cache re-fetches', () async {
      int calls = 0;
      DateTime now = DateTime(2026, 7, 20, 9);
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          calls++;
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: SharedPreferences.getInstance,
        clock: () => now,
      );
      await svc.check(currentVersion: '1.8.1');
      expect(calls, 1);

      now = now.add(AppUpdateService.cacheTtl + const Duration(minutes: 1));
      await svc.check(currentVersion: '1.8.1');
      expect(calls, 2);
    });

    test('a backwards clock invalidates the cache rather than pinning it',
        () async {
      int calls = 0;
      DateTime now = DateTime(2026, 7, 20, 9);
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          calls++;
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: SharedPreferences.getInstance,
        clock: () => now,
      );
      await svc.check(currentVersion: '1.8.1');
      now = now.subtract(const Duration(days: 2));
      await svc.check(currentVersion: '1.8.1');
      expect(calls, 2);
    });

    test('an unparseable tag is NOT cached, so it is retried', () async {
      int calls = 0;
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          calls++;
          return releaseJson('nightly');
        },
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: SharedPreferences.getInstance,
      );
      expect((await svc.check(currentVersion: '1.8.1')).status,
          AppUpdateStatus.unknown);
      expect((await svc.check(currentVersion: '1.8.1')).status,
          AppUpdateStatus.unknown);
      expect(calls, 2);
    });

    test('a failed fetch is NOT cached, so recovery is immediate', () async {
      int calls = 0;
      bool offline = true;
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async {
          calls++;
          if (offline) {
            throw const JsonHttpException(
              JsonHttpErrorKind.transport,
              'Network is unreachable.',
            );
          }
          return releaseJson('v1.9.0');
        },
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: SharedPreferences.getInstance,
      );
      expect((await svc.check(currentVersion: '1.8.1')).status,
          AppUpdateStatus.unknown);
      offline = false;
      expect((await svc.check(currentVersion: '1.8.1')).status,
          AppUpdateStatus.updateAvailable);
      expect(calls, 2);
    });

    test('an unavailable preference store does not break the check', () async {
      final AppUpdateService svc = AppUpdateService(
        fetcher: (Duration _) async => releaseJson('v1.9.0'),
        resolveChannel: () => UpdateChannel.githubReleases,
        getStore: () async => throw StateError('no preference store'),
      );
      final AppUpdateResult r = await svc.check(currentVersion: '1.8.1');
      expect(r.status, AppUpdateStatus.updateAvailable);
    });
  });
}
