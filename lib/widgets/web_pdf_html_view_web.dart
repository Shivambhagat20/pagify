// Displays PDF bytes in an <iframe> using a blob: URL.
// Works on recent Flutter (HtmlElementView.fromTagName). No view registry needed.

import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';

class WebPdfHtmlView extends StatefulWidget {
  final Uint8List bytes;
  /// 1-based page number for the built-in browser viewer.
  final int startPage;

  const WebPdfHtmlView({
    super.key,
    required this.bytes,
    this.startPage = 1,
  });

  @override
  State<WebPdfHtmlView> createState() => _WebPdfHtmlViewState();
}

class _WebPdfHtmlViewState extends State<WebPdfHtmlView> {
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    // Create a blob/object URL for the PDF bytes.
    _objectUrl = html.Url.createObjectUrl(
      html.Blob(<dynamic>[widget.bytes], 'application/pdf'),
    );
  }

  @override
  void dispose() {
    final u = _objectUrl;
    if (u != null) {
      html.Url.revokeObjectUrl(u);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final src = '$_objectUrl#page=${widget.startPage}';
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (el) {
        final e = el as html.IFrameElement;
        e
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..src = src;
      },
    );
  }
}
