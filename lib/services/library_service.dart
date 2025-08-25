//library_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import 'auth_service.dart';

class LibraryItem {
  final String id; // doc id
  final String name;
  final String storagePath; // gs:// or relative storage path
  final int lastPage;
  final int totalPages;
  final DateTime updatedAt;

  LibraryItem({
    required this.id,
    required this.name,
    required this.storagePath,
    required this.lastPage,
    required this.totalPages,
    required this.updatedAt,
  });

  factory LibraryItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data()!;
    return LibraryItem(
      id: d.id,
      name: j['name'] as String,
      storagePath: j['storagePath'] as String,
      lastPage: (j['lastPage'] ?? 0) as int,
      totalPages: (j['totalPages'] ?? 0) as int,
      updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'storagePath': storagePath,
        'lastPage': lastPage,
        'totalPages': totalPages,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class LibraryService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static CollectionReference<Map<String, dynamic>> _col() {
    final uid = AuthService.currentUser!.uid;
    return _db.collection('users').doc(uid).collection('library');
  }

  /// Adds or updates a PDF in the user's library.
  /// Uploads to Firebase Storage if not already there.
  static Future<LibraryItem> addOrUpdatePdf(File localFile,
      {int lastPage = 0, int totalPages = 0}) async {
    final uid = AuthService.currentUser!.uid;
    final bytes = await localFile.readAsBytes();
    final hash = sha1.convert(bytes).toString(); // stable content id
    final filename = p.basename(localFile.path);
    final path = 'users/$uid/books/$hash/$filename';

    // Upload if not exists
    final ref = _storage.ref().child(path);
    try {
      await ref.getMetadata();
    } catch (_) {
      await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    }

    // Upsert Firestore doc
    final doc = _col().doc(hash);
    await doc.set({
      'name': filename,
      'storagePath': path,
      'lastPage': lastPage,
      'totalPages': totalPages,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    final snap = await doc.get();
    return LibraryItem.fromDoc(snap);
  }

  static Stream<List<LibraryItem>> streamLibrary() {
    return _col()
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(LibraryItem.fromDoc).toList());
  }

  static Future<void> updateProgress(String id, int lastPage, int totalPages) async {
    await _col().doc(id).set({
      'lastPage': lastPage,
      'totalPages': totalPages,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Ensures a local copy exists (downloads if needed) and returns the local file path.
  static Future<String> ensureLocalCopy(LibraryItem item) async {
    final dir = await getApplicationDocumentsDirectory();
    final localPath = p.join(dir.path, 'pagify_cache', item.id, item.name);
    final f = File(localPath);
    if (await f.exists()) return f.path;

    await f.parent.create(recursive: true);
    final ref = _storage.ref().child(item.storagePath);
    final data = await ref.getData();
    await f.writeAsBytes(data!, flush: true);
    return f.path;
  }
}
