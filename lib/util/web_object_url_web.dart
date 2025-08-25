// Web implementation: turn bytes into a blob URL we can give to an <iframe>.
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'dart:typed_data';

class WebObjectUrl {
  static String createFromBytes(Uint8List bytes, {String mimeType = 'application/pdf'}) {
    final blob = html.Blob([bytes], mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  }

  static void revoke(String url) {
    html.Url.revokeObjectUrl(url);
  }
}
