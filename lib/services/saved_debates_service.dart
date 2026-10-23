import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_session.dart';
import '../firestore_database.dart';
import '../utils/invitation_links.dart';

class SavedDebate {
  const SavedDebate(this.id, this.topic);
  final String id;
  // No old title is retained when the battle disappears or access is revoked.
  final String? topic;
}

class SavedDebatesService {
  SavedDebatesService()
      : _uid = appAuth.currentUser?.uid,
        _db = appFirestore;
  final String? _uid;
  final FirebaseFirestore _db;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool hasMore = true;
  void _checkSession() {
    if (_uid == null || appAuth.currentUser?.uid != _uid) {
      throw StateError('Session changed');
    }
  }

  CollectionReference<Map<String, dynamic>> get _refs {
    _checkSession();
    return _db.collection('users').doc(_uid!).collection('saved_debates');
  }

  Future<bool> contains(String id) async {
    if (!validInvitationId(id)) throw ArgumentError('Invalid debate');
    final snapshot = await _refs
        .doc(id)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    _checkSession();
    return snapshot.exists;
  }

  Future<void> setSaved(String id, bool saved) async {
    if (!validInvitationId(id)) throw ArgumentError('Invalid debate');
    final ref = _refs.doc(id);
    if (saved) {
      await ref.set({'savedAt': FieldValue.serverTimestamp()}).timeout(
          const Duration(seconds: 20));
    } else {
      await ref.delete().timeout(const Duration(seconds: 20));
    }
    _checkSession();
  }

  Future<List<SavedDebate>> nextPage({bool reset = false}) async {
    _checkSession();
    if (reset) {
      _cursor = null;
      hasMore = true;
    }
    if (!hasMore) return [];
    Query<Map<String, dynamic>> query =
        _refs.orderBy('savedAt', descending: true).limit(20);
    if (_cursor != null) query = query.startAfterDocument(_cursor!);
    final snapshot = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    final rows = await Future.wait(snapshot.docs.map((ref) async {
      try {
        final debate = await _db
            .collection('debates')
            .doc(ref.id)
            .get(const GetOptions(source: Source.server));
        final topic = debate.data()?['topic'];
        return SavedDebate(ref.id, topic is String ? topic : null);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' || error.code == 'not-found') {
          return SavedDebate(ref.id, null);
        }
        rethrow;
      }
    })).timeout(const Duration(seconds: 20));
    _checkSession();
    if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;
    hasMore = snapshot.docs.length == 20;
    return rows;
  }
}
