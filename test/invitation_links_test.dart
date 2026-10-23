import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/utils/invitation_links.dart';

void main() {
  test('copyable link targets only the test host and an invitation locator',
      () {
    final link = testInvitationLink('debate_A-123');
    expect(link.toString(),
        'https://verdict-test-1471f.web.app/invite/debate_A-123');
    expect(link.query, isEmpty);
    expect(link.fragment, isEmpty);
  });
  test('authentication carries a canonical invitation through its query', () {
    final auth = Uri.parse(invitationAuthRoute('debate_A-123'));
    expect(auth.path, '/auth');
    expect(invitationReturnPath(auth.queryParameters['returnTo']),
        '/invite/debate_A-123');
  });
  test('auth return cannot become an external redirect or arbitrary app route',
      () {
    for (final unsafe in [
      null,
      'https://evil.test/invite/abc',
      '//evil.test',
      '/profile',
      '/invite/a/b',
      '/invite/../profile',
      '/invite/a?admin=true',
      '/invite/%2fprofile',
      '/invite/a#section',
      '/invite/',
      '/invite/${'a' * 129}'
    ]) {
      expect(invitationReturnPath(unsafe), isNull, reason: unsafe);
    }
  });
  test('invalid IDs cannot enter a shared path', () {
    for (final id in [
      '',
      '../users',
      'a/b',
      '<script>',
      'id?token=secret',
      ' id',
      'a' * 129
    ]) {
      expect(() => testInvitationLink(id), throwsArgumentError);
    }
  });
}
