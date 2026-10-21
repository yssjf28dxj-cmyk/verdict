import 'package:flutter_test/flutter_test.dart';
import 'package:verdict/utils/debate_media_path.dart';

void main() {
  String resolve(String reference) => debateMediaPath(
    debateId: 'debate', bucket: 'verdict.appspot.com', reference: reference,
  );
  const path = 'debates/debate/media/123_user.png';

  test('new object paths resolve directly', () {
    expect(resolve(path), path);
    expect(resolve('debates/debate/secured/message.png'),
        'debates/debate/secured/message.png');
  });

  test('legacy URL is resolved to a path without its bearer token', () {
    expect(resolve('https://firebasestorage.googleapis.com/v0/b/verdict.appspot.com/o/'
        '${Uri.encodeComponent(path)}?alt=media&token=old'), path);
  });

  for (final reference in [
    'debates/other/media/file.png', 'debates/debate/media/../file.png',
    'debates/debate/media/folder/file.png', 'debates/debate/media/%2f.png',
    'https://example.com/file.png',
    'https://firebasestorage.googleapis.com/v0/b/other/o/file',
    'https://firebasestorage.googleapis.com.evil.test/v0/b/verdict.appspot.com/o/file',
  ]) {
    test('rejects foreign or malformed reference: $reference', () {
      expect(() => resolve(reference), throwsFormatException);
    });
  }
}
