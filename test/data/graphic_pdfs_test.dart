// Guards the one failure GraphicPdfs cannot detect about itself: a declared
// entry whose PDF is not actually in the bundle.
//
// The map is hand-maintained by design (Keith picked 4 of 125 on 2026-07-30), so
// the realistic mistake is adding a row and forgetting the file, or renaming the
// file and leaving the row. Either ships a Download button that fails on tap,
// which is worse than no button at all.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/graphic_pdfs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GraphicPdfs', () {
    test('every declared PDF is actually bundled and is a real PDF', () async {
      expect(GraphicPdfs.assetNames, isNotEmpty);
      for (final String name in GraphicPdfs.assetNames) {
        final String? path = GraphicPdfs.path(name);
        expect(path, isNotNull, reason: '$name has no path');
        final ByteData data = await rootBundle.load(path!);
        expect(data.lengthInBytes, greaterThan(1024),
            reason: '$path is suspiciously small');
        // %PDF- magic. A missing asset would throw above; a wrong-format file
        // would not, and would fail only in the user's hands.
        final String magic = String.fromCharCodes(
            data.buffer.asUint8List(data.offsetInBytes, 5));
        expect(magic, '%PDF-', reason: '$path is not a PDF');
      }
    });

    test('every declared PDF has a matching SVG, so the stems cannot drift',
        () async {
      for (final String name in GraphicPdfs.assetNames) {
        final ByteData svg =
            await rootBundle.load('assets/tool-graphics/$name.svg');
        expect(svg.lengthInBytes, greaterThan(0),
            reason: 'no SVG for declared PDF $name');
      }
    });

    test('has() and title() agree with path()', () {
      for (final String name in GraphicPdfs.assetNames) {
        expect(GraphicPdfs.has(name), isTrue);
        expect(GraphicPdfs.title(name), isNotNull);
        expect(GraphicPdfs.title(name), isNotEmpty);
      }
      expect(GraphicPdfs.has('no-such-graphic'), isFalse);
      expect(GraphicPdfs.path('no-such-graphic'), isNull);
      expect(GraphicPdfs.title('no-such-graphic'), isNull);
    });
  });
}
