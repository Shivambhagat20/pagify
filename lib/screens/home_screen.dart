import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _selectedFile;
  int? _lastReadPage; // 0-based for storage, we display 1-based

  String _keyForPath(String path) =>
      'last_page_${base64Url.encode(utf8.encode(path))}';

  Future<void> _loadLastPageForPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastReadPage = prefs.getInt(_keyForPath(path));
    });
  }

  Future<void> _pickPDF() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _selectedFile = File(path);

      // load last page for THIS file
      final prefs = await SharedPreferences.getInstance();
      final startPage = prefs.getInt(_keyForPath(path)) ?? 0; // 0-based

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/reader',
        arguments: {
          'file': _selectedFile!,
          'startPage': startPage, // 0-based
        },
      );

      // optional: update UI showing last read page on homescreen
      _loadLastPageForPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = (_selectedFile != null && _lastReadPage != null)
        ? 'Resume at page ${(_lastReadPage! + 1)}'
        : 'Pick a PDF to start';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagify'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _pickPDF,
              icon: const Icon(Icons.folder_open),
              label: const Text('Pick PDF to Read'),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
