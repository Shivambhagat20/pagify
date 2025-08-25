import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Placeholder used on non-web platforms (ReaderScreen uses Syncfusion there).
class WebPdfHtmlView extends StatelessWidget {
  final Uint8List bytes;
  final int startPage;

  const WebPdfHtmlView({
    super.key,
    required this.bytes,
    this.startPage = 1,
  });

  @override
  Widget build(BuildContext context) {
    assert(!kIsWeb, 'WebPdfHtmlView should only be used on web.');
    return const SizedBox.shrink();
  }
}
