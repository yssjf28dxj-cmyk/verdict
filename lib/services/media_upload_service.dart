import 'package:verdict/firebase_session.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Handles uploading voice recordings and images to Firebase Storage.
///
/// Upload path: `debates/{debateId}/media/{timestamp}_{uid}.{ext}`
class MediaUploadService {
  MediaUploadService._();
  static final MediaUploadService instance = MediaUploadService._();

  final FirebaseStorage _storage = appStorage;

  /// Upload a file and return its object path, never a download-token URL.
  ///
  /// Returns `null` on failure.
  Future<String?> uploadMedia({
    required String debateId,
    required String uid,
    required String filePath,
    required String contentType,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('[MediaUpload] File does not exist: $filePath');
        return null;
      }

      final ext = filePath.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'debates/$debateId/media/${timestamp}_$uid.$ext';

      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(contentType: contentType);

      final uploadTask = ref.putFile(file, metadata);

      // Monitor progress (optional)
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress =
            snapshot.bytesTransferred / snapshot.totalBytes * 100;
        debugPrint('[MediaUpload] Progress: ${progress.toStringAsFixed(0)}%');
      });

      await uploadTask;
      debugPrint('[MediaUpload] Upload complete: $storagePath');
      return storagePath;
    } catch (e) {
      debugPrint('[MediaUpload] Upload failed: $e');
      return null;
    }
  }

  /// Upload voice recording
  Future<String?> uploadVoice({
    required String debateId,
    required String uid,
    required String filePath,
  }) {
    return uploadMedia(
      debateId: debateId,
      uid: uid,
      filePath: filePath,
      contentType: 'audio/m4a',
    );
  }

  /// Upload image
  Future<String?> uploadImage({
    required String debateId,
    required String uid,
    required String filePath,
  }) {
    final ext = filePath.split('.').last.toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    return uploadMedia(
      debateId: debateId,
      uid: uid,
      filePath: filePath,
      contentType: contentType,
    );
  }
}
