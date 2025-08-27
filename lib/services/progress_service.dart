import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores/reads last page both locally (SharedPreferences)
/// and in Firestore when a user is signed in.
/// The page number is always 0-based here.
class ProgressService {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  String _localKey(String docId) => 'resume_v2:$docId';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  bool get _hasUser => _auth.currentUser != null;

  /// Read best-known last page (0-based).
  /// Prefs wins if it has a higher number; otherwise Firestore wins if available.
  Future<int?> getLastPage(String docId) async {
    int? best;

    // Local
    try {
      final p = await SharedPreferences.getInstance();
      best = p.getInt(_localKey(docId));
    } catch (_) {}

    // Remote
    if (_hasUser) {
      try {
        final uid = _auth.currentUser!.uid;
        final snap = await _db
            .collection('readingProgress')
            .doc(uid)
            .collection('docs')
            .doc(docId)
            .get();
        if (snap.exists) {
          final v = (snap.data()?['lastPage'] as num?)?.toInt();
          if (v != null) {
            if (best == null || v > best) best = v;
          }
        }
      } catch (_) {}
    }
    return best;
  }

  /// Store last page (0-based) to both local and (if signed in) Firestore.
  Future<void> setLastPage(String docId, int lastPage0) async {
    // Local
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_localKey(docId), lastPage0);
    } catch (_) {}

    // Remote
    if (_hasUser) {
      try {
        final uid = _auth.currentUser!.uid;
        await _db
            .collection('readingProgress')
            .doc(uid)
            .collection('docs')
            .doc(docId)
            .set({
          'lastPage': lastPage0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}
