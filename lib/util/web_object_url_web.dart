import 'dart:typed_data';
import 'dart:html' as html;

/// Creates and revokes blob: URLs for PDF bytes on the web.
class WebObjectUrl {
  static String createFromBytes(Uint8List bytes, {String mimeType = 'application/pdf'}) {
    final blob = html.Blob(<Object>[bytes], mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  }

  static void revoke(String url) {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  }
}
