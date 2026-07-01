// ============================================================================
// STRUCTURAL GUARD — Wi-Fi/signal consumers must not gate capability on a RAW
// platform check; they must delegate to the shared SSOT resolver seams.
// ============================================================================
//
// This is the source-level companion to platform_capability_invariant_test.dart.
// The behavioral invariant proves the SHIPPED SCREENS behave; this proves the
// CODE SHAPE that caused C1/C2/C3 (a screen carrying its own inline
// `TargetPlatform` / `Platform.isX` capability list) cannot creep back into a
// Wi-Fi/signal consumer without a seam in the same file.
//
// WHAT IT DOES.
//   1. AUTO-DISCOVERS Wi-Fi/signal consumers: every file under the network
//      tools + the interface-info service that references the shared Wi-Fi
//      types (WifiInfoSource / WifiSignalSampler / ConnectedApCache / cellular
//      source). New consumers are picked up with no edit here.
//   2. For each discovered consumer that branches on a RAW platform primitive
//      (`TargetPlatform.` or `Platform.isX`), REQUIRES the same file to
//      reference at least one SSOT seam: WifiInfoSourceResolver,
//      WifiSignalSampler(.isSupportedSource), or CellularInfoSourceResolver.
//   3. Pins the KNOWN healthy consumers to the specific seam they must keep
//      (drop-detection): if a refactor deletes the resolver reference from a
//      consumer, this fails even if the file no longer branches on platform.
//
// ---------------------------------------------------------------------------
// THE LIMIT (documented, per the brief). Dart has no cheap AST here without
// pulling the `analyzer` package into the test deps, so this is a lexical scan,
// not a data-flow proof. It can prove a seam is PRESENT in the same file as a
// raw platform branch; it CANNOT prove the branch is actually ROUTED THROUGH
// that seam. A determined regression — a raw `TargetPlatform` capability switch
// sitting beside an unrelated resolver call — would slip past this guard. That
// residual is caught by the BEHAVIORAL invariant (the sibling file drives the
// screen and fails on the false ceiling itself). The two together — behavior +
// shape — are the practical maximum short of a full analyzer pass, which is the
// documented boundary the manual sweep is aware of.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Raw platform-primitive markers that, in a Wi-Fi/signal consumer, are a
/// capability-gate smell unless a resolver seam sits alongside them.
final RegExp _rawPlatformBranch = RegExp(r'TargetPlatform\.|Platform\.is[A-Z]');

/// Any of these in a file means "this is a Wi-Fi/signal/cellular data consumer".
const List<String> _consumerMarkers = <String>[
  'WifiInfoSource',
  'WifiSignalSampler',
  'ConnectedApCache',
  'CellularInfoSource',
];

/// The SSOT delegation seams. A consumer that branches on a raw platform must
/// reference at least one of these in the same file.
const List<String> _ssotSeams = <String>[
  'WifiInfoSourceResolver',
  'WifiSignalSampler.isSupportedSource',
  'WifiSignalSampler', // the sampler instance is itself SSOT-anchored
  'CellularInfoSourceResolver',
];

/// Roots scanned for consumers. The source-of-truth SEAM files themselves
/// (wifi_info_adapter.dart, wifi_signal_sampler.dart, cellular_info_adapter.dart)
/// are the resolvers — they legitimately own the raw platform switch — so they
/// are excluded from the "must delegate" rule.
const List<String> _scanDirs = <String>[
  'lib/screens/tools/network',
];

const List<String> _extraFiles = <String>[
  'lib/services/network/interface_info_service.dart',
];

/// Files that OWN the platform switch (they ARE the SSOT) — excluded from the
/// delegation requirement.
const Set<String> _seamOwners = <String>{
  'wifi_info_adapter.dart',
  'wifi_signal_sampler.dart',
  'cellular_info_adapter.dart',
};

/// Known healthy consumers pinned to the seam they must keep referencing.
/// Drop-detection: deleting the seam from any of these fails the guard.
const Map<String, List<String>> _pinnedConsumers = <String, List<String>>{
  'lib/screens/tools/network/network_glance_card.dart': <String>[
    'WifiInfoSourceResolver'
  ],
  'lib/screens/tools/network/roaming_log_screen.dart': <String>[
    'WifiSignalSampler'
  ],
  'lib/screens/tools/network/test_my_connection_screen.dart': <String>[
    'WifiInfoSourceResolver',
    'WifiSignalSampler',
  ],
  'lib/screens/tools/network/interface_info_screen.dart': <String>[
    'WifiInfoSourceResolver'
  ],
  'lib/screens/tools/network/wifi_info_screen.dart': <String>[
    'WifiInfoSourceResolver'
  ],
  'lib/screens/tools/network/cellular_info_screen.dart': <String>[
    'CellularInfoSourceResolver'
  ],
  'lib/services/network/interface_info_service.dart': <String>[
    'WifiInfoSourceResolver'
  ],
};

bool _mentionsAny(String src, List<String> needles) =>
    needles.any(src.contains);

/// Strips `//` line comments so a raw-platform mention inside a comment (like
/// the explanatory header on the glance card) is not treated as a code branch.
String _stripLineComments(String src) => src
    .split('\n')
    .map((String line) {
      final int i = line.indexOf('//');
      return i >= 0 ? line.substring(0, i) : line;
    })
    .join('\n');

List<File> _discoverConsumers() {
  final List<File> files = <File>[];
  for (final String dir in _scanDirs) {
    final Directory d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final FileSystemEntity e in d.listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) files.add(e);
    }
  }
  for (final String f in _extraFiles) {
    final File file = File(f);
    if (file.existsSync()) files.add(file);
  }
  return files;
}

void main() {
  test('the scan roots exist (guard is actually looking at code)', () {
    expect(Directory(_scanDirs.first).existsSync(), isTrue,
        reason: 'network tools dir moved — update _scanDirs');
    for (final String f in _pinnedConsumers.keys) {
      expect(File(f).existsSync(), isTrue,
          reason: 'pinned consumer moved/renamed — update _pinnedConsumers: $f');
    }
  });

  test(
      'every Wi-Fi/signal consumer that branches on a raw platform ALSO '
      'references a shared SSOT resolver seam (the C1/C2/C3 shape guard)', () {
    final List<String> offenders = <String>[];
    for (final File file in _discoverConsumers()) {
      final String name = file.uri.pathSegments.last;
      if (_seamOwners.contains(name)) continue; // the SSOT owns the switch
      final String raw = file.readAsStringSync();
      if (!_mentionsAny(raw, _consumerMarkers)) continue; // not a consumer
      final String code = _stripLineComments(raw);
      final bool branchesOnPlatform = _rawPlatformBranch.hasMatch(code);
      if (!branchesOnPlatform) continue; // no raw platform gate at all
      if (!_mentionsAny(code, _ssotSeams)) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'these Wi-Fi/signal consumers branch on a raw platform WITHOUT '
            'a shared resolver seam in the file — the exact inline-list shape '
            'that produced C1/C2/C3. Route the capability decision through '
            'WifiInfoSourceResolver / WifiSignalSampler.isSupportedSource / '
            'CellularInfoSourceResolver:\n${offenders.join('\n')}');
  });

  test('known healthy consumers still reference their required SSOT seam '
      '(drop-detection)', () {
    _pinnedConsumers.forEach((String path, List<String> requiredSeams) {
      final File file = File(path);
      if (!file.existsSync()) return; // covered by the existence test above
      final String code = _stripLineComments(file.readAsStringSync());
      for (final String seam in requiredSeams) {
        expect(code.contains(seam), isTrue,
            reason: '$path no longer references "$seam" — a consumer must not '
                'drop its SSOT seam (that is how it drifts and re-introduces a '
                'false platform ceiling)');
      }
    });
  });
}
