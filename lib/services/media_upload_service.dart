import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:verdict/firebase_session.dart';

/// Uploads bounded media through the server, which checks the selected Firestore
/// database and participant permissions before writing a private storage object.
class MediaUploadService {
  MediaUploadService._();
  static final MediaUploadService instance = MediaUploadService._();
  static const maxUploadBytes = 6 * 1024 * 1024;

  /// Returns an object path, never a bearer-token URL, or null after a failure.
  Future<String?> uploadMedia({
    required String debateId,
    required String uid,
    required String filePath,
    required String contentType,
  }) async {
    // Capture the selected identity before file I/O. A singleton must not retain
    // another test profile's Firebase client between uploads.
    final functions = appFunctions;
    final auth = appAuth;
    if (uid.isEmpty || auth.currentUser?.uid != uid) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size <= 0 || size > maxUploadBytes) {
        debugPrint('[MediaUpload] File exceeds the allowed upload size');
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > maxUploadBytes ||
          auth.currentUser?.uid != uid) {
        return null;
      }
      final response = await functions
          .httpsCallable(
        'uploadDebateMedia',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      )
          .call({
        'debateId': debateId,
        'base64': base64Encode(bytes),
        'contentType': contentType,
      });
      if (auth.currentUser?.uid != uid) return null;
      final data = response.data;
      final path = data is Map ? data['mediaPath'] : null;
      if (path is! String || !path.startsWith('debates/$debateId/uploads/')) {
        debugPrint('[MediaUpload] Server returned an invalid object path');
        return null;
      }
      return path;
    } catch (error) {
      debugPrint('[MediaUpload] Upload failed: $error');
      return null;
    }
  }

  Future<void> sendMedia(
      {required String debateId,
      required String uid,
      required String filePath,
      required String messageType,
      required String requestId,
      required int expectedRound,
      int duration = 0}) async {
    final functions = appFunctions;
    final auth = appAuth;
    if (auth.currentUser?.uid != uid) throw StateError('Account changed');
    final file = File(filePath);
    if (!await file.exists() || await file.length() > maxUploadBytes) {
      throw StateError('Invalid media size');
    }
    final bytes = await file.readAsBytes();
    if (auth.currentUser?.uid != uid) throw StateError('Account changed');
    await functions
        .httpsCallable('sendLiveMedia',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 45)))
        .call({
      'debateId': debateId,
      'base64': base64Encode(bytes),
      'contentType': messageType == 'voice'
          ? 'audio/m4a'
          : (filePath.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg'),
      'clientRequestId': requestId,
      'expectedRoundIndex': expectedRound,
      'mediaDuration': duration,
    });
  }
}
