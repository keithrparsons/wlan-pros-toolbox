// Regression guard for the iOS bundled-asset signing blocker (error 90035,
// "Invalid Signature, Code object is not signed at all").
//
// iOS distribution signing treats a bundled file with an executable/script
// extension (`.sh`, `.command`, `.bash`, `.deb`) as unsigned code and rejects
// the upload. macOS Developer ID accepts it, so the failure is iOS-only and
// easy to reintroduce by dropping a new script/package into assets/downloads/.
//
// This test makes that regression impossible to ship silently: it scans the
// real `assets/downloads/` directory on disk (no Flutter binding needed — the
// established pattern in this suite reads bundled assets via dart:io) and
// asserts no file carries a risky executable/script extension. The bundled
// files are renamed to `.txt` / `.bin` (inert data extensions); the user-facing
// DOWNLOAD filenames stay `install_freeradius.sh` / `wlanpi-dual-orb_1.1.3_all.deb`
// via the screens' `scriptFilename` / `kDualOrbDebFilename` constants.
//
// Robustness: if the directory scan ever can't run, the test still asserts the
// two known asset-path constants don't end in `.sh` / `.deb`, so the guard
// can never silently pass.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/guides/dual_orb_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/freeradius_wlanpi_screen.dart';

void main() {
  // Extensions iOS distribution signing flags as unsigned code. `.bin` is NOT
  // risky (inert data), so it is intentionally absent from this list.
  const List<String> riskyExtensions = <String>[
    '.sh',
    '.command',
    '.bash',
    '.deb',
  ];

  bool endsWithRisky(String path) {
    final String lower = path.toLowerCase();
    return riskyExtensions.any(lower.endsWith);
  }

  group('bundled downloads iOS signing guard', () {
    test(
        'no asset under assets/downloads/ ends in a risky executable extension',
        () {
      final Directory downloads = Directory('assets/downloads');
      expect(
        downloads.existsSync(),
        isTrue,
        reason: 'assets/downloads/ must exist (bundled in pubspec.yaml)',
      );

      final List<String> offenders = downloads
          .listSync()
          .whereType<File>()
          .map((File f) => f.path)
          .where(endsWithRisky)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'these bundled files use an executable/script extension iOS '
            'distribution signing rejects (error 90035). Rename them to an '
            'inert data extension (.txt / .bin) and keep the download FILENAME '
            'via the screen constant: $offenders',
      );
    });

    test('the known asset-path constants do not end in .sh / .deb', () {
      // Fallback guard: independent of the directory scan, the constants the
      // screens actually bundle must not carry a risky extension.
      expect(endsWithRisky(FreeradiusWlanpiScreen.scriptAsset), isFalse,
          reason: 'freeradius scriptAsset must not end in a risky extension');
      expect(endsWithRisky(kDualOrbAssetPath), isFalse,
          reason: 'dual-orb asset path must not end in a risky extension');
    });

    test('the user-facing download filenames are unchanged (real .sh / .deb)',
        () {
      // The bundled-asset rename must NOT change what the user downloads.
      expect(FreeradiusWlanpiScreen.scriptFilename, 'install_freeradius.sh');
      expect(kDualOrbDebFilename, 'wlanpi-dual-orb_1.1.3_all.deb');
    });
  });
}
