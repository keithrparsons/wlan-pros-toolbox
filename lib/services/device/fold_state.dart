// iPhone Duo fold state (Keith, 2026-11-07, approach C).
//
// Flutter does not report the Duo's fold on iOS (MediaQuery.displayFeatures is
// filled only on Android; flutter/flutter#192515 is open), so the native
// HingeChannel (ios/Runner/HingeChannel.swift) reads Apple's iOS 27.1 hinge
// and reserved-region APIs and streams them here. Every other platform, and an
// iPhone without a hinge, stays at [FoldState.none].

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple's UIHinge.Status.
enum HingeStatus { unknown, closed, partiallyOpen, fullyOpen }

@immutable
class FoldState {
  const FoldState({
    required this.status,
    required this.angle,
    required this.folds,
  });

  /// No hinge reported: the plain layout.
  static const FoldState none = FoldState(
    status: HingeStatus.unknown,
    angle: 0,
    folds: <Rect>[],
  );

  /// Reads one HingeChannel event. Anything malformed reads as [none], so a
  /// bad event can only cost the fold-aware layout, never the screen.
  factory FoldState.fromEvent(Object? event) {
    if (event is! Map) return none;
    final Object? status = event['status'];
    final Object? angle = event['angle'];
    final Object? folds = event['folds'];
    if (status is! String || angle is! num || folds is! List) return none;
    final List<Rect> rects = <Rect>[];
    for (final Object? f in folds) {
      if (f is! List || f.length != 4 || f.any((Object? v) => v is! num)) {
        return none;
      }
      final List<double> v = f
          .cast<num>()
          .map((num n) => n.toDouble())
          .toList();
      rects.add(Rect.fromLTWH(v[0], v[1], v[2], v[3]));
    }
    return FoldState(
      status: HingeStatus.values.firstWhere(
        (HingeStatus s) => s.name == status,
        orElse: () => HingeStatus.unknown,
      ),
      angle: angle.toDouble(),
      folds: rects,
    );
  }

  final HingeStatus status;

  /// Hinge angle in degrees, as Apple reports it.
  final double angle;

  /// Active fold regions in the app's logical pixels (a flat fold may be zero
  /// wide).
  final List<Rect> folds;

  @override
  bool operator ==(Object other) =>
      other is FoldState &&
      other.status == status &&
      other.angle == angle &&
      listEquals(other.folds, folds);

  @override
  int get hashCode => Object.hash(status, angle, Object.hashAll(folds));

  @override
  String toString() => 'FoldState($status, $angle°, $folds)';
}

/// The current fold state. Screens listen to it; tests set it directly.
final ValueNotifier<FoldState> foldState = ValueNotifier<FoldState>(
  FoldState.none,
);

/// Starts the HingeChannel stream on iOS. Called once from main().
void startFoldUpdates() {
  if (kIsWeb || !Platform.isIOS) return;
  const EventChannel(
    'com.wlanpros.toolbox/hinge',
  ).receiveBroadcastStream().listen(
    (Object? event) => foldState.value = FoldState.fromEvent(event),
    onError: (Object _) => foldState.value = FoldState.none,
  );
}
