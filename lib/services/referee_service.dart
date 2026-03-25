import 'package:cloud_functions/cloud_functions.dart';

class RefereeService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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
