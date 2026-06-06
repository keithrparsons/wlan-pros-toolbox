// Regression guard for the iOS bundled-asset signing blocker (error 90035,
// "Code object is not signed at all").
//
// ROOT CAUSE (corrected): iOS distribution signing flags a bundled file as
// unsigned code based on its CONTENT, not its extension. An earlier fix renamed
// the script/package to inert extensions (`.sh.txt` / `.deb.bin`) and STILL got
// rejected — Apple's validator reads the `#!/bin/bash` shebang (and Mach-O
// magic) and treats the file as an executable regardless of name. The definitive
// fix stores the payloads BASE64-ENCODED (`.b64`) so nothing in the bundle looks
// like a script or a Mach-O binary; the screens decode them at runtime.
//
// This test asserts the REAL invariant: scan the real `assets/downloads/`
// directory on disk (no Flutter binding needed — the established pattern in this
// suite reads bundled assets via dart:io) and assert that NO file's first bytes
// are a shebang (`#!`) or Mach-O magic. Only base64/text payloads are allowed.
// That is the exact thing Apple's signer rejects, so guarding the content (not
// the extension) is what makes the regression impossible to ship silently.
//
// Robustness: if the directory scan ever can't run, the test still asserts the
// two known asset-path constants end in `.b64`, so the guard can never silently
// pass.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/guides/dual_orb_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/freeradius_wlanpi_screen.dart';

void main() {
  // The first bytes Apple's code-signing validator treats as executable code.
  // A shebang (`#!`) marks a script; the four Mach-O magics mark a native
  // binary (thin big/little-endian, 64-bit, and fat/universal).
  const int hashBang0 = 0x23; // '#'
  const int hashBang1 = 0x21; // '!'

  // Mach-O / fat-binary magic numbers, as 4-byte big-endian sequences.
  const List<List<int>> machOMagics = <List<int>>[
    <int>[0xCA, 0xFE, 0xBA, 0xBE], // FAT_MAGIC (universal)
    <int>[0xFE, 0xED, 0xFA, 0xCE], // MH_MAGIC (32-bit)
    <int>[0xFE, 0xED, 0xFA, 0xCF], // MH_MAGIC_64 (64-bit)
    <int>[0xCF, 0xFA, 0xED, 0xFE], // MH_CIGAM_64 (64-bit, byte-swapped)
  ];

  bool startsWithShebang(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == hashBang0 && bytes[1] == hashBang1;

  bool startsWithMachO(Uint8List bytes) {
    if (bytes.length < 4) return false;
    for (final List<int> magic in machOMagics) {
      if (bytes[0] == magic[0] &&
          bytes[1] == magic[1] &&
          bytes[2] == magic[2] &&
          bytes[3] == magic[3]) {
        return true;
      }
    }
    return false;
  }

  group('bundled downloads iOS signing guard (content, not extension)', () {
    test(
        'no asset under assets/downloads/ begins with a shebang or Mach-O magic',
        () {
      final Directory downloads = Directory('assets/downloads');
      expect(
        downloads.existsSync(),
        isTrue,
        reason: 'assets/downloads/ must exist (bundled in pubspec.yaml)',
      );

      final List<String> offenders = <String>[];
      for (final File f in downloads.listSync().whereType<File>()) {
        final Uint8List head = f.openSync().readSync(8);
        if (startsWithShebang(head) || startsWithMachO(head)) {
          offenders.add(f.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these bundled files begin with a `#!` shebang or Mach-O magic, '
            'which iOS distribution signing treats as unsigned code (error '
            '90035) REGARDLESS of file extension. Store the payload '
            'base64-encoded (.b64) and decode it at runtime: $offenders',
      );
    });

    test('the known asset-path constants are base64 (.b64) payloads', () {
      // Fallback guard: independent of the directory scan, the constants the
      // screens actually bundle must point at base64-encoded payloads.
      expect(
        FreeradiusWlanpiScreen.scriptAsset.endsWith('.b64'),
        isTrue,
        reason: 'freeradius scriptAsset must be a .b64 payload',
      );
      expect(
        kDualOrbAssetPath.endsWith('.b64'),
        isTrue,
        reason: 'dual-orb asset path must be a .b64 payload',
      );
    });

    test('the user-facing download filenames are unchanged (real .sh / .deb)',
        () {
      // The base64 encoding must NOT change what the user downloads.
      expect(FreeradiusWlanpiScreen.scriptFilename, 'install_freeradius.sh');
      expect(kDualOrbDebFilename, 'wlanpi-dual-orb_1.1.3_all.deb');
    });
  });
}
