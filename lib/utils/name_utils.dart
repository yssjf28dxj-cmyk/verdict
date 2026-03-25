const Set<String> _legacyPlaceholderNames = {
  'guest',
  'google user',
  'fighter',
  'fighter 1',
  'fighter 2',
  'opponent',
  'invited',
  'user',
  'гость',
  'боец',
  'боец 1',
  'боец 2',
  'оппонент',
  'вы',
};

String sanitizePublicName(dynamic raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  final normalized = value.toLowerCase();
  if (_legacyPlaceholderNames.contains(normalized)) return '';
  return value;
}

String deriveNeutralName({
  required String displayName,
  required String email,
  required String uid,
}) {
  final sanitizedDisplayName = sanitizePublicName(displayName);
  if (sanitizedDisplayName.isNotEmpty) return sanitizedDisplayName;

  final localPart = email.trim().split('@').first;
  final sanitizedLocalPart = sanitizePublicName(localPart);
  if (sanitizedLocalPart.isNotEmpty) return sanitizedLocalPart;

  return uid.trim();
}

String firstNonEmptyName(Iterable<dynamic> values, {String fallback = ''}) {
  for (final value in values) {
    final normalized = sanitizePublicName(value);
    if (normalized.isNotEmpty) return normalized;
  }
  return fallback;
}
