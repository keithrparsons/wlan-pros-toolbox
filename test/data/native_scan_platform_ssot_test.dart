// Native-scan platform support has ONE source of truth.
//
// WHY THIS FILE EXISTS: `kNativeScanPlatforms` (tool_catalog.dart) and the
// wired-platform set inside `ApScanService` were two hand-kept lists joined
// only by a comment reading "Mirrors ApScanService.isSupportedPlatform".
// Desyncing them — dropping macOS from the catalog while the service still
// claimed macOS support, and adding Windows to the catalog while the screen
// still said Windows is not wired — left the full suite byte-identical at
// 4596 +4/-4. The mutation SURVIVED. A rule expressed as a comment is a rule
// the next maker sincerely believes they followed (GL-013).
//
// The catalog set is now DERIVED from `ApScanService.wiredPlatforms`, so the
// desync is unrepresentable. These tests pin the derivation itself: the mapping
// must stay total and correct, and the shipped value must stay a deliberate,
// test-visible choice rather than something a one-line edit can change quietly.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';

void main() {
  group('native scan platform SSOT', () {
    test('catalog set agrees with the service set, member for member', () {
      final Set<String> fromCatalog =
          kNativeScanPlatforms.map(nativeScanPlatformKey).toSet();
      expect(
        fromCatalog,
        ApScanService.wiredPlatforms,
        reason: 'kNativeScanPlatforms must be derived from '
            'ApScanService.wiredPlatforms, never copied beside it.',
      );
    });

    test('every wired platform string maps to a real TargetPlatform', () {
      // Guards the other direction: a typo'd or retired key in wiredPlatforms
      // would silently derive an EMPTY catalog set, dropping the tool
      // everywhere with no test failing.
      final Set<String> known =
          TargetPlatform.values.map(nativeScanPlatformKey).toSet();
      for (final String p in ApScanService.wiredPlatforms) {
        expect(known, contains(p),
            reason: '"$p" matches no TargetPlatform, so it can never derive '
                'into the catalog.');
      }
    });

    test('the shipped value is Android and macOS', () {
      // Pins the decision itself. Windows stays out until its Native Wifi path
      // is verified on real hardware ([[feedback_gate_until_clean]]); changing
      // this list is a deliberate act that must edit this test too.
      expect(ApScanService.wiredPlatforms, <String>{'android', 'macos'});
      expect(kNativeScanPlatforms,
          <TargetPlatform>{TargetPlatform.android, TargetPlatform.macOS});
    });

    test('the platform key mapping is total and unique', () {
      final List<String> keys =
          TargetPlatform.values.map(nativeScanPlatformKey).toList();
      expect(keys.toSet().length, keys.length,
          reason: 'two TargetPlatforms sharing a key would alias support.');
    });
  });
}
