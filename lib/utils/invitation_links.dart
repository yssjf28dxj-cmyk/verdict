import 'package:flutter/services.dart' show appFlavor;

const testInvitationHost = 'verdict-test-1471f.web.app';
bool get invitationsEnabled =>
    appFlavor == 'staging' &&
    const bool.fromEnvironment('VERDICT_INVITES_ENABLED');

bool validInvitationId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);

String invitationRoute(String id) {
  if (!validInvitationId(id)) throw ArgumentError('Invalid invitation ID');
  return '/invite/$id';
}

/// A locator, never a bearer credential. Existing Firestore/Functions checks
/// still decide whether the selected account can read or accept the challenge.
Uri testInvitationLink(String id) =>
    Uri.https(testInvitationHost, invitationRoute(id));

/// Authentication may return only to a canonical invitation path, never to an
/// arbitrary URL supplied by a link. Drop encoded paths, queries and fragments.
String? invitationReturnPath(String? input) {
  if (input == null || !input.startsWith('/invite/')) return null;
  final id = input.substring('/invite/'.length);
  return validInvitationId(id) ? invitationRoute(id) : null;
}

String invitationAuthRoute(String id) =>
    Uri(path: '/auth', queryParameters: {'returnTo': invitationRoute(id)})
        .toString();
