// Complex: a small immutable complex number for the Wi-Fi Classroom physics.
//
// Dart has no built-in complex type and the repo had none (checked
// 2026-09-25: no `class Complex` under lib/ or test/). This one carries only
// what the ITU-R P.2040 slab equations need: arithmetic, the principal square
// root and the complex exponential.
//
// Two numerical choices matter for the wall simulator:
//   - Division uses Smith's algorithm, so a metal wall (conductivity 1e7 S/m,
//     an imaginary permittivity near 1e8) never overflows an intermediate.
//   - sqrt is the principal branch (real part >= 0). For a lossy medium,
//     epsilon = e' - j e'', that puts the imaginary part <= 0, which is the
//     decaying wave the slab formulas assume.
//
// No Flutter imports.

import 'dart:math' as math;

/// An immutable complex number `re + j·im`.
class Complex {
  const Complex(this.re, [this.im = 0]);

  /// `0 + 0j`.
  static const Complex zero = Complex(0);

  /// `1 + 0j`.
  static const Complex one = Complex(1);

  /// The imaginary unit `j`.
  static const Complex j = Complex(0, 1);

  /// `r·e^(jθ)`.
  factory Complex.polar(double r, double theta) =>
      Complex(r * math.cos(theta), r * math.sin(theta));

  final double re;
  final double im;

  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator -() => Complex(-re, -im);

  Complex operator *(Complex o) =>
      Complex(re * o.re - im * o.im, re * o.im + im * o.re);

  /// Smith's algorithm: scales by the larger component of the divisor so no
  /// intermediate squares a huge number.
  Complex operator /(Complex o) {
    if (o.re == 0 && o.im == 0) {
      throw ArgumentError('Complex division by zero');
    }
    if (o.re.abs() >= o.im.abs()) {
      final double r = o.im / o.re;
      final double den = o.re + o.im * r;
      return Complex((re + im * r) / den, (im - re * r) / den);
    }
    final double r = o.re / o.im;
    final double den = o.re * r + o.im;
    return Complex((re * r + im) / den, (im * r - re) / den);
  }

  /// Multiplies by a real scalar.
  Complex scale(double k) => Complex(re * k, im * k);

  /// Complex conjugate.
  Complex get conjugate => Complex(re, -im);

  /// Magnitude `|z|`, computed without overflow (hypot form).
  double get abs {
    final double a = re.abs();
    final double b = im.abs();
    if (a == 0) return b;
    if (b == 0) return a;
    if (a >= b) {
      final double r = b / a;
      return a * math.sqrt(1 + r * r);
    }
    final double r = a / b;
    return b * math.sqrt(1 + r * r);
  }

  /// Squared magnitude `|z|²`. For power ratios.
  double get abs2 => re * re + im * im;

  /// Argument in radians, in (-π, π].
  double get arg => math.atan2(im, re);

  /// Principal square root: real part >= 0; on the branch cut (negative real
  /// axis) the imaginary part takes the sign of [im], so `-4 - 0j` gives
  /// `0 - 2j`.
  Complex sqrt() {
    if (re == 0 && im == 0) return zero;
    final double m = abs;
    final double a = math.sqrt((m + re.abs()) / 2);
    if (re >= 0) {
      return Complex(a, im / (2 * a));
    }
    final double b = im.isNegative ? -a : a;
    return Complex(im.abs() / (2 * a), b);
  }

  /// `e^z = e^re·(cos im + j sin im)`. A very negative real part underflows
  /// cleanly to zero, which is what a thick metal wall should produce.
  Complex exp() {
    final double m = math.exp(re);
    if (m == 0) return zero;
    return Complex(m * math.cos(im), m * math.sin(im));
  }

  bool get isFinite => re.isFinite && im.isFinite;

  @override
  bool operator ==(Object other) =>
      other is Complex && other.re == re && other.im == im;

  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() => im < 0 ? '$re - ${-im}j' : '$re + ${im}j';
}
