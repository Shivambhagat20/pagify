import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Persisted (no raw bytes):
  /// - desktop/mobile: { name, path, lastPage, docId }
  /// - web:            { name, lastPage, docId }
  ///
  /// Session-only on web: { bytes: Uint8List }
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  // Stable IDs (used for resume keys)
  String _docIdFromPath(String path) => base64Url.encode(utf8.encode('path#$path'));
  String _docIdFromName(String name) => base64Url.encode(utf8.encode('name#$name'));

  Future<void> _loadMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('library_items');
    if (raw == null) return;

    final list = (jsonDecode(raw) as List)
        .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    // Ensure docId + sane defaults
    for (final m in list) {
      m['lastPage'] = (m['lastPage'] as int?) ?? 0;
      if (m['docId'] == null) {
        if (!kIsWeb && m['path'] is String && (m['path'] as String).isNotEmpty) {
          m['docId'] = _docIdFromPath(m['path'] as String);
        } else {
          m['docId'] = _docIdFromName(m['name'] as String? ?? 'Document.pdf');
        }
      }
    }
    setState(() => _items = list);
  }

  Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final meta = _items.map((e) {
      final m = <String, dynamic>{
        'name': e['name'],
        'lastPage': (e['lastPage'] as int?) ?? 0,
        'docId': e['docId'],
      };
      if (!kIsWeb && e['path'] is String) m['path'] = e['path'];
      return m;
    }).toList();
    await prefs.setString('library_items', jsonEncode(meta));
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: kIsWeb, // web needs bytes
      );
      if (result == null) return;

      final f = result.files.single;
      final name = f.name;

      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file bytes. Try again.')),
          );
          return;
        }

        final docId = _docIdFromName(name);
        _items.add({
          'name': name,
          'lastPage': 0,
          'docId': docId,
          'bytes': bytes, // session-only
        });
        await _saveMeta();
        if (mounted) setState(() {});
        return;
      }

      // Desktop/mobile
      final path = f.path;
      if (path == null || path.isEmpty) return;

      final docId = _docIdFromPath(path);
      final i = _items.indexWhere((e) => e['path'] == path);
      if (i == -1) {
        _items.add({'name': name, 'path': path, 'lastPage': 0, 'docId': docId});
      } else {
        _items[i]['name'] = name;
        _items[i]['docId'] = _items[i]['docId'] ?? docId;
      }
      await _saveMeta();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
  }

  Future<int?> _loadSavedResumeFor(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final name = item['name'] as String? ?? 'Document.pdf';
    final docId = item['docId'] as String? ?? _docIdFromName(name);
    final v2 = prefs.getInt('resume_v2:$docId'); // new
    if (v2 != null) return v2;
    return prefs.getInt('resume_page:$name'); // legacy
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final name = item['name'] as String? ?? 'Document.pdf';
    final docId = item['docId'] as String? ??
        (!kIsWeb && (item['path'] is String)
            ? _docIdFromPath(item['path'] as String)
            : _docIdFromName(name));

    final meta0 = (item['lastPage'] as int?) ?? 0;
    final saved0 = await _loadSavedResumeFor(item);
    final start0 = (saved0 == null) ? meta0 : (saved0 > meta0 ? saved0 : meta0);

    if (kIsWeb) {
      final bytes = item['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PDF bytes. Re-add from + Add PDF.')),
        );
        return;
      }

      final res = await Navigator.pushNamed(
        context,
        '/reader',
        arguments: {
          'name': name,
          'docId': docId,
          'bytes': bytes,
          'startPage': start0, // 0-based
        },
      );

      if (res is int) {
        item['lastPage'] = res;
        await _saveMeta();
        if (mounted) setState(() {});
      }
      return;
    }

    // Desktop/mobile
    final path = item['path'] as String?;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File missing on disk. Re-add from + Add PDF.')),
      );
      return;
    }

    final res = await Navigator.pushNamed(
      context,
      '/reader',
      arguments: {
        'name': name,
        'docId': docId,
        'filePath': path,
        'startPage': start0, // 0-based
      },
    );

    if (res is int) {
      item['lastPage'] = res;
      await _saveMeta();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          IconButton(
            tooltip: 'Add PDF',
            icon: const Icon(Icons.add),
            onPressed: _pickPdf,
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(child: Text('No books yet. Tap + to add a PDF.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = _items[i];
                final last = ((item['lastPage'] as int?) ?? 0) + 1;
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: Text(item['name'] as String),
                  subtitle: Text('Last page: $last'),
                  onTap: () => _open(item),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => _items.removeAt(i));
                      await _saveMeta();
                    },
                  ),
                );
              },
            ),
    );
  }
}
