// applyDebateResultToProfiles currently writes top-level statistics. Prefer those
// authoritative values (including zero) over a stale legacy nested snapshot.
// Reject non-finite values before rendering or calculating ranks.
num profileStatistic(Map<String, dynamic> data, String key) {
  final serverValue = data[key];
  if (serverValue is num && serverValue.isFinite) return serverValue;
  if (data.containsKey(key)) return 0;
  final stats = data['stats'];
  final legacyValue = stats is Map ? stats[key] : null;
  return legacyValue is num && legacyValue.isFinite ? legacyValue : 0;
}

String profileDebateStyle(Map<String, dynamic> data) {
  final stats = data['stats'];
  final legacy = stats is Map ? stats['debateStyle'] : null;
  for (final value in [data['debateStyle'], legacy]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return 'Balanced';
}
