import { copyFile } from 'node:fs/promises';

// The CLI disallows rules outside its project directory. Refresh an exact local
// copy before each run; the test runner also loads the original file directly.
await copyFile(
  new URL('../../firestore.rules', import.meta.url),
  new URL('firestore.generated.rules', import.meta.url),
);
await copyFile(
  new URL('../../storage.rules', import.meta.url),
  new URL('storage.generated.rules', import.meta.url),
);
