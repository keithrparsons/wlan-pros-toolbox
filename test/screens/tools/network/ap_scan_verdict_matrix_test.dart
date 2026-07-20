// THE CROSS-PRODUCT GUARD: exactly one verdict, over the whole state matrix.
//
// WHY THIS FILE EXISTS. Three consecutive fixes to this screen each closed a
// real defect and opened a new false claim one axis over:
//
//   1. A withheld identity rendered as "(hidden network)" — a permission fact
//      told as an RF fact. Fixed by dropping identity-less rows.
//   2. That drop was silent, so the screen under-reported the RF environment —
//      false identity became false COUNT. Fixed by gating and disclosing.
//   3. The disclosure then rendered ALONGSIDE "no access points in range",
//      telling a user standing among APs that there were none, with an action
//      attached ("move to where Wi-Fi is in use").
//
// Every one of those was the same root cause: a state was ADDED and nobody
// re-walked the matrix. The screen decided its cards with independent `if`s, so
// "the screen states exactly one thing" was a property no code owned.
//
// This test owns it. It walks the full cross-product of the state axes and
// asserts that exactly ONE verdict card renders — never zero (the user is told
// nothing), never two (the user is told two contradictory things). It is
// deliberately indifferent to WHICH card is right for a given combination;
// that is what the behaviour tests in ap_scan_screen_test.dart pin. This test
// guards the invariant that survives the next person adding a fourth state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ap_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The user-visible verdict cards, each identified by a finder that matches
/// that card and no other.
///
/// Matched on COPY rather than widget type on purpose: the defect being guarded
/// is what the user is TOLD, and two cards can be distinct widgets while making
/// the same claim.
///
/// The discriminators are narrower than the obvious phrase because the product
/// copy genuinely overlaps: the Wi-Fi-off card and the Location card BOTH say
/// "the scan could not run" (correctly — in both cases it did not), and
/// "access point" appears inside the no-networks copy. A loose matcher would
/// have reported contradictions that are not there, and — worse — could mask a
/// real one behind a false positive.
final Map<String, Finder> _verdictFinders = <String, Finder>{
  'radio off': find.textContaining('Wi-Fi is off, so the scan could not run'),
  'permission': find.textContaining('Location Services'),
  'none readable': find.textContaining('Networks detected, none readable'),
  'nothing in range': find.textContaining('found no access points in range'),
  // The AP-list card title, and only that: "3 access points" / "1 access
  // point", never the same words inside a sentence.
  'aps found': find.byWidgetPredicate((Widget w) =>
      w is Text &&
      w.data != null &&
      RegExp(r'^\d+ access points?$').hasMatch(w.data!)),
};

void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.dark(), home: child);

  ApScanService service(Map<String, Object?> payload) => ApScanService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          switch (method) {
            case 'scan':
            case 'lastResults':
              return payload;
            case 'isLocationAuthorized':
              return payload['locationAuthorized'];
          }
          return null;
        },
      );

  /// A well-formed row that parses into a real AP.
  Map<String, Object?> goodRow(int channel) => <String, Object?>{
        'ssid': 'Net$channel',
        'bssid': 'a4:83:e7:00:11:${channel.toRadixString(16).padLeft(2, '0')}',
        'rssiDbm': -60,
        'channel': channel,
        'band': '2.4 GHz',
        'frequencyMhz': 2437,
      };

  /// A row the radio reported that cannot be parsed — no channel or band. This
  /// is the shape the 6 GHz `bandUnknown` drop produces.
  Map<String, Object?> unreadableRow() =>
      <String, Object?>{'ssid': 'Unreadable', 'bssid': 'a4:83:e7:00:99:99'};

  /// A row whose identity the OS withheld — the Android no-permission
  /// placeholder.
  Map<String, Object?> withheldRow() => <String, Object?>{
        'ssid': null,
        'bssid': '02:00:00:00:00:00',
        'rssiDbm': -60,
        'channel': 6,
        'band': '2.4 GHz',
        'frequencyMhz': 2437,
      };

  group('exactly one verdict renders, over the full state matrix', () {
    // The axes. `rows` is the interesting one: it drives aps.isEmpty,
    // unreadableCount and identityWithheld all at once, which is precisely why
    // they could not be reasoned about independently.
    final Map<String, List<Map<String, Object?>>> rowSets =
        <String, List<Map<String, Object?>>>{
      'no rows': <Map<String, Object?>>[],
      'good rows only': <Map<String, Object?>>[goodRow(1), goodRow(6)],
      'unreadable rows only': <Map<String, Object?>>[
        unreadableRow(),
        unreadableRow(),
      ],
      'good + unreadable': <Map<String, Object?>>[goodRow(1), unreadableRow()],
      'withheld only': <Map<String, Object?>>[withheldRow()],
      'good + withheld': <Map<String, Object?>>[goodRow(1), withheldRow()],
      'withheld + unreadable': <Map<String, Object?>>[
        withheldRow(),
        unreadableRow(),
      ],
      'all three': <Map<String, Object?>>[
        goodRow(1),
        withheldRow(),
        unreadableRow(),
      ],
    };

    for (final bool poweredOn in <bool>[true, false]) {
      for (final bool locationAuthorized in <bool>[true, false]) {
        for (final bool scanThrottled in <bool>[true, false]) {
          for (final MapEntry<String, List<Map<String, Object?>>> rows
              in rowSets.entries) {
            final String name = 'poweredOn=$poweredOn '
                'locationAuthorized=$locationAuthorized '
                'throttled=$scanThrottled rows=${rows.key}';

            testWidgets(name, (tester) async {
              await tester.pumpWidget(host(ApScanScreen(
                service: service(<String, Object?>{
                  'poweredOn': poweredOn,
                  'locationAuthorized': locationAuthorized,
                  'scanThrottled': scanThrottled,
                  'accessPoints': rows.value,
                }),
              )));
              await tester.pumpAndSettle();

              final List<String> rendered = <String>[
                for (final MapEntry<String, Finder> e in _verdictFinders.entries)
                  if (e.value.evaluate().isNotEmpty) e.key,
              ];

              expect(
                rendered,
                hasLength(1),
                reason: 'Expected exactly ONE verdict for [$name], got '
                    '${rendered.length}: $rendered. Zero means the user is told '
                    'nothing happened; two means the screen contradicts itself. '
                    'If a state was just added, extend ApScanVerdict rather '
                    'than adding another independent `if` to the screen.',
              );
            });
          }
        }
      }
    }
  });

  group('the verdict itself is derived, not re-decided per card', () {
    ApScanSnapshot snap({
      bool poweredOn = true,
      bool locationAuthorized = true,
      List<ScannedAp> aps = const <ScannedAp>[],
      int unreadableCount = 0,
    }) =>
        ApScanSnapshot(
          accessPoints: aps,
          poweredOn: poweredOn,
          locationAuthorized: locationAuthorized,
          scanThrottled: false,
          unreadableCount: unreadableCount,
        );

    const ScannedAp ap = ScannedAp(
      ssid: 'Net',
      bssid: 'a4:83:e7:00:11:22',
      rssiDbm: -60,
      channel: 6,
      band: '2.4 GHz',
      frequencyMhz: 2437,
    );

    test('radio off outranks everything — nothing was measured', () {
      expect(snap(poweredOn: false).verdict, ApScanVerdict.radioOff);
      expect(
        snap(poweredOn: false, unreadableCount: 3).verdict,
        ApScanVerdict.radioOff,
      );
    });

    test('a missing grant outranks an empty list', () {
      // The emptiness was never measured, so it cannot be reported as emptiness.
      expect(
        snap(locationAuthorized: false).verdict,
        ApScanVerdict.permissionMissing,
      );
    });

    test('unread rows outrank "nothing in range" — unknown is not empty', () {
      expect(snap(unreadableCount: 2).verdict, ApScanVerdict.noneReadable);
    });

    test('only a clean, empty, authorized scan may claim nothing in range', () {
      expect(snap().verdict, ApScanVerdict.nothingInRange);
    });

    test('any readable AP makes the list the verdict', () {
      expect(
        snap(aps: <ScannedAp>[ap], unreadableCount: 5).verdict,
        ApScanVerdict.apsFound,
      );
    });
  });
}
