# VERDICT

Flutter-приложение для дебатов: два участника, очереди с серверными сроками,
зрительское голосование и общий чат. Сервер — Firebase/Cloud Functions.

- [Цели и порядок развития](docs/roadmap.md)
- [Проверка фундамента и статус выпуска](docs/foundation-audit-2026-10-23.md)
- [Тестовые профили](docs/test-profiles.md)
- [План оформления](docs/design-refresh.md)

## Проверка исходников

Flutter 3.41.4, Node.js 22 и Java 21. Зависимости зафиксированы lockfiles.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --flavor staging
flutter test --no-pub --flavor production
npm ci --prefix functions
npm test --prefix functions
npm ci --prefix tests/firestore
```

Все серверные интеграционные проверки выполняются на локальных эмуляторах
с demo-проектом; команды также приведены в `.github/workflows/verify.yml`.
Наличие исходников и собранного APK не означает публикацию изменений в Firebase.

## Изолированный тестовый выпуск

Работа ведётся в `codex/verdict-test-setup` с Firebase `verdict-test-1471f`,
база `default` без скобок. Для этого выпуска нужен согласованный деплой
сервера/правил и соответствующий APK. Порядок и оставшиеся проверки приведены
в отчёте фундамента. Рабочий Firebase, main и магазины не являются целями
тестовых скриптов.
