// Web body for the QR PNG share seam.
//
// Browser anchor-download: wrap the rendered QR PNG bytes in a Blob, make an
// object URL, and click a hidden <a download="..."> so the browser saves the
// file. Uses package:web + dart:js_interop (the modern, wasm-safe web interop),
// kept out of the native build by the conditional import in qr_share.dart.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of the QR [png] bytes under [filename].
Future<void> shareQrPngImpl({
  required Uint8List png,
  required String filename,
}) async {
  final web.Blob blob = web.Blob(
    <web.BlobPart>[png.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final String url = web.URL.createObjectURL(blob);

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
