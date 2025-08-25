import 'dart:convert';
import 'dart:io' show File, Platform;
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
  /// desktop/mobile: { name, path, lastPage }
  /// web:            { name, bytes (Uint8List), lastPage } (bytes are in-memory only)
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('library_items');
    if (raw == null) return;

    final list = (jsonDecode(raw) as List)
        .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    setState(() => _items = list);
  }

  Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final metaOnly = _items.map((e) {
      final m = <String, dynamic>{
        'name': e['name'],
        'lastPage': e['lastPage'] ?? 0,
      };
      if (!kIsWeb) m['path'] = e['path']; // desktop/mobile only
      return m;
    }).toList();

    await prefs.setString('library_items', jsonEncode(metaOnly));
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: kIsWeb, // we need bytes on web
      );
      if (result == null) return;

      final f = result.files.single;

      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file bytes. Please try again.')),
          );
          return;
        }

        _items.add({
          'name': f.name,
          'bytes': bytes, // kept in memory only
          'lastPage': 0,
        });
        await _saveMeta(); // meta (name/lastPage) only
        setState(() {});
        return;
      }

      // Desktop/mobile: use file path
      final path = f.path;
      if (path == null) return;

      final existing = _items.indexWhere((e) => e['path'] == path);
      if (existing == -1) {
        _items.add({'name': f.name, 'path': path, 'lastPage': 0});
      } else {
        _items[existing]['name'] = f.name;
      }
      await _saveMeta();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (kIsWeb) {
      final bytes = item['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This entry has no PDF bytes. Re-add from + Add PDF.')),
        );
        return;
      }

      final last = (item['lastPage'] as int?) ?? 0;

      final res = await Navigator.pushNamed(
        context,
        '/reader',
        arguments: {
          'name': item['name'] as String,
          'bytes': bytes,       // <-- matches ReaderScreen
          'startPage': last,    // 0-based
        },
      );

      if (res is int) {
        item['lastPage'] = res; // 0-based
        await _saveMeta();
        if (mounted) setState(() {});
      }
      return;
    }

    // Desktop/mobile:
    final path = item['path'] as String?;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File missing on disk. Re-add from + Add PDF.')),
      );
      return;
    }

    final last = (item['lastPage'] as int?) ?? 0;
    final res = await Navigator.pushNamed(
      context,
      '/reader',
      arguments: {
        'name': item['name'] as String,
        'filePath': path,    // local file path
        'startPage': last,   // 0-based
      },
    );

    if (res is int) {
      item['lastPage'] = res; // 0-based
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
