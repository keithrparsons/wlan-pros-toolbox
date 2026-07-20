// App update check — "is a newer build published than the one running?"
//
// WHY: customers asked for a latest-version check on the About screen. Before
// this file the app had no version-comparison logic of any kind.
//
// PRIVACY (standing product rule: the Toolbox collects NO app telemetry).
// The entire network surface of this feature is ONE unauthenticated HTTPS GET
// to a fixed, parameter-free URL:
//
//     https://api.github.com/repos/walnprosgithub/toolbox-wlanpros-site/releases/latest
//
// No query string, no token, no install ID, no device or usage data, no version
// number, no anything that identifies a user or a machine. The only headers are
// the shared client's static User-Agent ("WLANProsToolbox/1.0 …", identical for
// every install and carrying no version) and Accept: application/json. The
// comparison against the running version happens entirely ON DEVICE — the
// running version is never transmitted. GitHub necessarily observes the source
// IP of any HTTPS request, as it would for any link tap; nothing else leaves.
//
// DEGRADE SILENTLY. Offline, DNS-blocked, rate-limited (the unauthenticated
// GitHub API allows 60 requests/hour/IP), a 404, a malformed body, or a tag we
// cannot parse ALL collapse to [AppUpdateStatus.unknown]. The UI then says it
// could not check. It never shows an error banner, never blocks the About
// screen, and above all never renders "unknown" as reassurance — a false
// "you are up to date" is exactly the class of claim this product does not make
// when it cannot measure something.
//
// PER-PLATFORM. Only direct-download builds may be pointed at GitHub Releases.
// A store-managed install must never be told to go download a .dmg; that is
// both a store-policy problem and a bad experience. See [UpdateChannel].

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'update/update_platform_web_stub.dart'
    if (dart.library.io) 'update/update_platform_io.dart'
    show fetchLatestRelease, macHasAppStoreReceipt;

/// How the running build receives updates, which decides whether an in-app
/// GitHub prompt is appropriate at all.
enum UpdateChannel {
  /// Direct download (notarized macOS .dmg, Windows build). GitHub Releases is
  /// the real update path, so checking and linking is correct.
  githubReleases,

  /// An App Store / TestFlight / Google Play install. The store already handles
  /// updates and pointing at a GitHub download would violate store policy, so
  /// the app shows nothing.
  managedByStore,

  /// No meaningful update channel (web always serves the current build).
  none,
}

/// The outcome of a check. [unknown] is a first-class state, not an error.
enum AppUpdateStatus {
  /// The running version is greater than or equal to the published one.
  upToDate,

  /// A newer version is published; [AppUpdateResult.latestVersion] and
  /// [AppUpdateResult.releaseUrl] are non-null.
  updateAvailable,

  /// The check could not complete or could not be trusted. Render as "could not
  /// check", NEVER as "up to date".
  unknown,

  /// This build does not check (store-managed or web). Render nothing at all.
  notApplicable,
}

/// A typed, immutable check outcome.
@immutable
class AppUpdateResult {
  const AppUpdateResult._(
    this.status, {
    this.latestVersion,
    this.releaseUrl,
  });

  const AppUpdateResult.upToDate() : this._(AppUpdateStatus.upToDate);

  const AppUpdateResult.unknown() : this._(AppUpdateStatus.unknown);

  const AppUpdateResult.notApplicable() : this._(AppUpdateStatus.notApplicable);

  const AppUpdateResult.updateAvailable({
    required String latestVersion,
    required String releaseUrl,
  }) : this._(
          AppUpdateStatus.updateAvailable,
          latestVersion: latestVersion,
          releaseUrl: releaseUrl,
        );

  final AppUpdateStatus status;

  /// The published marketing version (leading `v` stripped), e.g. `1.8.2`.
  /// Non-null only for [AppUpdateStatus.updateAvailable].
  final String? latestVersion;

  /// Where to send the user to get it. Non-null only for
  /// [AppUpdateStatus.updateAvailable].
  final String? releaseUrl;
}

/// A parsed release version, so comparison is NUMERIC and not lexicographic.
///
/// String compare gets `1.10.0` vs `1.9.0` wrong (`'1.1' < '1.9'`), which is the
/// exact bug that would tell a user on the newest build to downgrade. Parsing
/// is deliberately tolerant of the shapes a git tag actually takes (`v1.8.1`,
/// `1.8.1`, `1.8`, `1.8.1+26071901`, `1.9.0-beta.1`) and returns null for
/// anything it cannot read rather than throwing or guessing.
@immutable
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion._(this.components, this.preRelease);

  /// The numeric dot-separated core, e.g. `[1, 8, 1]`. Always non-empty.
  final List<int> components;

  /// The semver pre-release tail (`beta.1` in `1.9.0-beta.1`), or null for a
  /// final release.
  final String? preRelease;

  /// Guard against a pathological tag (e.g. `1.1.1.1.1.…`) turning into an
  /// unbounded list.
  static const int _maxComponents = 4;

  /// Parse a tag or version string, or return null if it is not a version.
  ///
  /// Accepts an optional leading `v`/`V`, discards `+build` metadata (semver
  /// says it is not part of precedence), and requires every core component to
  /// be plain digits.
  static ReleaseVersion? tryParse(String? raw) {
    if (raw == null) return null;
    String s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    if (s.isEmpty) return null;

    // Build metadata is ignored for precedence.
    final int plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);

    // Split the pre-release tail off the numeric core.
    String? pre;
    final int dash = s.indexOf('-');
    if (dash >= 0) {
      pre = s.substring(dash + 1);
      s = s.substring(0, dash);
      if (pre.isEmpty) pre = null;
    }
    if (s.isEmpty) return null;

    final List<String> parts = s.split('.');
    if (parts.isEmpty || parts.length > _maxComponents) return null;

    final List<int> components = <int>[];
    for (final String part in parts) {
      // int.tryParse would accept '+1', '-1' and unicode digits; require plain
      // ASCII digits so a malformed tag is rejected rather than reinterpreted.
      if (part.isEmpty || part.length > 9) return null;
      for (int i = 0; i < part.length; i++) {
        final int c = part.codeUnitAt(i);
        if (c < 0x30 || c > 0x39) return null;
      }
      components.add(int.parse(part));
    }
    return ReleaseVersion._(components, pre);
  }

  @override
  int compareTo(ReleaseVersion other) {
    final int len = components.length > other.components.length
        ? components.length
        : other.components.length;
    for (int i = 0; i < len; i++) {
      // Missing trailing components read as 0, so 1.8 == 1.8.0.
      final int a = i < components.length ? components[i] : 0;
      final int b = i < other.components.length ? other.components[i] : 0;
      if (a != b) return a < b ? -1 : 1;
    }

    // Semver: a pre-release has LOWER precedence than the same final release,
    // so 1.9.0-beta.1 < 1.9.0. Two pre-releases compare by their tail text,
    // which is enough ordering for the one thing this feature does (decide
    // whether the published build is strictly newer than the running one).
    final String? a = preRelease;
    final String? b = other.preRelease;
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(
        components.isNotEmpty ? components[0] : 0,
        components.length > 1 ? components[1] : 0,
        components.length > 2 ? components[2] : 0,
        preRelease,
      );

  @override
  String toString() {
    final String core = components.join('.');
    return preRelease == null ? core : '$core-$preRelease';
  }
}

/// Fetches the raw release JSON. The injectable network seam: tests script
/// every failure mode against it without touching the network.
typedef ReleaseFetcher = Future<Map<String, dynamic>> Function(Duration timeout);

/// Resolves which update channel the running build is on. Injectable so tests
/// can exercise the store branches on a host that is none of those platforms.
typedef ChannelResolver = UpdateChannel Function();

/// Checks whether a newer build has been published, for direct-download builds.
class AppUpdateService {
  AppUpdateService({
    ReleaseFetcher? fetcher,
    ChannelResolver? resolveChannel,
    Future<SharedPreferences> Function()? getStore,
    DateTime Function()? clock,
  })  : _fetch = fetcher ?? fetchLatestRelease,
        _resolveChannel = resolveChannel ?? resolveUpdateChannel,
        _getStore = getStore ?? SharedPreferences.getInstance,
        _now = clock ?? DateTime.now;

  final ReleaseFetcher _fetch;
  final ChannelResolver _resolveChannel;
  final Future<SharedPreferences> Function() _getStore;
  final DateTime Function() _now;

  /// How long a fetched answer is reused before we ask GitHub again.
  ///
  /// Sized against the unauthenticated GitHub limit of 60 requests/hour/IP: at
  /// six hours a user who opens About repeatedly costs at most 4 requests a
  /// day, so this feature cannot be what exhausts the budget (and behind a
  /// shared NAT it stays a rounding error).
  static const Duration cacheTtl = Duration(hours: 6);

  /// Wall-clock budget for the request.
  static const Duration timeout = Duration(seconds: 8);

  static const String _kCachedTagKey = 'app_update_cached_tag';
  static const String _kCachedUrlKey = 'app_update_cached_url';
  static const String _kCachedAtKey = 'app_update_cached_at_ms';

  /// Resolve the update state for [currentVersion] (the running marketing
  /// version, e.g. `1.8.1`).
  ///
  /// Never throws and never rethrows: every failure path returns
  /// [AppUpdateStatus.unknown] so a caller can await this without a try/catch
  /// and without any risk of a network fault reaching the UI as an error.
  Future<AppUpdateResult> check({required String currentVersion}) async {
    final ReleaseVersion? running = ReleaseVersion.tryParse(currentVersion);
    // If we cannot parse OUR OWN version there is nothing to compare against,
    // so claim nothing.
    if (running == null) return const AppUpdateResult.unknown();

    final UpdateChannel channel = _resolveChannel();
    if (channel != UpdateChannel.githubReleases) {
      return const AppUpdateResult.notApplicable();
    }

    final _CachedRelease? cached = await _readCache();
    if (cached != null) {
      return _compare(running: running, tag: cached.tag, url: cached.url);
    }

    final Map<String, dynamic> json;
    try {
      json = await _fetch(timeout);
    } catch (_) {
      // Offline, DNS-blocked, TLS failure, timeout, HTTP 404, HTTP 429
      // rate-limit, oversized or non-JSON body: all indistinguishable to the
      // user and all equally "we do not know".
      return const AppUpdateResult.unknown();
    }

    final Object? rawTag = json['tag_name'];
    final Object? rawUrl = json['html_url'];
    if (rawTag is! String || rawTag.trim().isEmpty) {
      return const AppUpdateResult.unknown();
    }
    // A missing html_url is survivable: fall back to the repo releases page
    // rather than throwing away an otherwise good answer.
    final String url = rawUrl is String && rawUrl.trim().isNotEmpty
        ? rawUrl.trim()
        : kReleasesPageUrl;

    // Only cache a tag we could actually parse, so a garbage tag is re-fetched
    // next time instead of being pinned for six hours.
    if (ReleaseVersion.tryParse(rawTag) != null) {
      await _writeCache(tag: rawTag, url: url);
    }
    return _compare(running: running, tag: rawTag, url: url);
  }

  AppUpdateResult _compare({
    required ReleaseVersion running,
    required String tag,
    required String url,
  }) {
    final ReleaseVersion? latest = ReleaseVersion.tryParse(tag);
    if (latest == null) return const AppUpdateResult.unknown();
    if (latest.compareTo(running) <= 0) return const AppUpdateResult.upToDate();
    return AppUpdateResult.updateAvailable(
      latestVersion: latest.toString(),
      releaseUrl: url,
    );
  }

  Future<_CachedRelease?> _readCache() async {
    try {
      final SharedPreferences prefs = await _getStore();
      final String? tag = prefs.getString(_kCachedTagKey);
      final String? url = prefs.getString(_kCachedUrlKey);
      final int? atMs = prefs.getInt(_kCachedAtKey);
      if (tag == null || url == null || atMs == null) return null;

      final DateTime at = DateTime.fromMillisecondsSinceEpoch(atMs);
      final Duration age = _now().difference(at);
      // A negative age means the clock moved backwards (or the entry was
      // written by a future clock); treat it as stale rather than trusting it
      // indefinitely.
      if (age.isNegative || age > cacheTtl) return null;
      return _CachedRelease(tag: tag, url: url);
    } catch (_) {
      // An unavailable preference store must not break the check.
      return null;
    }
  }

  Future<void> _writeCache({required String tag, required String url}) async {
    try {
      final SharedPreferences prefs = await _getStore();
      await prefs.setString(_kCachedTagKey, tag);
      await prefs.setString(_kCachedUrlKey, url);
      await prefs.setInt(
        _kCachedAtKey,
        _now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Caching is an optimization; failing to persist is not a check failure.
    }
  }
}

/// Human-facing releases page, used as the link fallback and never as an API.
const String kReleasesPageUrl =
    'https://github.com/walnprosgithub/toolbox-wlanpros-site/releases';

/// Decide the update channel for the running build.
///
/// - web: never checks.
/// - iOS / Android: ALWAYS store-managed. These ship only through the App Store
///   (and TestFlight) and Google Play, so a GitHub prompt is never correct. The
///   conservative choice is taken deliberately: we show nothing rather than
///   query a store version API. Checking the iTunes Lookup API would work
///   technically but adds a second network call whose only purpose is to
///   restate what the store already tells the user on the store page, and Play
///   exposes no supported public version API at all (it would mean scraping).
///   Nothing is the honest, policy-safe answer.
/// - macOS: the only platform where the build could be EITHER. Resolved by the
///   Mac App Store receipt probe, defaulting to direct download.
/// - Windows: direct download today.
/// - Linux and anything else: no defined channel, so no claim.
UpdateChannel resolveUpdateChannel() {
  if (kIsWeb) return UpdateChannel.none;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
      return UpdateChannel.managedByStore;
    case TargetPlatform.macOS:
      return macHasAppStoreReceipt()
          ? UpdateChannel.managedByStore
          : UpdateChannel.githubReleases;
    case TargetPlatform.windows:
      return UpdateChannel.githubReleases;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return UpdateChannel.none;
  }
}

@immutable
class _CachedRelease {
  const _CachedRelease({required this.tag, required this.url});

  final String tag;
  final String url;
}
