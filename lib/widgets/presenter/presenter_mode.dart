// PresenterMode: the projector-legibility scale for the Wi-Fi Classroom presenter
// layout (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 00-presenter-layout.md).
//
// PresenterLayout wraps its stage and controls in a [PresenterMode] and raises
// the MediaQuery text scale by [PresenterScale.text], so every Text widget
// grows with no change to the tool. What MediaQuery cannot reach is paint:
// strokes, marker radii and TextPainter labels inside a CustomPainter. Those
// read [PresenterMode.scaleOf] and multiply. Outside presenter mode it returns
// [PresenterScale.normal] (every factor 1.0), so a painter never branches.
//
// Contrast floors (GL-003 §8.9) are untouched: this scales size, never color.

import 'package:flutter/widgets.dart';

/// The size factors a presenter surface applies. Immutable.
@immutable
class PresenterScale {
  const PresenterScale({
    this.text = 1,
    this.headline = 1,
    this.stroke = 1,
    this.marker = 1,
  });

  /// Identity: the phone and desktop layouts.
  static const PresenterScale normal = PresenterScale();

  /// The projector scale (spec §1: about 1.35x on body and readouts, larger
  /// on headline readouts; painters thicken strokes and enlarge markers).
  static const PresenterScale projector = PresenterScale(
    text: 1.35,
    headline: 1.75,
    stroke: 1.75,
    marker: 1.5,
  );

  /// The window height [projector] is calibrated to.
  static const double referenceHeight = 1080;

  /// The projector scale for a window of [size]. A projector throws any
  /// window onto the same physical screen, so what the back row can read is
  /// text height as a share of the window height, not logical pixels. The
  /// factors therefore follow the window height, equal to [projector] at
  /// [referenceHeight] (1.35x text at 1080, 1.125x at 900, 1.5x at 1200), and
  /// held so text never drops below 1.1x or passes 1.8x.
  static PresenterScale forWindow(Size size) {
    final double k = size.height / referenceHeight;
    final double t = (projector.text * k).clamp(1.1, 1.8);
    final double r = t / projector.text;
    return PresenterScale(
      text: t,
      headline: projector.headline * r,
      stroke: projector.stroke * r,
      marker: projector.marker * r,
    );
  }

  /// Factor on all text. PresenterLayout applies it through MediaQuery, so
  /// ordinary Text widgets need nothing. Painters that lay out their own
  /// TextPainter multiply their font size by it ([paintFont]).
  final double text;

  /// Total factor on a headline readout (the one number a lesson is about).
  final double headline;

  /// Factor on painted line widths.
  final double stroke;

  /// Factor on painted marker radii and dot sizes.
  final double marker;

  /// True for any scale other than [normal].
  bool get isPresenting => this != normal;

  /// A painted stroke width.
  double strokeWidth(double w) => w * stroke;

  /// A painted marker radius or size.
  double markerSize(double r) => r * marker;

  /// A font size for a TextPainter a CustomPainter lays out itself (which
  /// MediaQuery's text scaler does not reach).
  double paintFont(double size) => size * text;

  /// A headline readout style. MediaQuery already applies [text], so this
  /// adds only the headline's extra over it.
  TextStyle headlineStyle(TextStyle style) {
    final double? size = style.fontSize;
    if (size == null || text == 0) return style;
    return style.copyWith(fontSize: size * headline / text);
  }

  @override
  bool operator ==(Object other) =>
      other is PresenterScale &&
      other.text == text &&
      other.headline == headline &&
      other.stroke == stroke &&
      other.marker == marker;

  @override
  int get hashCode => Object.hash(text, headline, stroke, marker);
}

/// Marks a subtree as the presenter surface and carries its [PresenterScale].
class PresenterMode extends InheritedWidget {
  const PresenterMode({
    super.key,
    this.scale = PresenterScale.projector,
    required super.child,
  });

  final PresenterScale scale;

  /// The nearest presenter scale, or [PresenterScale.normal] outside
  /// presenter mode. Safe to call from any build method.
  static PresenterScale scaleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PresenterMode>()?.scale ??
      PresenterScale.normal;

  /// True inside a presenter layout. Stage and controls widgets use this to
  /// pick their presenter arrangement (fill a bounded box) over the phone one
  /// (an intrinsic-height column inside a page scroll).
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PresenterMode>() != null;

  @override
  bool updateShouldNotify(PresenterMode oldWidget) => oldWidget.scale != scale;
}
