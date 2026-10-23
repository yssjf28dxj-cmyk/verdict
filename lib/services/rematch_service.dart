import 'package:cloud_functions/cloud_functions.dart';
import '../firebase_session.dart';

class RematchService {
  Future<String> request(String sourceId, String requestId) async {
    final auth = appAuth;
    final functions = appFunctions;
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Authentication required');
    final response = await functions
        .httpsCallable('requestRematch',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
        .call({
      'sourceDebateId': sourceId,
      'clientRequestId': requestId,
    });
    if (auth.currentUser?.uid != uid) throw StateError('Session changed');
    final data = response.data;
    final id = data is Map ? data['debateId'] : null;
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw StateError('Invalid rematch response');
    }
    return id;
  }
}
