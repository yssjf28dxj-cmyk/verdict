import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_session.dart';
import '../firestore_database.dart';
import '../models/debate_history_item.dart';

/// Independent cursors prevent omitting older battles on either fighter side.
class DebateHistoryService {
  DebateHistoryService()
      : _uid = appAuth.currentUser?.uid,
        _db = appFirestore;
  final String? _uid;
  final FirebaseFirestore _db;
  final _cursors = <DocumentSnapshot<Map<String, dynamic>>?>[null, null];
  final _more = [true, true];
  bool get hasMore => _more.any((value) => value);
  Future<List<DebateHistoryItem>> nextPage({bool reset = false}) async {
    void check() {
      if (_uid == null || appAuth.currentUser?.uid != _uid) {
        throw StateError('Session changed');
      }
    }

    check();
    if (reset) {
      _cursors.fillRange(0, 2, null);
      _more.fillRange(0, 2, true);
    }
    final pages = await Future.wait(List.generate(2, (index) async {
      if (!_more[index]) return null;
      Query<Map<String, dynamic>> query = _db
          .collection('debates')
          .where('fighter${index + 1}', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(20);
      if (_cursors[index] != null) {
        query = query.startAfterDocument(_cursors[index]!);
      }
      return query.get(const GetOptions(source: Source.server));
    })).timeout(const Duration(seconds: 20));
    check();
    final rows = <String, DebateHistoryItem>{};
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      if (page == null) continue;
      for (final doc in page.docs) {
        rows[doc.id] = DebateHistoryItem.fromData(doc.id, doc.data(), _uid!);
      }
      if (page.docs.isNotEmpty) _cursors[index] = page.docs.last;
      _more[index] = page.docs.length == 20;
    }
    return rows.values.toList();
  }
}
