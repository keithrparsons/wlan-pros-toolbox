// ═══════════════════════════════════════════════════════════════════════════
// REFERENCE-VECTOR VERIFICATION — PART B (GEODESY)
//
// Expected values transcribed from
//   Deliverables/2026-07-11-calculator-verification/REFERENCE-VECTORS.md §B.
// The geodesy vectors were chosen to be ANALYTICALLY EXACT (πR/2, πR/3,
// arctan(√2), arctan(1/√2)) rather than hand-computed on real coordinates —
// which makes them stronger tests than any city pair.
//
// Reference Earth radius: R = 6,371.0088 km (IUGG mean radius R₁).
// The app uses R = 6371 in all four of its independent declarations. The
// vectors' tolerances were written to accept that (±0.02 km) — see the
// findings for the one place where that tolerance does not actually stretch
// far enough.
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ IF A TEST IN THIS FILE FAILS, THAT IS THE DELIVERABLE.                   │
// │ Do NOT change an expected value. Do NOT widen a tolerance.               │
// └──────────────────────────────────────────────────────────────────────────┘
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/maidenhead_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dist_bearing_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/final_point_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/midpoint_screen.dart';

import 'reference_vector_expect.dart';

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // §B1 — HAVERSINE DISTANCE + INITIAL BEARING
  // ═════════════════════════════════════════════════════════════════════════
  group('§B1 Haversine + bearing — analytically exact vectors', () {
    test('B1-1  (0,0) → (0,90): quarter circumference, bearing 90°', () {
      expectVector(
        id: 'B1-1',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (0, 90)',
        expected: 10007.557, // = πR/2, R = 6371.0088
        actual: DistBearingScreen.haversineKm(0, 0, 0, 90),
        tolerance: 0.02,
        unit: 'km',
        trap: 'pins R exactly. R = 6378.137 (WGS-84 equatorial) gives 10018.75',
      );
      expectVector(
        id: 'B1-1 (bearing)',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (0, 90)',
        expected: 90.0,
        actual: DistBearingScreen.bearingDeg(0, 0, 0, 90),
        tolerance: 0.01,
        unit: '°',
      );
    });

    test('B1-2  (0,0) → (90,0): to the pole  [catches a lat/lon swap]', () {
      expectVector(
        id: 'B1-2',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (90, 0)',
        expected: 10007.557,
        actual: DistBearingScreen.haversineKm(0, 0, 90, 0),
        tolerance: 0.02,
        unit: 'km',
      );
      expectVector(
        id: 'B1-2 (bearing)',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (90, 0)',
        expected: 0.0,
        actual: DistBearingScreen.bearingDeg(0, 0, 90, 0),
        tolerance: 0.01,
        unit: '°',
      );
    });

    test('B1-3  (0,0) → (0,180): half circumference (πR)', () {
      expectVector(
        id: 'B1-3',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (0, 180)',
        expected: 20015.115, // = πR, R = 6371.0088
        actual: DistBearingScreen.haversineKm(0, 0, 0, 180),
        tolerance: 0.02,
        unit: 'km',
      );
    });

    test('B1-4  (0,0) → (45,0): πR/4', () {
      expectVector(
        id: 'B1-4',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (45, 0)',
        expected: 5003.779,
        actual: DistBearingScreen.haversineKm(0, 0, 45, 0),
        tolerance: 0.02,
        unit: 'km',
      );
      expectVector(
        id: 'B1-4 (bearing)',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (45, 0)',
        expected: 0.0,
        actual: DistBearingScreen.bearingDeg(0, 0, 45, 0),
        tolerance: 0.01,
        unit: '°',
      );
    });

    test('B1-5  (0,0) → (45,45): THE key vector — πR/3, bearing atan(1/√2)',
        () {
      // The only vector not on the equator and not on a meridian, so it is the
      // only one that exercises the cos(φ1)·cos(φ2) term — precisely the term
      // that vanishes in every degenerate case.
      expectVector(
        id: 'B1-5',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (45, 45)',
        expected: 6671.705, // = πR/3
        actual: DistBearingScreen.haversineKm(0, 0, 45, 45),
        tolerance: 0.02,
        unit: 'km',
        trap: 'pass B1-1..B1-4 but fail this one → the bug is in cos(φ1)·cos(φ2)',
      );
      expectVector(
        id: 'B1-5 (bearing)',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (45, 45)',
        expected: 35.264390,
        actual: DistBearingScreen.bearingDeg(0, 0, 45, 45),
        tolerance: 0.01,
        unit: '°',
      );
    });

    test('B1-6  identical points → 0 km', () {
      expectVector(
        id: 'B1-6',
        tool: 'Distance & Bearing',
        input: '(10, 20) → (10, 20)',
        expected: 0.0,
        actual: DistBearingScreen.haversineKm(10, 20, 10, 20),
        tolerance: 0.02,
        unit: 'km',
      );
    });

    test('B1-7  (0,0) → (0,−90): bearing 270°  [atan2 quadrant + 0–360 wrap]',
        () {
      expectVector(
        id: 'B1-7',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (0, −90)',
        expected: 10007.557,
        actual: DistBearingScreen.haversineKm(0, 0, 0, -90),
        tolerance: 0.02,
        unit: 'km',
      );
      expectVector(
        id: 'B1-7 (bearing)',
        tool: 'Distance & Bearing',
        input: '(0, 0) → (0, −90)',
        expected: 270.0,
        actual: DistBearingScreen.bearingDeg(0, 0, 0, -90),
        tolerance: 0.01,
        unit: '°',
        trap: 'atan instead of atan2 returns −90; no 0–360 normalisation also '
            'returns −90',
      );
    });

    test('B1 output-unit conversions (extracted from the State getters)', () {
      // km → mi / m / ft. Lifted out of _DistBearingScreenState so the display
      // conversions are callable. 1 km = 0.621371 mi = 0.539957 NM.
      expectVector(
        id: 'B1-fm7 (km→mi)',
        tool: 'Distance & Bearing',
        input: '1 km → miles',
        expected: 0.621371,
        actual: DistBearingScreen.kmToMiles(1),
        tolerance: 0.000001,
        unit: 'mi',
      );
      expectVector(
        id: 'B1-fm7 (km→m)',
        tool: 'Distance & Bearing',
        input: '1 km → metres',
        expected: 1000.0,
        actual: DistBearingScreen.kmToMeters(1),
        tolerance: 0.0001,
        unit: 'm',
      );
      expectVector(
        id: 'B1-fm7 (km→ft)',
        tool: 'Distance & Bearing',
        input: '1 km → feet (exact: 1000 / 0.3048 = 3280.8399)',
        expected: 3280.8399,
        actual: DistBearingScreen.kmToFeet(1),
        tolerance: 0.01,
        unit: 'ft',
      );
      // Reverse bearing.
      expect(DistBearingScreen.reverseBearingDeg(90), closeTo(270, 1e-9));
      expect(DistBearingScreen.reverseBearingDeg(270), closeTo(90, 1e-9));
      expect(DistBearingScreen.reverseBearingDeg(0), closeTo(180, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // §B2 — MIDPOINT
  // The midpoint is NOT the arithmetic mean of the lats and lons. B2-2 and
  // B2-3 are the trap-explainers: in both, the naive average is CORRECT, which
  // is why a developer who spot-checks with an equator or meridian pair
  // concludes the shortcut works. B2-1 is the one that must be in any suite.
  // ═════════════════════════════════════════════════════════════════════════
  group('§B2 Midpoint — not the arithmetic mean', () {
    test('B2-1  (45,0) + (45,90) → (54.7356, 45)  [THE killer vector]', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(45, 0, 45, 90);
      expectVector(
        id: 'B2-1 (lat)',
        tool: 'Midpoint',
        input: '(45, 0) → (45, 90)',
        expected: 54.735610, // = atan(√2), exact
        actual: m.lat,
        tolerance: 0.0001,
        unit: '°',
        trap: 'the naive average gives 45.0 — a 9.74° / ~1083 km miss',
      );
      expectVector(
        id: 'B2-1 (lon)',
        tool: 'Midpoint',
        input: '(45, 0) → (45, 90)',
        expected: 45.0000,
        actual: m.lon,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B2-2  (0,0) + (0,90) → (0, 45)  [naive average coincides]', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(0, 0, 0, 90);
      expectVector(
        id: 'B2-2 (lat)',
        tool: 'Midpoint',
        input: '(0, 0) → (0, 90)',
        expected: 0.0,
        actual: m.lat,
        tolerance: 0.0001,
        unit: '°',
      );
      expectVector(
        id: 'B2-2 (lon)',
        tool: 'Midpoint',
        input: '(0, 0) → (0, 90)',
        expected: 45.0,
        actual: m.lon,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B2-3  (0,0) + (90,0) → (45, 0)  [naive average coincides]', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(0, 0, 90, 0);
      expectVector(
        id: 'B2-3 (lat)',
        tool: 'Midpoint',
        input: '(0, 0) → (90, 0)',
        expected: 45.0,
        actual: m.lat,
        tolerance: 0.0001,
        unit: '°',
      );
      expectVector(
        id: 'B2-3 (lon)',
        tool: 'Midpoint',
        input: '(0, 0) → (90, 0)',
        expected: 0.0,
        actual: m.lon,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B2-4  (0,0) + (45,45) → (23.5651, 20.9052)', () {
      // ⚠ REFERENCE-VECTORS.md flags this vector itself: "I hand-derived it and
      // it has no closed form; confirm it independently before relying on it."
      // It is run here exactly as written. Reported, not adjudicated.
      final MidpointResult m = MidpointScreen.sphereMidpoint(0, 0, 45, 45);
      expectVector(
        id: 'B2-4 (lat)',
        tool: 'Midpoint',
        input: '(0, 0) → (45, 45)',
        expected: 23.5651,
        actual: m.lat,
        tolerance: 0.001,
        unit: '°',
        trap: 'Pax flagged B2-4 as hand-derived and unconfirmed',
      );
      expectVector(
        id: 'B2-4 (lon)',
        tool: 'Midpoint',
        input: '(0, 0) → (45, 45)',
        expected: 20.9052,
        actual: m.lon,
        tolerance: 0.001,
        unit: '°',
        trap: 'Pax flagged B2-4 as hand-derived and unconfirmed',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // §B3 — DESTINATION POINT (direct problem)
  // ═════════════════════════════════════════════════════════════════════════
  group('§B3 Destination point', () {
    test('B3-1  (0,0), 90°, 5003.779 km → (0, 45)', () {
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        90.0,
        5003.779,
      );
      expectVector(
        id: 'B3-1 (lat)',
        tool: 'Final Point',
        input: '(0, 0), brg 90°, 5003.779 km',
        expected: 0.0,
        actual: d.latitude,
        tolerance: 0.0001,
        unit: '°',
      );
      expectVector(
        id: 'B3-1 (lon)',
        tool: 'Final Point',
        input: '(0, 0), brg 90°, 5003.779 km',
        expected: 45.0,
        actual: d.longitude,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B3-2  (0,0), 0°, 5003.779 km → (45, 0)', () {
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        0.0,
        5003.779,
      );
      expectVector(
        id: 'B3-2 (lat)',
        tool: 'Final Point',
        input: '(0, 0), brg 0°, 5003.779 km',
        expected: 45.0,
        actual: d.latitude,
        tolerance: 0.0001,
        unit: '°',
      );
      expectVector(
        id: 'B3-2 (lon)',
        tool: 'Final Point',
        input: '(0, 0), brg 0°, 5003.779 km',
        expected: 0.0,
        actual: d.longitude,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B3-3  (0,0), 35.2644°, 6671.705 km → (45, 45)  [inverse of B1-5]',
        () {
      // Exact to machine precision: sin(35.264390°) = 1/√3, cos = √(2/3).
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        35.2644,
        6671.705,
      );
      expectVector(
        id: 'B3-3 (lat)',
        tool: 'Final Point',
        input: '(0, 0), brg 35.2644°, 6671.705 km',
        expected: 45.0,
        actual: d.latitude,
        tolerance: 0.0001,
        unit: '°',
        trap: 'the exact round-trip inverse of B1-5',
      );
      expectVector(
        id: 'B3-3 (lon)',
        tool: 'Final Point',
        input: '(0, 0), brg 35.2644°, 6671.705 km',
        expected: 45.0,
        actual: d.longitude,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B3-4  (0,0), 90°, 10007.557 km → (0, 90)', () {
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        90.0,
        10007.557,
      );
      expectVector(
        id: 'B3-4 (lat)',
        tool: 'Final Point',
        input: '(0, 0), brg 90°, 10007.557 km (σ = 90°)',
        expected: 0.0,
        actual: d.latitude,
        tolerance: 0.0001,
        unit: '°',
      );
      expectVector(
        id: 'B3-4 (lon)',
        tool: 'Final Point',
        input: '(0, 0), brg 90°, 10007.557 km (σ = 90°)',
        expected: 90.0,
        actual: d.longitude,
        tolerance: 0.0001,
        unit: '°',
      );
    });

    test('B3-5  (0,0), 180°, 5003.779 km → (−45, 0 or 180)', () {
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        180.0,
        5003.779,
      );
      expectVector(
        id: 'B3-5 (lat)',
        tool: 'Final Point',
        input: '(0, 0), brg 180°, 5003.779 km',
        expected: -45.0,
        actual: d.latitude,
        tolerance: 0.0001,
        unit: '°',
      );
      // Longitude is degenerate on the meridian — the vector accepts 0 or 180.
      final double lon = d.longitude.abs();
      expect(
        lon < 0.0001 || (lon - 180).abs() < 0.0001,
        isTrue,
        reason: 'B3-5: longitude is degenerate southbound on the meridian; '
            'the vector accepts 0° or 180°. Got ${d.longitude}',
      );
    });

    test('B3 round trip — B1-5 and B3-3 are inverses', () {
      final DestinationPoint d = FinalPointScreen.destination(
        0,
        0,
        DistBearingScreen.bearingDeg(0, 0, 45, 45),
        DistBearingScreen.haversineKm(0, 0, 45, 45),
      );
      expect(
        d.latitude,
        closeTo(45.0, 0.0001),
        reason: 'B1-5 → B3-3 round trip must return to (45, 45)',
      );
      expect(d.longitude, closeTo(45.0, 0.0001));
    });

    test('B3 distance-unit paths', () {
      expect(FinalPointScreen.distToKm(1, FpDistUnit.km), closeTo(1, 1e-9));
      expect(
        FinalPointScreen.distToKm(1000, FpDistUnit.m),
        closeTo(1, 1e-9),
        reason: '1000 m = 1 km',
      );
      expectVector(
        id: 'B3 (mi→km)',
        tool: 'Final Point',
        input: '1 mi → km',
        expected: 1.609344,
        actual: FinalPointScreen.distToKm(1, FpDistUnit.mi),
        tolerance: 0.00001,
        unit: 'km',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // §B4 — MAIDENHEAD GRID SQUARE
  // ═════════════════════════════════════════════════════════════════════════
  group('§B4 Maidenhead — IARU Region 1, 1980', () {
    test('B4-1  Munich (48.14666, 11.60833) → JN58td', () {
      expectVectorString(
        id: 'B4-1',
        tool: 'Maidenhead',
        input: 'lat = 48.14666, lon = 11.60833',
        expected: 'JN58td',
        actual: Maidenhead.encode(48.14666, 11.60833),
        trap: 'a lat/lon swap in the interleave gives the valid-looking "NJ85dt"',
      );
    });

    test('B4-2  JN58td → CENTRE (48.14583, 11.62500)', () {
      final MaidenheadCell c = Maidenhead.decode('JN58td')!;
      expectVector(
        id: 'B4-2 (lat)',
        tool: 'Maidenhead',
        input: 'JN58td → centre latitude',
        expected: 48.14583,
        actual: c.centerLat,
        tolerance: 0.00001,
        unit: '°',
      );
      expectVector(
        id: 'B4-2 (lon)',
        tool: 'Maidenhead',
        input: 'JN58td → centre longitude',
        expected: 11.62500,
        actual: c.centerLon,
        tolerance: 0.00001,
        unit: '°',
      );
    });

    test('B4-3  JN58td → SW CORNER (48.12500, 11.58333)', () {
      final MaidenheadCell c = Maidenhead.decode('JN58td')!;
      expectVector(
        id: 'B4-3 (lat)',
        tool: 'Maidenhead',
        input: 'JN58td → SW-corner latitude',
        expected: 48.12500,
        actual: c.swLat,
        tolerance: 0.00001,
        unit: '°',
        trap: 'centre vs SW corner differ by ~2.3 km lat / ~3 km lon — the app '
            'must say which it returns',
      );
      expectVector(
        id: 'B4-3 (lon)',
        tool: 'Maidenhead',
        input: 'JN58td → SW-corner longitude',
        expected: 11.58333,
        actual: c.swLon,
        tolerance: 0.00001,
        unit: '°',
      );
    });

    test('B4-4  (0, 0) → JJ00aa  [the floor() boundary]', () {
      expectVectorString(
        id: 'B4-4',
        tool: 'Maidenhead',
        input: 'lat = 0.0, lon = 0.0',
        expected: 'JJ00aa',
        actual: Maidenhead.encode(0.0, 0.0),
        trap: 'a floor() on 9.0 that drifts to 8.9999999 yields I, not J',
      );
    });

    test('B4-5  (−90, −180) → AA00aa', () {
      expectVectorString(
        id: 'B4-5',
        tool: 'Maidenhead',
        input: 'lat = −90.0, lon = −180.0',
        expected: 'AA00aa',
        actual: Maidenhead.encode(-90.0, -180.0),
      );
    });

    test('B4-6  (89.9999, 179.9999) → RR99xx  [top of range]', () {
      expectVectorString(
        id: 'B4-6',
        tool: 'Maidenhead',
        input: 'lat = 89.9999, lon = 179.9999',
        expected: 'RR99xx',
        actual: Maidenhead.encode(89.9999, 179.9999),
        trap: 'field alphabet is A–R (18 values), subsquare a–x (24) — not 26',
      );
    });

    test('B4 encode/decode round trip through the centre', () {
      final MaidenheadCell c = Maidenhead.decode('JN58td')!;
      expectVectorString(
        id: 'B4 (round trip)',
        tool: 'Maidenhead',
        input: 'JN58td → centre → encode',
        expected: 'JN58td',
        actual: Maidenhead.encode(c.centerLat, c.centerLon),
      );
    });
  });
}
