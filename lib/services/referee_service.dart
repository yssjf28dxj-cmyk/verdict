import 'package:verdict/firebase_session.dart';
import 'package:cloud_functions/cloud_functions.dart';

class RefereeService {
  final FirebaseFunctions _functions = appFunctions;

  Future<void> advanceRoundOrFinish(String debateId) async {
    await _callAdvanceRoundOrFinish(debateId);
  }

  Future<void> finishDebate(String debateId) async {
    await _callAdvanceRoundOrFinish(debateId);
  }

  Future<void> _callAdvanceRoundOrFinish(String debateId) async {
    final callable = _functions.httpsCallable('advanceRoundOrFinish');
    await callable.call({'debateId': debateId});
  }
}
