// Web body for the PDF share seam.
//
// Browser anchor-download: fetch the bundled asset bytes, wrap them in a Blob,
// make an object URL, and click a hidden <a download="..."> so the browser
// saves the file under the clean filename. Uses package:web + dart:js_interop
// (the modern, wasm-safe web interop), kept out of the native build by the
// conditional import in pdf_download.dart.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import 'pdf_download.dart' show ShareOrigin;

/// Generic web body: fetches the bundled [assetPath] bytes and triggers a
/// browser anchor-download under the clean [filename], typed [mimeType].
/// [shareOrigin] is unused on web. Mirrors [sharePdfImpl]; the only difference
/// is the Blob MIME type.
Future<void> shareAssetImpl({
  required String assetPath,
  required String filename,
  required String mimeType,
  ShareOrigin? shareOrigin,
}) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Uint8List bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );

  // Blob from the asset bytes, typed by [mimeType]. The byte buffer is a
  // BlobPart; the parts array is a JSArray<BlobPart>.
  final web.Blob blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final String url = web.URL.createObjectURL(blob);

  // A transient anchor with the clean download name; click it, then revoke.
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = filename
        ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
