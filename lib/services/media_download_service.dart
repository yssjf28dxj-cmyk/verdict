import 'package:verdict/firebase_session.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/debate_media_path.dart';

class MediaDownloadService {
  MediaDownloadService._();
  static final instance = MediaDownloadService._();

  Future<Uint8List> read(String debateId, String reference) async {
    final storage = appStorage;
    final path = debateMediaPath(
      debateId: debateId,
      bucket: storage.ref().bucket,
      reference: reference,
    );
    // The callable checks auth and current debate access on every download.
    // Protected objects cannot be read directly to mint a permanent token URL.
    final result = await appFunctions.httpsCallable(
      'getDebateMedia',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    ).call({'debateId': debateId, 'mediaPath': path});
    final data = result.data;
    if (data is! Map || data['base64'] is! String) {
      throw StateError('Media download returned no data');
    }
    final encoded = data['base64'] as String;
    if (encoded.length > 14 * 1024 * 1024) {
      throw StateError('Media download is too large');
    }
    return base64Decode(encoded);
  }
}
