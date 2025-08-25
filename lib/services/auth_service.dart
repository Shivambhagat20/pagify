import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  static const String _kGuestActive = 'guest_active';
  static const String _kGuestReadsLeft = 'guest_reads_left';

  Future<UserCredential> signInAsGuestLimited({int maxReads = 5}) async {
    final cred = await _auth.signInAnonymously();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_kGuestActive, true);
    final left = prefs.getInt(_kGuestReadsLeft);
    if (left == null || left < 0 || left > maxReads) {
      await prefs.setInt(_kGuestReadsLeft, maxReads);
    }
    return cred;
  }

  Future<bool> get isGuest async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGuestActive) ?? false;
  }

  Future<({int left, int used, int max})> guestUsage({int maxReads = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getInt(_kGuestReadsLeft) ?? 0;
    final used = (left <= maxReads) ? (maxReads - left) : 0;
    return (left: left, used: used, max: maxReads);
  }

  Future<bool> guestLimitReached({int maxReads = 5}) async {
    final usage = await guestUsage(maxReads: maxReads);
    return usage.left <= 0;
  }

  Future<void> incrementGuestReadsUsed({int maxReads = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    final leftNow = prefs.getInt(_kGuestReadsLeft) ?? maxReads;
    final next = (leftNow - 1).clamp(0, maxReads);
    await prefs.setInt(_kGuestReadsLeft, next);
  }

  Future<void> clearGuestFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGuestActive);
    await prefs.remove(_kGuestReadsLeft);
  }

  Future<UserCredential> signInWithGoogle() async {
    final current = _auth.currentUser;

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      try {
        final res = current == null
            ? await _auth.signInWithPopup(provider)
            : await current.linkWithPopup(provider);
        await clearGuestFlag();
        return res;
      } on FirebaseAuthException catch (e) {
        if (current != null &&
            (e.code == 'credential-already-in-use' ||
             e.code == 'provider-already-linked' ||
             e.code == 'requires-recent-login' ||
             e.code == 'operation-not-allowed')) {
          final res = await _auth.signInWithPopup(provider);
          await clearGuestFlag();
          try { await current.delete(); } catch (_) {}
          return res;
        }
        rethrow;
      }
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final provider = GoogleAuthProvider();
      try {
        final res = current == null
            ? await _auth.signInWithProvider(provider)
            : await current.linkWithProvider(provider);
        await clearGuestFlag();
        return res;
      } on FirebaseAuthException catch (e) {
        if (current != null &&
            (e.code == 'credential-already-in-use' ||
             e.code == 'provider-already-linked' ||
             e.code == 'requires-recent-login' ||
             e.code == 'operation-not-allowed')) {
          final res = await _auth.signInWithProvider(provider);
          await clearGuestFlag();
          try { await current.delete(); } catch (_) {}
          return res;
        }
        rethrow;
      }
    }

    final google = GoogleSignIn(scopes: const ['email']);
    final acct = await google.signIn();
    if (acct == null) {
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Sign-in cancelled.',
      );
    }
    final auth = await acct.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    try {
      final res = current == null
          ? await _auth.signInWithCredential(credential)
          : await current.linkWithCredential(credential);
      await clearGuestFlag();
      return res;
    } on FirebaseAuthException catch (e) {
      if (current != null &&
          (e.code == 'credential-already-in-use' ||
           e.code == 'provider-already-linked' ||
           e.code == 'requires-recent-login' ||
           e.code == 'operation-not-allowed')) {
        final res = await _auth.signInWithCredential(credential);
        await clearGuestFlag();
        try { await current.delete(); } catch (_) {}
        return res;
      }
      rethrow;
    }
  }

  Future<UserCredential> signInWithApple() async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      throw FirebaseAuthException(
        code: 'apple-not-supported',
        message: 'Apple Sign-In is only available on iOS/macOS.',
      );
    }

    final appleID = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final oauthProvider = OAuthProvider('apple.com');
    final credential = oauthProvider.credential(
      idToken: appleID.identityToken,
      accessToken: appleID.authorizationCode,
    );

    final current = _auth.currentUser;
    final res = current == null
        ? await _auth.signInWithCredential(credential)
        : await current.linkWithCredential(credential);

    await clearGuestFlag();
    return res;
  }

  Future<void> signOut() async {
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await _auth.signOut();
  }
}
