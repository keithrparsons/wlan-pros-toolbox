// App version — runtime-read build identity for the About screen.
//
// As of v1.1.1 the version + build number are read at RUNTIME via
// `package_info_plus` (PackageInfo.fromPlatform), so what the About screen
// shows is always the actual running build — never a hand-mirrored constant
// that can drift from pubspec / the injected CFBundleVersion. This matters for
// beta triage: a tester needs to report the EXACT build, and the buildNumber at
// runtime is the CFBundleVersion timestamp ship_ios.sh injects (e.g.
// 202606052247).
//
// PackageInfo maps to:
//   - version     → CFBundleShortVersionString (iOS/macOS) / versionName
//                   (Android) — the marketing version, pubspec's `<name>` part.
//   - buildNumber → CFBundleVersion (iOS/macOS) / versionCode (Android) —
//                   pubspec's `+<build>` part, overridden per-build by
//                   --build-number (the ship_ios.sh timestamp).
//
// The pubspec-mirrored [fallback*] constants remain ONLY as a safe, synchronous
// default for the brief window before [load] resolves and for widget tests that
// do not bind the platform channel. They are NOT the runtime source of truth;
// PackageInfo is. The legacy [name] / [build] / [display] aliases are retained
// so pre-existing callers/tests keep compiling, but new code should read the
// runtime [AppVersionInfo] from [AppVersion.load].

import 'package:package_info_plus/package_info_plus.dart';

/// An immutable snapshot of the running build's version + build number.
///
/// Carries the two halves separately (so the UI can label them) plus a
/// pre-formatted [display] string. Const-constructible so it doubles as the
/// synchronous fallback before the async [AppVersion.load] resolves.
class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  /// Marketing version — CFBundleShortVersionString, e.g. `1.5.9`.
  final String version;

  /// Build number — CFBundleVersion, e.g. `202606052247`. May be empty on
  /// platforms/builds that did not set one.
  final String buildNumber;

  /// The labeled, copy-ready line, e.g. `Version 1.5.9 (build 202606052247)`.
  /// When the build number is empty, the `(build …)` clause is omitted rather
  /// than printing an empty paren.
  String get display => buildNumber.isEmpty
      ? 'Version $version'
      : 'Version $version (build $buildNumber)';
}

/// Reads the running build's version identity at runtime.
class AppVersion {
  AppVersion._();

  /// Pubspec-mirrored marketing version — the synchronous fallback only.
  ///
  /// MUST equal pubspec's `version:` marketing part. This isn't only a
  /// failure-case value: it renders unconditionally on the license page
  /// (`showLicensePage`) and as the pre-resolve copy fallback, so a stale value
  /// here is a wrong version shown to a user, not just a rare degrade. Pinned to
  /// pubspec by `app_version_fallback_matches_pubspec_test.dart` so it can't
  /// silently drift again (it had drifted to 1.1.0 while pubspec was 1.5.9).
  static const String fallbackVersion = '1.5.12';

  /// Pubspec-mirrored build number — the synchronous fallback only. MUST equal
  /// pubspec's `+<build>` part; pinned by the same drift test as
  /// [fallbackVersion]. (iOS ship builds inject a CFBundleVersion timestamp that
  /// PackageInfo reads at runtime; this constant is the pubspec-declared build
  /// used only when that runtime read is unavailable.)
  static const String fallbackBuildNumber = '48';

  /// A const fallback snapshot, used before [load] resolves and in tests that
  /// do not bind the platform channel.
  static const AppVersionInfo fallback = AppVersionInfo(
    version: fallbackVersion,
    buildNumber: fallbackBuildNumber,
  );

  /// Reads version + build number from the running bundle via
  /// `PackageInfo.fromPlatform`. On any failure (e.g. an unbound test channel)
  /// it falls back to the const [fallback] so the UI never throws or shows
  /// nothing useful.
  static Future<AppVersionInfo> load() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String version =
          info.version.isNotEmpty ? info.version : fallbackVersion;
      return AppVersionInfo(version: version, buildNumber: info.buildNumber);
    } catch (_) {
      return fallback;
    }
  }

  // --- Legacy synchronous aliases (retained for backward compatibility) ------
  // These point at the pubspec-mirrored fallback values, NOT the runtime read.
  // Kept so existing callers/tests keep compiling during the runtime migration.

  /// Legacy alias for [fallbackVersion].
  static const String name = fallbackVersion;

  /// Legacy alias for [fallbackBuildNumber].
  static const String build = fallbackBuildNumber;

  /// Legacy synchronous display, `name (build)` — the pre-runtime format.
  static const String display = '$name ($build)';
}
