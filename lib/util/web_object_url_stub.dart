// Fallback for non-web builds so the code compiles everywhere.
import 'dart:typed_data';

class WebObjectUrl {
  static String createFromBytes(Uint8List bytes, {String mimeType = 'application/octet-stream'}) {
    return 'about:blank'; // not used on non-web
  }

  static void revoke(String url) {
    // no-op off web
  }
}
