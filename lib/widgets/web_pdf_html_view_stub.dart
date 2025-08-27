import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Stub used on non-web targets so the app compiles everywhere.
/// This widget is never shown when kIsWeb == true.
class WebPdfHtmlView extends StatelessWidget {
  final Uint8List bytes;
  final int initialPage; // 1-based
  final ValueChanged<int>? onSavePage;

  const WebPdfHtmlView({
    super.key,
    required this.bytes,
    required this.initialPage,
    this.onSavePage,
  });

  @override
  Widget build(BuildContext context) {
    // Not used on desktop/mobile; ReaderScreen uses Syncfusion there.
    return const SizedBox.shrink();
  }
}
