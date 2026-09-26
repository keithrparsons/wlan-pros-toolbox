// Tests for the Wi-Fi Classroom Complex type. The wall simulator's P.2040 slab
// equations stand on these: arithmetic, the principal square root (branch
// choice decides whether a lossy wave decays or grows) and exp (a thick metal
// wall must underflow to zero, not overflow to NaN).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/complex.dart';

void _near(Complex a, Complex b, [double tol = 1e-12]) {
  expect(a.re, closeTo(b.re, tol), reason: 're of $a vs $b');
  expect(a.im, closeTo(b.im, tol), reason: 'im of $a vs $b');
}

void main() {
  test('add, subtract, negate, multiply', () {
    const Complex a = Complex(3, 4);
    const Complex b = Complex(1, -2);
    _near(a + b, const Complex(4, 2));
    _near(a - b, const Complex(2, 6));
    _near(-a, const Complex(-3, -4));
    _near(a * b, const Complex(11, -2));
    _near(Complex.j * Complex.j, const Complex(-1));
  });

  test('division, both Smith branches, and divide by zero throws', () {
    const Complex a = Complex(3, 4);
    _near(a / const Complex(1, -2), const Complex(-1, 2));
    _near(
      a / const Complex(0.5, 7),
      (a * const Complex(0.5, -7)).scale(1 / (0.25 + 49)),
    );
    expect(() => a / Complex.zero, throwsArgumentError);
  });

  test('division with a huge divisor does not overflow', () {
    // The metal wall's permittivity scale: ~1e8, squared would be 1e16 and
    // fine, but 1e200 squared overflows a naive implementation.
    const Complex big = Complex(1e200, 1e200);
    final Complex q = Complex.one / big;
    expect(q.isFinite, isTrue);
    expect(q.re, closeTo(0.5e-200, 1e-210));
    expect(q.im, closeTo(-0.5e-200, 1e-210));
  });

  test('abs, abs2, arg, conjugate', () {
    const Complex a = Complex(3, -4);
    expect(a.abs, 5);
    expect(a.abs2, 25);
    expect(a.arg, closeTo(math.atan2(-4, 3), 1e-15));
    _near(a.conjugate, const Complex(3, 4));
    expect(const Complex(1e300, 1e300).abs.isFinite, isTrue);
  });

  test('sqrt is the principal branch and squares back', () {
    for (final Complex z in <Complex>[
      const Complex(4),
      const Complex(-4),
      const Complex(0, 2),
      const Complex(5.24, -1.7),
      const Complex(1, -7.5e7),
      const Complex(-3, 0.5),
      const Complex(-3, -0.5),
    ]) {
      final Complex r = z.sqrt();
      expect(r.re, greaterThanOrEqualTo(0), reason: 'principal branch of $z');
      _near(r * r, z, 1e-9 * (1 + z.abs));
    }
    _near(const Complex(-4).sqrt(), const Complex(0, 2));
    _near(const Complex(-4, -0.0).sqrt(), const Complex(0, -2));
    _near(Complex.zero.sqrt(), Complex.zero);
  });

  test('a lossy permittivity gives a decaying root (Im < 0)', () {
    // e = e' - j e'': the wave e^(-j k sqrt(e) x) must decay with x.
    final Complex r = const Complex(5.24, -0.69).sqrt();
    expect(r.im, lessThan(0));
  });

  test('exp: Euler, and clean underflow', () {
    _near(Complex(0, math.pi).exp(), const Complex(-1), 1e-15);
    _near(const Complex(1).exp(), const Complex(math.e), 1e-15);
    final Complex tiny = const Complex(-61600, 61600).exp();
    expect(tiny, Complex.zero);
    expect(tiny.isFinite, isTrue);
  });

  test('polar', () {
    _near(Complex.polar(2, math.pi / 2), const Complex(0, 2), 1e-15);
  });
}
