/// Resolve new paths and old Firebase links without ever fetching a bearer URL.
String debateMediaPath({
  required String debateId,
  required String bucket,
  required String reference,
}) {
  var path = reference;
  if (reference.startsWith('https://')) {
    final uri = Uri.parse(reference);
    final segments = uri.pathSegments;
    if (uri.host != 'firebasestorage.googleapis.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        segments.length != 5 ||
        segments[0] != 'v0' ||
        segments[1] != 'b' ||
        segments[2] != bucket ||
        segments[3] != 'o') {
      throw const FormatException('Unsupported media reference');
    }
    path = segments[4];
  }
  final securePrefix = 'debates/$debateId/secured/';
  final prefix = path.startsWith(securePrefix)
      ? securePrefix
      : 'debates/$debateId/media/';
  if (!path.startsWith(prefix) ||
      path.substring(prefix.length).isEmpty ||
      path.substring(prefix.length).contains('/') ||
      path.contains('..') ||
      path.contains('\\') ||
      path.contains('%')) {
    throw const FormatException('Media must belong to this debate');
  }
  return path;
}
