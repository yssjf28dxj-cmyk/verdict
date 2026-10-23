export function invitationId(path) {
  return typeof path === 'string' ? /^\/invite\/([A-Za-z0-9_-]{1,128})$/.exec(path)?.[1] ?? null : null;
}

export function appIntent(path) {
  const id = invitationId(path);
  return id ? `intent://app/invite/${id}#Intent;scheme=verdicttest;package=com.example.verdict.test;end` : null;
}

// Static landing page: no Firebase SDK, user query, preview metadata or tokens.
// Opening the native app requires an explicit click, never an automatic redirect.
if (typeof document !== 'undefined') {
  const russian = navigator.language.toLowerCase().startsWith('ru');
  const intent = appIntent(location.pathname);
  const title = document.getElementById('title');
  const hint = document.getElementById('hint');
  const open = document.getElementById('open');
  document.documentElement.lang = russian ? 'ru' : 'en';
  document.getElementById('privacy').textContent = russian
    ? 'Закрытые вызовы доступны только приглашённому аккаунту. Ссылка не открывает чужую переписку.'
    : 'Private challenges are available only to the invited account. This link does not unlock private messages.';
  title.textContent = intent
    ? (russian ? 'Приглашение в дебаты' : 'You are invited to debate')
    : (russian ? 'Приглашение недоступно' : 'Invitation unavailable');
  hint.textContent = intent
    ? (russian ? 'Откройте вызов в VERDICT Test. Если приложение не установлено, установите тестовую версию и снова откройте эту ссылку.'
      : 'Open the challenge in VERDICT Test. If the app is not installed, install the test version and open this link again.')
    : (russian ? 'Проверьте ссылку у отправителя.' : 'Ask the sender for a valid link.');
  if (intent) {
    open.href = intent;
    open.textContent = russian ? 'Открыть в приложении' : 'Open in the app';
    open.hidden = false;
  }
}
