import 'dart:typed_data';
import 'dart:html' as html; // ignore: avoid_web_libraries_in_flutter
import 'package:flutter/material.dart';

// Your existing util helper that creates/revokes blob/object URLs.
import '../util/web_object_url_web.dart';

/// Simple PDF iframe viewer for web with a tiny toolbar:
/// - page box (1-based)
/// - "Save page" -> calls [onSavePage(page1)]
/// - "Open tab"
class WebPdfHtmlView extends StatefulWidget {
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
  State<WebPdfHtmlView> createState() => _WebPdfHtmlViewState();
}

class _WebPdfHtmlViewState extends State<WebPdfHtmlView> {
  late final TextEditingController _pageCtrl;
  String? _objectUrl;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _objectUrl = WebObjectUrl.createFromBytes(
      widget.bytes,
      mimeType: 'application/pdf',
    );
    _pageCtrl = TextEditingController(text: widget.initialPage.toString());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    final url = _objectUrl;
    if (url != null) {
      WebObjectUrl.revoke(url);
    }
    super.dispose();
  }

  void _goToPage(int page1) {
    // Update iframe to requested page (also fits to page).
    final url = _objectUrl;
    if (url == null) return;
    final src = '$url#page=$page1&zoom=page-fit';
    _iframe?.src = src;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 34,
                  child: TextField(
                    controller: _pageCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Page',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                    ),
                    onSubmitted: (val) {
                      final p = int.tryParse(val);
                      if (p != null && p > 0) _goToPage(p);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final p = int.tryParse(_pageCtrl.text);
                    if (p == null || p < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid page')),
                      );
                      return;
                    }
                    widget.onSavePage?.call(p);
                    _goToPage(p);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save page'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final url = _objectUrl;
                    if (url == null) return;
                    final p = int.tryParse(_pageCtrl.text) ?? widget.initialPage;
                    html.window.open(
                      '$url#page=$p&zoom=page-fit',
                      '_blank',
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open tab'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: HtmlElementView.fromTagName(
            tagName: 'iframe',
            onElementCreated: (el) {
              final ifr = el as html.IFrameElement;
              _iframe = ifr;
              ifr.style
                ..border = 'none'
                ..width = '100%'
                ..height = '100%';
              final url = _objectUrl;
              if (url != null) {
                ifr.src = '$url#page=${widget.initialPage}&zoom=page-fit';
              }
            },
          ),
        ),
      ],
    );
  }
}
