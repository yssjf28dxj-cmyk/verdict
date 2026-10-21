const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveDebateMediaPath, readableDebateMediaPath } = require('../lib/domain/debate/media.js');
const base = { debateId: 'debate', uid: 'user', bucket: 'verdict.appspot.com' };
const path = 'debates/debate/media/123_user.png';

test('media download: accepts protected and legacy paths in the requested debate', () => {
  assert.equal(readableDebateMediaPath('debate', 'debates/debate/secured/message.png'),
    'debates/debate/secured/message.png');
  assert.equal(readableDebateMediaPath('debate', path), path);
});

for (const invalid of ['debates/other/secured/file.png', 'debates/debate/secured/../file',
  'users/user/avatar.png', 'debates/debate/secured/folder/file']) {
  test(`media download: rejects path ${invalid}`, () => {
    assert.throws(() => readableDebateMediaPath('debate', invalid));
  });
}

test('media: accepts a path in this debate owned by the sender', () => {
  assert.equal(resolveDebateMediaPath({ ...base, mediaPath: path }), path);
});

test('media: legacy URL resolves to a path without storing its token', () => {
  assert.equal(resolveDebateMediaPath({ ...base,
    mediaUrl: `https://firebasestorage.googleapis.com/v0/b/${base.bucket}/o/${encodeURIComponent(path)}?alt=media&token=old`,
  }), path);
});

for (const mediaPath of ['', 'debates/other/media/123_user.png',
  'debates/debate/media/123_other.png', 'debates/debate/media/123_user.png/extra',
  'debates/debate/media/123_user..png', 'debates/debate/media/123_user.%2f']) {
  test(`media: rejects invalid or foreign path ${mediaPath}`, () => {
    assert.throws(() => resolveDebateMediaPath({ ...base, mediaPath }),
      (error) => error.details?.reason === 'MESSAGE_INVALID_MEDIA_PATH');
  });
}

for (const mediaUrl of ['https://example.com/file',
  'https://firebasestorage.googleapis.com.evil.test/v0/b/verdict.appspot.com/o/file',
  'https://firebasestorage.googleapis.com/v0/b/other.appspot.com/o/file',
  'https://firebasestorage.googleapis.com/v0/b/verdict.appspot.com/o/%ZZ']) {
  test(`media: rejects an untrusted legacy URL ${mediaUrl}`, () => {
    assert.throws(() => resolveDebateMediaPath({ ...base, mediaUrl }));
  });
}
