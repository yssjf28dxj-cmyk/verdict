import { HttpsError } from 'firebase-functions/v2/https';

export function readableDebateMediaPath(debateId: string, path: string): string {
  const prefix = path.startsWith(`debates/${debateId}/secured/`)
    ? `debates/${debateId}/secured/` : `debates/${debateId}/media/`;
  const file = path.startsWith(prefix) ? path.slice(prefix.length) : '';
  if (!debateId || debateId.includes('/') || !file || file.includes('/')
      || path.includes('..') || path.includes('\\') || path.includes('%')) {
    throw new HttpsError('invalid-argument', 'Некорректный путь медиа.', {
      reason: 'MESSAGE_INVALID_MEDIA_PATH',
    });
  }
  return path;
}

export function resolveDebateMediaPath(params: {
  debateId: string; uid: string; bucket: string;
  mediaPath?: string; mediaUrl?: string;
}): string {
  let path = params.mediaPath || '';
  if (!path && params.mediaUrl) {
    try {
      const url = new URL(params.mediaUrl);
      const prefix = `/v0/b/${params.bucket}/o/`;
      if (url.origin !== 'https://firebasestorage.googleapis.com'
          || url.username || url.password || !url.pathname.startsWith(prefix)) {
        throw new Error('Invalid origin or bucket');
      }
      path = decodeURIComponent(url.pathname.slice(prefix.length));
    } catch (_) {
      throw new HttpsError('invalid-argument', 'Некорректная ссылка медиа.', {
        reason: 'MESSAGE_INVALID_MEDIA_URL',
      });
    }
  }
  const prefix = path.startsWith(`debates/${params.debateId}/uploads/`)
    ? `debates/${params.debateId}/uploads/` : `debates/${params.debateId}/media/`;
  const file = path.startsWith(prefix) ? path.slice(prefix.length) : '';
  // Upload filenames are <timestamp>_<authenticated uid>.<extension>.
  const timestampEnd = file.indexOf('_');
  if (!params.debateId || params.debateId.includes('/') || !file
      || path.includes('..') || path.includes('\\') || path.includes('%')
      || file.includes('/') || timestampEnd < 1
      || !/^\d+$/.test(file.slice(0, timestampEnd))
      || !file.slice(timestampEnd + 1).startsWith(`${params.uid}.`)
      || !/^[A-Za-z0-9]+$/.test(file.slice(timestampEnd + 1 + params.uid.length + 1))) {
    throw new HttpsError('invalid-argument', 'Файл должен принадлежать отправителю и этому дебату.', {
      reason: 'MESSAGE_INVALID_MEDIA_PATH',
    });
  }
  return path;
}
