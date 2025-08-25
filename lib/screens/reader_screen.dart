import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Web uses iframe widget; desktop/mobile use Syncfusion viewer.
import '../widgets/web_pdf_html_view_stub.dart'
    if (dart.library.html) '../widgets/web_pdf_html_view_web.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../services/progress_service.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});
  static const String route = '/reader';

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final String _name;
  late final String _bookId;

  Uint8List? _bytes;     // preferred on web
  String? _fileUrl;      // http/https (works everywhere)
  String? _filePath;     // desktop/mobile
  late int _startPage0;

  // desktop/mobile viewer state
  final sf.PdfViewerController _pdf = sf.PdfViewerController();
  int _totalPages = 0;
  int _currentPage1 = 1;

  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    final args = (ModalRoute.of(context)?.settings.arguments ?? const {}) as Map;

    _name       = (args['name'] as String?) ?? 'Document.pdf';
    _bookId     = ProgressService.instance.normalizeId(_name);

    _bytes      = args['bytes'] as Uint8List?;
    _fileUrl    = args['fileUrl'] as String?;
    _filePath   = args['filePath'] as String?;
    _startPage0 = (args['startPage'] as int?) ?? 0;

    _inited = true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _onWillPop() async {
    // Save last known page (0-based) and return it to the caller.
    final zero = (_currentPage1 - 1).clamp(0, _totalPages > 0 ? _totalPages - 1 : 0);
    await ProgressService.instance.save(_bookId, zero);
    if (!mounted) return false;
    Navigator.pop(context, zero);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final title = _name.isEmpty ? 'Reader' : _name;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
        body: _buildBody(),
        bottomNavigationBar: kIsWeb
            ? null // The browser’s viewer handles navigation; we can’t observe changes.
            : _Pager(
                current: _currentPage1,
                total: _totalPages,
                onPrev: () => _pdf.previousPage(),
                onNext: () => _pdf.nextPage(),
                onJump: (p1) {
                  if (_totalPages == 0) return;
                  final clamped = p1.clamp(1, _totalPages);
                  _pdf.jumpToPage(clamped);
                },
              ),
      ),
    );
  }

  Widget _buildBody() {
    final hasBytes = _bytes != null && _bytes!.isNotEmpty;
    final hasUrl   = _fileUrl != null && _fileUrl!.isNotEmpty;
    final hasPath  = _filePath != null && _filePath!.isNotEmpty;

    if (!hasBytes && !hasUrl && !hasPath) {
      return const _ErrorCard(
        headline: 'PDF not provided',
        details: 'Provide bytes/URL on web, or file path/URL/bytes on desktop.',
      );
    }

    // ---------------- WEB: prefer BYTES -> iframe; fallback to URL ----------------
    if (kIsWeb) {
      if (hasBytes) {
        return FutureBuilder<int?>(
          future: ProgressService.instance.load(_bookId),
          builder: (context, snap) {
            // 1-based for the PDF hash
            final start1 = ((snap.data ?? _startPage0) + 1).clamp(1, 999999);
            _currentPage1 = start1; // we can't observe further changes in the iframe
            return WebPdfHtmlView(bytes: _bytes!, startPage: start1);
          },
        );
      }
      if (hasUrl) {
        // Simple iframe of the network URL.
        return HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (el) {
            (el as dynamic)
              ..style.border = 'none'
              ..style.width = '100%'
              ..style.height = '100%'
              ..src = _fileUrl!;
          },
        );
      }
      return const _ErrorCard(
        headline: 'Local files are not readable in browser',
        details: 'Please add the PDF via the Library so we can read its bytes.',
      );
    }

    // --------------- DESKTOP/MOBILE: Syncfusion viewer (path/bytes/url) ---------------
    Future<void> _onLoaded(int pageCount) async {
      _totalPages = pageCount;
      final saved0 = await ProgressService.instance.load(_bookId);
      final target1 = ((saved0 ?? _startPage0) + 1).clamp(1, _totalPages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pdf.jumpToPage(target1);
        setState(() => _currentPage1 = target1);
      });
    }

    Future<void> _onChanged(int newPage1) async {
      _currentPage1 = newPage1;
      await ProgressService.instance.save(_bookId, _currentPage1 - 1);
      if (mounted) setState(() {});
    }

    if (hasBytes) {
      return sf.SfPdfViewer.memory(
        _bytes!,
        controller: _pdf,
        canShowScrollHead: true,
        canShowPaginationDialog: true,
        onDocumentLoaded: (d) => _onLoaded(d.document.pages.count),
        onPageChanged: (d) => _onChanged(d.newPageNumber),
        onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
      );
    }

    if (hasUrl) {
      return sf.SfPdfViewer.network(
        _fileUrl!,
        controller: _pdf,
        canShowScrollHead: true,
        canShowPaginationDialog: true,
        onDocumentLoaded: (d) => _onLoaded(d.document.pages.count),
        onPageChanged: (d) => _onChanged(d.newPageNumber),
        onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
      );
    }

    // Path (desktop/mobile)
    return sf.SfPdfViewer.file(
      File(_filePath!),
      controller: _pdf,
      canShowScrollHead: true,
      canShowPaginationDialog: true,
      onDocumentLoaded: (d) => _onLoaded(d.document.pages.count),
      onPageChanged: (d) => _onChanged(d.newPageNumber),
      onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
    );
  }
}

// ---------- small UI bits ----------

class _ErrorCard extends StatelessWidget {
  final String headline;
  final String details;
  const _ErrorCard({required this.headline, required this.details});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 40),
                const SizedBox(height: 12),
                Text(headline,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(details, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onJump;

  const _Pager({
    required this.current,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final canUse = total > 0;
    final ctrl = TextEditingController(text: '$current');

    return Material(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton(onPressed: canUse ? onPrev : null, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: ctrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: total == 0 ? 'Page' : '1–$total',
                  ),
                  onSubmitted: (val) {
                    final p = int.tryParse(val);
                    if (p != null && total > 0) onJump(p);
                  },
                ),
              ),
            ),
            IconButton(onPressed: canUse ? onNext : null, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}
