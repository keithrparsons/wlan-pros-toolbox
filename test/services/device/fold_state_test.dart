// The iPhone Duo hinge event, as the native HingeChannel sends it
// (ios/Runner/HingeChannel.swift): status, angle in degrees, and the active
// fold ("division") regions in the app's own points as [x, y, width, height].
// The native side also sends the hinge angle; the layout does not use it.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/device/fold_state.dart';

void main() {
  test('parses a half-open book pose', () {
    final FoldState s = FoldState.fromEvent(<String, Object?>{
      'status': 'partiallyOpen',
      'angle': 95.0,
      'folds': <Object?>[
        <Object?>[475.0, 0.0, 0.0, 669.0],
      ],
    });
    expect(s.status, HingeStatus.partiallyOpen);
    expect(s.folds, <Rect>[const Rect.fromLTWH(475, 0, 0, 669)]);
  });

  for (final (String raw, HingeStatus status) in <(String, HingeStatus)>[
    ('closed', HingeStatus.closed),
    ('fullyOpen', HingeStatus.fullyOpen),
    ('unknown', HingeStatus.unknown),
    ('somethingNew', HingeStatus.unknown),
  ]) {
    test('status "$raw" reads as $status', () {
      final FoldState s = FoldState.fromEvent(<String, Object?>{
        'status': raw,
        'angle': 0.0,
        'folds': <Object?>[],
      });
      expect(s.status, status);
    });
  }

  test('anything malformed reads as no fold', () {
    for (final Object? bad in <Object?>[
      null,
      'x',
      <String, Object?>{'status': 'partiallyOpen'},
      <String, Object?>{
        'status': 'partiallyOpen',
        'angle': 90.0,
        'folds': <Object?>[
          <Object?>[1.0, 2.0],
        ],
      },
    ]) {
      expect(FoldState.fromEvent(bad), FoldState.none, reason: '$bad');
    }
  });
}
