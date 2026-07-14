// THE FAKES SAID YES. THE SWIFT SAID NOTHING. THE PHONE BELIEVED THE SWIFT.
//
// THE BUG THIS FILE EXISTS TO MAKE IMPOSSIBLE (2026-07-14):
//
// `ShortcutsBridge.store(json:)` stamped every delivery into `latestPayloadAtKey`.
// `ShortcutsBridge.storeLive(wifiJson:cellularJson:)` DID NOT — and storeLive is the
// path the combined "WLAN Pros Live" Shortcut actually uses
// (`ReceiveLiveDetailsIntent.perform()` → storeLive). So EVERY LIVE SAMPLE refreshed
// the payload while refreshing NOTHING that proved the payload was fresh.
//
// That silently gutted the liveness check written to fix the PREVIOUS round's bug.
// `WifiMonitorController._loopIsAlive()` asks `payloadReceivedAt()` whether a loop is
// genuinely delivering. It survives on device only because an in-memory short-circuit
// (`_sampleSinceStart`) usually answers first — but on a SCENE REBUILD the controller
// is brand new, that flag is false, and the App Group stamp is the ONLY witness left.
// It was stale or absent, so a perfectly healthy running loop would be judged dead and
// torn down. The check failed exactly where it was the only thing standing.
//
// WHY 4,282 TESTS DID NOT CATCH IT — AND WHY NO DART TEST EVER COULD.
// Every Dart fake models the App Group in Dart, and every one of them sets
// `payloadAt = DateTime.now()` on delivery. They encoded what the native side SHOULD
// do. The native side did not do it. A Dart test cannot execute Swift, so the
// divergence between the fake and the real bridge was structurally invisible to the
// entire suite — including to `live_loop_scene_rebuild_test.dart`, the file written
// specifically to drive the scene-rebuild path. It was GREEN because its fake was
// WRONG, which is the most expensive kind of green there is.
//
// So the guard cannot be another fake. It has to read the SWIFT.
//
// This is a MECHANICAL check on the source text — the same species as
// `platform_capability_invariant_test.dart`, and it is deliberately dumb: it cannot
// be socially deferred to, it does not care how confident anyone was in review, and
// it fails on a diff rather than on a device three days later.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The App Group key that holds the most recent Wi-Fi payload.
const String _kPayloadKey = 'latestPayloadKey';

/// The App Group key that holds WHEN that payload landed — the only evidence that
/// survives a scene teardown and can tell a live loop from a dead flag.
const String _kStampKey = 'latestPayloadAtKey';

/// The helper every writer must funnel through.
const String _kStampFn = 'stampPayloadDelivery';

File _bridgeFile() {
  final File f = File('ios/Runner/ShortcutsBridge.swift');
  if (!f.existsSync()) {
    fail('ios/Runner/ShortcutsBridge.swift not found from ${Directory.current.path}');
  }
  return f;
}

/// STRIPS COMMENTS. THIS LINE IS THE DIFFERENCE BETWEEN A GUARD AND A DECORATION.
///
/// The first cut of this file matched the raw source text — and a hand-injected
/// mutant that DELETED the `stampPayloadDelivery()` CALL from `storeLive` still
/// passed, because the explanatory comment sitting directly above the deleted line
/// says the words "stampPayloadDelivery". The guard was reading the PROSE ABOUT the
/// fix and scoring it as the fix. It would have gone green on the exact bug it was
/// written to catch, and it would have done so more convincingly every time someone
/// improved the comment.
///
/// A test that passes because of a comment is not a weak test, it is a FALSE one. So
/// the invariant is enforced against CODE ONLY.
String _stripComments(String swift) {
  final StringBuffer out = StringBuffer();
  bool inBlock = false;
  for (final String line in swift.split('\n')) {
    String l = line;
    if (inBlock) {
      final int end = l.indexOf('*/');
      if (end == -1) continue;
      l = l.substring(end + 2);
      inBlock = false;
    }
    // Strip /* ... */ opened on this line.
    while (true) {
      final int start = l.indexOf('/*');
      if (start == -1) break;
      final int end = l.indexOf('*/', start + 2);
      if (end == -1) {
        l = l.substring(0, start);
        inBlock = true;
        break;
      }
      l = l.substring(0, start) + l.substring(end + 2);
    }
    // Strip // to end of line. (No string literal in this file contains "//".)
    final int slash = l.indexOf('//');
    if (slash != -1) l = l.substring(0, slash);
    out.writeln(l);
  }
  return out.toString();
}

/// Extracts the body of a `static func <name>(` from the Swift source by brace
/// matching. Crude on purpose: no Swift parser, no dependency, nothing to rot.
String _funcBody(String src, String name) {
  final int sig = src.indexOf('static func $name(');
  expect(sig, isNot(-1), reason: 'ShortcutsBridge.$name is gone or was renamed. '
      'If it moved, this invariant must move with it — do not delete the guard.');
  final int open = src.indexOf('{', sig);
  int depth = 0;
  for (int i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  fail('unbalanced braces reading $name');
}

void main() {
  group('APP GROUP INVARIANT: every Wi-Fi payload write STAMPS its delivery time',
      () {
    late String src;

    // CODE ONLY. See [_stripComments] — a raw-text version of this guard went GREEN
    // on the very mutant it exists to catch, because a comment mentioned the helper
    // by name.
    setUp(() => src = _stripComments(_bridgeFile().readAsStringSync()));

    test('the guard reads CODE, not comments (the guard on the guard)', () {
      // Meta-assertion, and it is not ceremony: it pins the one property whose loss
      // silently turns this whole file into a decoration. If someone "simplifies"
      // _stripComments away, this fails immediately rather than three releases later
      // on Keith's phone.
      const String sample = '''
static func fake() {
  // stampPayloadDelivery() latestPayloadAtKey
  defaults?.set(x, forKey: latestPayloadKey)
}
''';
      final String stripped = _stripComments(sample);
      expect(stripped.contains('stampPayloadDelivery'), isFalse,
          reason: 'a mention in a COMMENT must never satisfy the stamp invariant');
      expect(stripped.contains('latestPayloadKey'), isTrue,
          reason: 'real code must survive the strip');
    });

    test(
        'storeLive() stamps the delivery — THE LIVE LOOP RUNS THROUGH HERE, and for '
        'one release it wrote the payload without dating it', () {
      final String body = _funcBody(src, 'storeLive');

      expect(
        body.contains(_kPayloadKey),
        isTrue,
        reason: 'storeLive must still be a writer of the Wi-Fi payload; if it is '
            'not, this invariant needs rewriting, not deleting',
      );
      expect(
        body.contains(_kStampFn) || body.contains(_kStampKey),
        isTrue,
        reason: 'THE BUG, IN ONE ASSERTION. storeLive() is the delivery path of the '
            'recursive "WLAN Pros Live" Shortcut — every live sample, every cycle. '
            'Writing the payload without writing the stamp leaves the app unable to '
            'prove its own live loop is alive the moment the scene is rebuilt and '
            'the in-memory short-circuit is gone. The loop then gets torn down as '
            '"dead" while it is happily delivering.',
      );
    });

    test('store() stamps the delivery', () {
      final String body = _funcBody(src, 'store');
      expect(body.contains(_kPayloadKey), isTrue);
      expect(body.contains(_kStampFn) || body.contains(_kStampKey), isTrue);
    });

    test(
        'THE GENERAL RULE: no function may write the payload key without stamping. '
        'A future third writer is caught the day it is added, not the day it ships',
        () {
      // Walk every `static func` and enforce the pairing. This is the assertion that
      // makes the invariant hold for code NOBODY HAS WRITTEN YET — the two tests
      // above only pin the two writers that exist today, and the whole lesson of this
      // bug is that a second writer appeared and nobody noticed it had drifted.
      final RegExp fn = RegExp(r'static func (\w+)\s*\(');
      final List<String> offenders = <String>[];

      for (final RegExpMatch m in fn.allMatches(src)) {
        final String name = m.group(1)!;
        // The reader and the stamper itself are not writers of the payload.
        if (name == 'payloadReceivedAt' || name == _kStampFn) continue;
        final String body = _funcBody(src, name);
        // Only interested in functions that SET the payload key. `markShortcutMissing`
        // REMOVES it (removeObject), which is a deletion, not a delivery — a deletion
        // must not stamp a delivery time, so it is correctly excluded here.
        final bool writesPayload =
            RegExp(r'set\([^)]*forKey:\s*' + _kPayloadKey).hasMatch(body) ||
                RegExp(r'\.set\(\s*\w+,\s*forKey:\s*' + _kPayloadKey).hasMatch(body);
        if (!writesPayload) continue;
        final bool stamps =
            body.contains(_kStampFn) || body.contains(_kStampKey);
        if (!stamps) offenders.add(name);
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These functions write $_kPayloadKey but never stamp $_kStampKey: '
            '$offenders.\n\n'
            'A payload with no delivery time is a payload the app cannot date, and a '
            'payload it cannot date is one it must refuse to trust (GL-005). That '
            'refusal is what tears down a healthy live loop. Call $_kStampFn() — it '
            'exists precisely so these two writes can never drift apart again.',
      );
    });
  });
}
