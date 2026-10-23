/// Network failures and missing/incomplete payloads are not verdicts.
bool hasValidAiVerdict(Map<String, dynamic> data) {
  if (data['error'] == true || data['reason'] == 'no_content') return false;
  final status = data['status'];
  if (status != null && status != 'ready') return false;
  if (!const ['fighter1', 'fighter2', 'draw'].contains(data['winnerKey'])) return false;
  final a = data['scoreA'];
  final b = data['scoreB'];
  return a is num && b is num && a.isFinite && b.isFinite
      && a >= 0 && a <= 100 && b >= 0 && b <= 100;
}

String aiVerdictUnavailableReason(Map<String, dynamic> data) {
  if (data['status'] == 'insufficient_content' || data['reason'] == 'no_content') return 'no_content';
  if (data['reason'] == 'not_configured' || data['reason'] == 'FINALIZE_NO_API_KEY') return 'not_configured';
  return 'unavailable';
}
