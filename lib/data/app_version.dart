// App version — the SSOT mirror of pubspec.yaml `version:`.
//
// The Toolbox does not depend on `package_info_plus` (a native plugin that
// would need iOS/macOS/Android registration just to read one string the build
// already knows). Until that dependency is added, the About screen reads the
// real shipped version from this single constant, which MUST be kept in lockstep
// with the `version:` line in pubspec.yaml.
//
// pubspec format is `<name>+<build>` (e.g. `1.0.0+1`); we surface it as
// `<name> (<build>)` per the App Store convention CFBundleShortVersionString
// (<name>) + CFBundleVersion (<build>). This is the TRUE current value, not a
// placeholder — if pubspec's `version:` changes, update both halves here.
//
// FOLLOW-UP (non-blocking): if/when `package_info_plus` is added for other
// reasons, swap [AppVersion.display] to read PackageInfo.fromPlatform() at
// runtime and delete the manual mirror, so the version can never drift.
class AppVersion {
  AppVersion._();

  /// CFBundleShortVersionString — the marketing version (pubspec name part).
  static const String name = '1.0.0';

  /// CFBundleVersion — the build number (pubspec `+<build>` part).
  static const String build = '6';

  /// The version string shown in the About screen, e.g. `1.0.0 (1)`.
  static const String display = '$name ($build)';
}
