// Shared assertion helper for the reference-vector suite.
//
// Every expected value used with these helpers comes from
// `Deliverables/2026-07-11-calculator-verification/REFERENCE-VECTORS.md`
// (Pax, 2026-07-11), which was derived from ITU-R P.525-4, ITU-R P.530-18,
// ITU-R P.838-3, IEEE 802.3bt (via the Ethernet Alliance whitepaper),
// IEEE 802.11-2020, the Times Microwave LMR datasheets, and closed-form
// derivations from SI-exact constants — with no sight of this codebase.
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ THE ONE RULE                                                             │
// │ The `expected` value is GROUND TRUTH. If a vector and the code disagree, │
// │ we do not know which is wrong — that is a finding to REPORT, not a test  │
// │ to "fix". NEVER edit an expected value to make a test go green. NEVER    │
// │ widen a tolerance to make a test go green. A failing vector is the       │
// │ deliverable.                                                             │
// └──────────────────────────────────────────────────────────────────────────┘

import 'package:flutter_test/flutter_test.dart';

/// A percentage-of-expected tolerance, for the vectors stated as "±0.5%".
double pctTol(double expected, double percent) =>
    expected.abs() * (percent / 100.0);

String _block({
  required String id,
  required String tool,
  required String input,
  required String expected,
  required String actual,
  required String delta,
  required String tolerance,
  required String trap,
}) => <String>[
  '',
  '──────────────────────────────────────────────────────────────────',
  'REFERENCE VECTOR $id  —  $tool',
  '  input      : $input',
  '  expected   : $expected      <- REFERENCE-VECTORS.md (ground truth)',
  '  actual     : $actual      <- real app code',
  '  delta      : $delta',
  '  tolerance  : $tolerance',
  if (trap.isNotEmpty) '  trap       : $trap',
  '',
  '  The expected value is GROUND TRUTH. Do not edit it, and do not widen',
  '  the tolerance, to make this pass. Report the disagreement.',
  '──────────────────────────────────────────────────────────────────',
  '',
].join('\n');

/// Assert a real app-computed [actual] against a ground-truth [expected].
void expectVector({
  required String id,
  required String tool,
  required String input,
  required double expected,
  required double actual,
  required double tolerance,
  String unit = '',
  String trap = '',
}) {
  final double delta = actual - expected;
  final String u = unit.isEmpty ? '' : ' $unit';
  final String pct = expected == 0
      ? ''
      : '  (${(delta / expected.abs() * 100).toStringAsFixed(2)}% of expected)';

  expect(
    actual,
    closeTo(expected, tolerance),
    reason: _block(
      id: id,
      tool: tool,
      input: input,
      expected: '$expected$u',
      actual: '$actual$u',
      delta: '${delta >= 0 ? '+' : ''}$delta$u$pct',
      tolerance: '±$tolerance$u',
      trap: trap,
    ),
  );
}

/// Exact-integer variant (channel ↔ frequency, PoE counts).
void expectVectorInt({
  required String id,
  required String tool,
  required String input,
  required int? expected,
  required int? actual,
  String unit = '',
  String trap = '',
}) {
  final String u = unit.isEmpty ? '' : ' $unit';
  final String delta = (expected == null || actual == null)
      ? 'n/a (null on one side)'
      : '${actual - expected >= 0 ? '+' : ''}${actual - expected}$u';

  expect(
    actual,
    equals(expected),
    reason: _block(
      id: id,
      tool: tool,
      input: input,
      expected: '$expected$u',
      actual: '$actual$u',
      delta: delta,
      tolerance: 'exact',
      trap: trap,
    ),
  );
}

/// Exact-string variant (Maidenhead locators).
void expectVectorString({
  required String id,
  required String tool,
  required String input,
  required String expected,
  required String actual,
  String trap = '',
}) {
  expect(
    actual,
    equals(expected),
    reason: _block(
      id: id,
      tool: tool,
      input: input,
      expected: '"$expected"',
      actual: '"$actual"',
      delta: expected == actual ? 'none' : 'MISMATCH',
      tolerance: 'exact',
      trap: trap,
    ),
  );
}

/// A trap sentinel: assert the app did NOT land on a known-wrong value.
///
/// Unlike `expect(71.3, closeTo(71.3, 1e-9))` — the tautology this suite was
/// commissioned to hunt — this assertion is capable of failing: it compares a
/// real computed value against the number the *bug* would have produced.
void expectNotTheBug({
  required String id,
  required String tool,
  required String input,
  required double actual,
  required double bugValue,
  required double tolerance,
  required String bugName,
  String unit = '',
}) {
  expect(
    actual,
    isNot(closeTo(bugValue, tolerance)),
    reason: _block(
      id: id,
      tool: tool,
      input: input,
      expected: 'anything but $bugValue $unit',
      actual: '$actual $unit',
      delta: 'the app landed ON the known-wrong value',
      tolerance: '±$tolerance $unit',
      trap: 'BUG PRESENT — $bugName',
    ),
  );
}
