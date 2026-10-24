import 'package:verdict/firebase_session.dart';
import 'package:verdict/firestore_database.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'account_service.dart' show googleLoginAvailable;
import 'push_coordinator.dart';

class AuthService {
  final FirebaseAuth _auth = appAuth;
  final FirebaseFirestore _firestore = appFirestore;
  String? _lastErrorCode;
  String? _lastErrorMessage;

  static const Set<String> _retryableAuthCodes = {
    'network-request-failed',
    'too-many-requests',
    'internal-error',
  };

  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;

  void _setError({required String code, required String message}) {
    _lastErrorCode = code;
    _lastErrorMessage = message;
    debugPrint('AuthService error [$code]: $message');
  }

  void _clearError() {
    _lastErrorCode = null;
    _lastErrorMessage = null;
  }

  Future<UserCredential> _signInAnonymouslyWithRetry() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      if (!_retryableAuthCodes.contains(e.code)) rethrow;
      await Future.delayed(const Duration(milliseconds: 700));
      return _auth.signInAnonymously();
    }
  }

  Future<UserCredential?> signInAnonymously() async {
    _clearError();
    try {
      final credential = await _signInAnonymouslyWithRetry();

      try {
        final tag = (Random().nextInt(9000) + 1000).toString();
        await _createUserIfNeeded(
          uid: credential.user!.uid,
          name: 'Боец_$tag',
        );
      } catch (e) {
        debugPrint('AuthService profile bootstrap warning: $e');
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      // keychain-error on simulator: retry without keychain persistence.
      if (e.code == 'keychain-error') {
        try {
          await appAuth.setPersistence(Persistence.NONE);
          final credential = await _auth.signInAnonymously();
          return credential;
        } catch (e) {
          debugPrint('AuthService keychain-error recovery failed: $e');
        }
      }
      _setError(
        code: e.code,
        message: e.message ?? 'Anonymous sign-in failed.',
      );
      return null;
    } catch (e) {
      _setError(
        code: 'anonymous_sign_in_unknown',
        message: e.toString(),
      );
      return null;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    _clearError();
    try {
      if (!googleLoginAvailable) {
        throw FirebaseAuthException(code: 'operation-not-allowed');
      }
      if (_auth.currentUser != null) {
        throw FirebaseAuthException(code: 'guest-session-changed');
      }
      final GoogleSignIn googleSignIn = GoogleSignIn();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        _setError(
          code: 'google_sign_in_cancelled',
          message: 'Google sign-in cancelled by user.',
        );
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // A guest created while the provider picker was open must not be replaced.
      if (_auth.currentUser != null) {
        throw FirebaseAuthException(code: 'guest-session-changed');
      }
      final userCredential = await _auth.signInWithCredential(credential);
      final displayName = userCredential.user?.displayName?.trim() ?? '';

      try {
        await _createUserIfNeeded(
          uid: userCredential.user!.uid,
          name: displayName,
        );
      } catch (e) {
        debugPrint('AuthService profile bootstrap warning: $e');
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      _setError(
        code: e.code,
        message: e.message ?? 'Google sign-in failed.',
      );
      return null;
    } catch (e) {
      _setError(
        code: 'google_sign_in_unknown',
        message: e.toString(),
      );
      return null;
    }
  }

  Future<void> _createUserIfNeeded({
    required String uid,
    required String name,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);

    // Keep provider contact details in Firebase Auth. This document is a public
    // profile; the transaction only fills a missing display name.
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(userRef);

      if (!snap.exists) {
        transaction.set(userRef, {
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (name.isNotEmpty &&
          (snap.data()?['name'] ?? '').toString().trim().isEmpty) {
        transaction.update(userRef, {'name': name});
      }
    });
  }

  Future<void> signOut() async {
    await pushCoordinator.beforeSessionChange();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    await _auth.signOut();
  }
}
