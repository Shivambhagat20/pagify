import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Web iframe viewer (web-only) / stub (non-web)
import '../widgets/web_pdf_html_view_stub.dart'
    if (dart.library.html) '../widgets/web_pdf_html_view_web.dart';

// Desktop/Mobile: Syncfusion viewer
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

/// ---------- Models ----------
class HighlightMark {
  final int page1;     // 1-based
  final String text;   // selected snippet
  final String color;  // ARGB hex '#AARRGGBB'
  final DateTime ts;

  HighlightMark({
    required this.page1,
    required this.text,
    required this.color,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'page1': page1,
        'text': text,
        'color': color,
        'ts': ts.toIso8601String(),
      };

  static HighlightMark fromJson(Map<String, dynamic> m) => HighlightMark(
        page1: (m['page1'] as num).toInt(),
        text: (m['text'] as String?) ?? '',
        color: (m['color'] as String?) ?? '#FFFFEB3B', // yellow default
        ts: DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
      );
}

class NoteMark {
  final int page1;     // 1-based
  final String quote;  // optional selected snippet
  final String note;   // note body
  final DateTime ts;

  NoteMark({
    required this.page1,
    required this.quote,
    required this.note,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'page1': page1,
        'quote': quote,
        'note': note,
        'ts': ts.toIso8601String(),
      };

  static NoteMark fromJson(Map<String, dynamic> m) => NoteMark(
        page1: (m['page1'] as num).toInt(),
        quote: (m['quote'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        ts: DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
      );
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});
  static const String route = '/reader';

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  // ---- tuning ----
  static const double kFitZoom = 0.85; // default zoom to show whole page

  // Incoming
  late final String _name;
  late final String _docId;
  Uint8List? _bytes;
  String? _fileUrl;
  String? _filePath;
  late final int _startPage0;

  // Resume keys
  String get _resumeKeyV2 => 'resume_v2:$_docId';
  String get _resumeKeyLegacyByName => 'resume_page:$_name';

  // Desktop/Mobile viewer
  final sf.PdfViewerController _pdf = sf.PdfViewerController();
  int _totalPages = 0;
  int _currentPage1 = 1;

  // Zoom model
  final List<double> _zoomStops = const [0.75, 0.85, 1.0, 1.25, 1.5, 2.0];
  int _zoomIndex = 1; // 0.85
  bool _fitToPage = true;

  // Highlights & Notes (separate)
  List<HighlightMark> _highlights = [];
  List<NoteMark> _notes = [];

  // overlay for selection bubble
  OverlayEntry? _selOverlay;

  // highlight palette
  static final List<Color> _hlColors = [
    const Color(0xFFFFFF8D), // Yellow 200
    const Color(0xFFA5D6A7), // Green 200
    const Color(0xFFF48FB1), // Pink 200
    const Color(0xFF80DEEA), // Cyan 200
    const Color(0xFFCE93D8), // Purple 200
  ];

  bool _inited = false;

  // ---------- lifecycle ----------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    final args = (ModalRoute.of(context)?.settings.arguments ?? const {}) as Map;

    _name       = (args['name'] as String?) ?? 'Document.pdf';
    _docId      = (args['docId'] as String?) ??
        base64Url.encode(utf8.encode('name#$_name'));
    _bytes      = args['bytes'] as Uint8List?;
    _fileUrl    = args['fileUrl'] as String?;
    _filePath   = args['filePath'] as String?;
    _startPage0 = (args['startPage'] as int?) ?? 0;

    _inited = true;
    _loadMarks();
  }

  @override
  void dispose() {
    _selOverlay?.remove();
    super.dispose();
  }

  // ---------- prefs ----------
  Future<void> _saveLastPage(int zeroBased) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_resumeKeyV2, zeroBased);
    await p.setInt(_resumeKeyLegacyByName, zeroBased);
  }

  Future<int?> _loadLastPage() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_resumeKeyV2) ?? p.getInt(_resumeKeyLegacyByName);
  }

  String get _hlKey => 'marks_highlight:$_docId';
  String get _noteKey => 'marks_note:$_docId';

  Future<void> _loadMarks() async {
    final p = await SharedPreferences.getInstance();
    final rawH = p.getString(_hlKey);
    final rawN = p.getString(_noteKey);

    if (rawH != null) {
      try {
        final list = (jsonDecode(rawH) as List)
            .map((e) => HighlightMark.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _highlights = list;
      } catch (_) {}
    }
    if (rawN != null) {
      try {
        final list = (jsonDecode(rawN) as List)
            .map((e) => NoteMark.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _notes = list;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveHighlights() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _hlKey,
      jsonEncode(_highlights.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveNotes() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _noteKey,
      jsonEncode(_notes.map((e) => e.toJson()).toList()),
    );
  }

  // ---------- helpers ----------
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _onWillPop() async {
    final zero = (_currentPage1 - 1)
        .clamp(0, _totalPages > 0 ? _totalPages - 1 : 0);
    Navigator.pop(context, zero);
    return false;
  }

  void _applyZoom(double z) {
    try {
      _pdf.zoomLevel = z;
    } catch (_) {}
  }

  void _zoomToIndex(int idx) {
    final i = idx.clamp(0, _zoomStops.length - 1);
    setState(() {
      _zoomIndex = i;
      _fitToPage = (_zoomStops[i] - kFitZoom).abs() < 0.001;
    });
    _applyZoom(_zoomStops[i]);
  }

  void _zoomIn()  => _zoomToIndex(_zoomIndex + 1);
  void _zoomOut() => _zoomToIndex(_zoomIndex - 1);
  void _toggleFit() {
    if (_fitToPage) {
      final i = _zoomStops.indexOf(1.0);
      _zoomToIndex(i >= 0 ? i : 2);
    } else {
      final i = _zoomStops.indexWhere((v) => (v - kFitZoom).abs() < 0.001);
      _zoomToIndex(i >= 0 ? i : 1);
    }
  }

  // ---------- selection bubble (desktop/mobile) ----------
  static String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  static Color _hexToColor(String s) {
    try {
      final v = int.parse(s.replaceFirst('#', ''), radix: 16);
      return Color(v);
    } catch (_) {
      return const Color(0xFFFFFF8D);
    }
  }

  void _showSelectionBubble(String selected) {
    _selOverlay?.remove();

    _selOverlay = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 90,
        left: 16,
        right: 16,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Text('Highlight:',
                      style: TextStyle(color: Colors.white70)),
                  for (final c in _hlColors)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        _selOverlay?.remove();
                        _selOverlay = null;
                        await _addHighlight(selected, c);
                        try { await _pdf.clearSelection(); } catch (_) {}
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      _selOverlay?.remove();
                      _selOverlay = null;
                      await _addNoteFlow(selected);
                      try { await _pdf.clearSelection(); } catch (_) {}
                    },
                    icon: const Icon(Icons.sticky_note_2_outlined,
                        color: Colors.lightBlueAccent),
                    label: const Text('Add note',
                        style: TextStyle(color: Colors.white)),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      _selOverlay?.remove();
                      _selOverlay = null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_selOverlay!);
  }

  Future<void> _addHighlight(String selected, Color color) async {
    final page = _pdf.pageNumber;
    setState(() {
      _highlights.add(HighlightMark(
        page1: page,
        text: selected.trim(),
        color: _colorToHex(color),
        ts: DateTime.now(),
      ));
    });
    await _saveHighlights();
    _toast('Highlighted on page $page');
  }

  Future<void> _addNoteFlow(String selected) async {
    final page = _pdf.pageNumber;
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  selected.trim(),
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Write your note…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res == null || res.isEmpty) return;

    setState(() {
      _notes.add(NoteMark(
        page1: page,
        quote: selected.trim(),
        note: res,
        ts: DateTime.now(),
      ));
    });
    await _saveNotes();
    _toast('Note saved on page $page');
  }

  void _openMarksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final hs = [..._highlights]..sort((a, b) => b.ts.compareTo(a.ts));
        final ns = [..._notes]..sort((a, b) => b.ts.compareTo(a.ts));

        return DefaultTabController(
          length: 2,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bookmark_border),
                      const SizedBox(width: 8),
                      const Text('Your Annotations',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Highlights'),
                      Tab(text: 'Notes'),
                    ],
                  ),
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.55,
                    child: TabBarView(
                      children: [
                        // Highlights tab
                        Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: hs.isEmpty
                                    ? null
                                    : () async {
                                        final yes = await _confirm(ctx,
                                            'Clear all highlights?');
                                        if (!yes) return;
                                        setState(() => _highlights.clear());
                                        await _saveHighlights();
                                        if (mounted) Navigator.pop(ctx);
                                      },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: hs.isEmpty
                                  ? const Center(
                                      child: Text('No highlights yet.'),
                                    )
                                  : ListView.separated(
                                      itemCount: hs.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, i) {
                                        final h = hs[i];
                                        return ListTile(
                                          dense: true,
                                          leading: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: _hexToColor(h.color),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.black12),
                                            ),
                                          ),
                                          title: Text('Page ${h.page1}'),
                                          subtitle: Text(
                                            h.text,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontStyle: FontStyle.italic),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Open',
                                                icon: const Icon(
                                                    Icons.chevron_right),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  _pdf.jumpToPage(h.page1);
                                                },
                                              ),
                                              IconButton(
                                                tooltip: 'Delete',
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                onPressed: () async {
                                                  final yes = await _confirm(
                                                      ctx, 'Delete highlight?');
                                                  if (!yes) return;
                                                  setState(() => _highlights
                                                      .remove(h));
                                                  await _saveHighlights();
                                                  Navigator.pop(ctx);
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),

                        // Notes tab
                        Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: ns.isEmpty
                                    ? null
                                    : () async {
                                        final yes = await _confirm(
                                            ctx, 'Clear all notes?');
                                        if (!yes) return;
                                        setState(() => _notes.clear());
                                        await _saveNotes();
                                        if (mounted) Navigator.pop(ctx);
                                      },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: ns.isEmpty
                                  ? const Center(
                                      child: Text('No notes yet.'),
                                    )
                                  : ListView.separated(
                                      itemCount: ns.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (_, i) {
                                        final n = ns[i];
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(
                                              Icons.sticky_note_2_outlined),
                                          title: Text('Page ${n.page1}'),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (n.quote.isNotEmpty)
                                                Text(
                                                  n.quote,
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic),
                                                ),
                                              if (n.note.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6.0),
                                                  child: Text(n.note),
                                                ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Open',
                                                icon: const Icon(
                                                    Icons.chevron_right),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  _pdf.jumpToPage(n.page1);
                                                },
                                              ),
                                              IconButton(
                                                tooltip: 'Delete',
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                onPressed: () async {
                                                  final yes = await _confirm(
                                                      ctx, 'Delete note?');
                                                  if (!yes) return;
                                                  setState(
                                                      () => _notes.remove(n));
                                                  await _saveNotes();
                                                  Navigator.pop(ctx);
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<bool> _confirm(BuildContext ctx, String msg) async {
    return (await showDialog<bool>(
          context: ctx,
          builder: (c) => AlertDialog(
            content: Text(msg),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('OK')),
            ],
          ),
        )) ??
        false;
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final title = _name.isEmpty ? 'Reader' : _name;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            if (!kIsWeb) ...[
              IconButton(
                tooltip: 'Notes & Highlights',
                icon: const Icon(Icons.collections_bookmark_outlined),
                onPressed: _openMarksSheet,
              ),
              IconButton(
                tooltip: _fitToPage ? '100%' : 'Fit to page',
                icon: Icon(_fitToPage ? Icons.aspect_ratio : Icons.fit_screen),
                onPressed: _toggleFit,
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.zoom_out),
                onPressed: _zoomIndex > 0 ? _zoomOut : null,
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.zoom_in),
                onPressed:
                    _zoomIndex < _zoomStops.length - 1 ? _zoomIn : null,
              ),
            ],
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: kIsWeb
            ? null
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
        details:
            'Pass bytes or URL on web, or file path/bytes/URL on desktop & mobile.',
      );
    }

    // ---------------- WEB ----------------
    if (kIsWeb) {
      if (hasBytes) {
        return FutureBuilder<int?>(
          future: _loadLastPage(),
          builder: (context, snap) {
            final start1 = ((snap.data ?? _startPage0) + 1).clamp(1, 999999);
            _currentPage1 = start1;
            return WebPdfHtmlView(
              bytes: _bytes!,
              initialPage: start1,
              onSavePage: (p1) async {
                _currentPage1 = p1;
                await _saveLastPage(p1 - 1);
              },
            );
          },
        );
      }
      return const _ErrorCard(
        headline: 'URL viewing on web not enabled',
        details: 'Please add/open the PDF as bytes via the Library.',
      );
    }

    // ------------- DESKTOP/MOBILE -------------
    if (hasBytes) return _buildSfMemory(_bytes!);
    if (hasUrl)   return _buildSfNetwork(_fileUrl!);
    return _buildSfFile(_filePath!);
  }

  Widget _buildSfMemory(Uint8List bytes) {
    return sf.SfPdfViewer.memory(
      bytes,
      controller: _pdf,
      pageLayoutMode: sf.PdfPageLayoutMode.single,
      canShowScrollHead: true,
      canShowPaginationDialog: true,
      onTextSelectionChanged: (d) {
        final sel = d.selectedText?.trim() ?? '';
        if (sel.isNotEmpty) _showSelectionBubble(sel);
      },
      onDocumentLoaded: _onDocLoaded,
      onPageChanged: _onPageChanged,
      onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
    );
  }

  Widget _buildSfNetwork(String url) {
    return sf.SfPdfViewer.network(
      url,
      controller: _pdf,
      pageLayoutMode: sf.PdfPageLayoutMode.single,
      canShowScrollHead: true,
      canShowPaginationDialog: true,
      onTextSelectionChanged: (d) {
        final sel = d.selectedText?.trim() ?? '';
        if (sel.isNotEmpty) _showSelectionBubble(sel);
      },
      onDocumentLoaded: _onDocLoaded,
      onPageChanged: _onPageChanged,
      onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
    );
  }

  Widget _buildSfFile(String path) {
    return sf.SfPdfViewer.file(
      File(path),
      controller: _pdf,
      pageLayoutMode: sf.PdfPageLayoutMode.single,
      canShowScrollHead: true,
      canShowPaginationDialog: true,
      onTextSelectionChanged: (d) {
        final sel = d.selectedText?.trim() ?? '';
        if (sel.isNotEmpty) _showSelectionBubble(sel);
      },
      onDocumentLoaded: _onDocLoaded,
      onPageChanged: _onPageChanged,
      onDocumentLoadFailed: (f) => _toast('PDF failed to load: ${f.description}'),
    );
  }

  Future<void> _onDocLoaded(sf.PdfDocumentLoadedDetails details) async {
    _totalPages = details.document.pages.count;

    // 1) Fit (or 100%) first
    if (_fitToPage) {
      final i = _zoomStops.indexWhere((z) => (z - kFitZoom).abs() < 0.001);
      _zoomToIndex(i >= 0 ? i : 1);
    } else {
      final i = _zoomStops.indexOf(1.0);
      _zoomToIndex(i >= 0 ? i : 2);
    }

    // 2) Then jump to saved
    final saved0 = await _loadLastPage();
    final target1 = ((saved0 ?? _startPage0) + 1).clamp(1, _totalPages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pdf.jumpToPage(target1);
      setState(() => _currentPage1 = target1);
    });
  }

  Future<void> _onPageChanged(sf.PdfPageChangedDetails d) async {
    _currentPage1 = d.newPageNumber;
    await _saveLastPage(_currentPage1 - 1);
    if (mounted) setState(() {});
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
                    style:
                        const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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

/// Compact pager: 200px text field instead of full width.
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
            IconButton(
              onPressed: canUse ? onPrev : null,
              icon: const Icon(Icons.chevron_left),
            ),
            SizedBox(
              width: 200,
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
            IconButton(
              onPressed: canUse ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
