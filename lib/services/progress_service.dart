// lib/services/progress_service.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  String _k(String bookId) => 'progress:$bookId';

  /// Turn any filename into a short, URL-safe id we can use as a key/doc id.
  String normalizeId(String name) {
    return base64Url.encode(utf8.encode(name)).replaceAll('=', '');
  }

  /// Load last page (0-based). Tries Firestore if signed-in, otherwise local.
  Future<int?> load(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getInt(_k(bookId));

    final user = FirebaseAuth.instance.currentUser;
    final isAuthed = user != null && !user.isAnonymous;
    if (!isAuthed) return local;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('progress')
          .doc(bookId)
          .get();
      final cloud = snap.data()?['page'] as int?;
      return cloud ?? local;
    } catch (_) {
      return local;
    }
  }

  /// Save last page (0-based) locally and to Firestore (if signed-in).
  Future<void> save(String bookId, int zeroBasedPage) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(bookId), zeroBasedPage);

    final user = FirebaseAuth.instance.currentUser;
    final isAuthed = user != null && !user.isAnonymous;
    if (!isAuthed) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('progress')
        .doc(bookId)
        .set(
      {'page': zeroBasedPage, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
