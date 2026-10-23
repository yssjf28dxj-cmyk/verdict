# Тестовый Firebase VERDICT

Актуальное состояние и ограничения на 23 октября:
[проверка фундамента](foundation-audit-2026-10-23.md).
Новый согласованный тестовый выпуск: `scripts/deploy-test-foundation.sh`.
Он включает правила и новые callables; требуется соответствующий новый APK.
Предыдущие записи ниже оставлены как история и не заменяют текущий отчёт.


Состояние на 20 октября 2026. Firebase-проект создан пользователем:
`verdict-test-1471f`. Android-приложение зарегистрировано как
`com.example.verdict.test`. Загруженный `google-services.json` проверен по
этим двум идентификаторам и размещён в `android/app/src/staging/`.
Это клиентская конфигурация Firebase, не ключ сервисного аккаунта и не
разрешение на развёртывание серверных компонентов.

## Варианты сборки

| Вариант | Application ID | Название | Firebase |
| --- | --- | --- | --- |
| `production` | `com.example.verdict` | verdict | `verdict-final` |
| `staging` | `com.example.verdict.test` | VERDICT Test | `verdict-test-1471f` |

Оригинальные `android/app/google-services.json` и `lib/firebase_options.dart`
сохранены без изменений. Новый Android source set перекрывает конфигурацию
только для `staging`. FirebaseOptions в Dart выбираются через стандартный
Flutter `appFlavor`; `staging` настроен только для Android, на другой
платформе останавливается с ошибкой вместо перехода на production.

Вход в `main.dart` остаётся общим. Теперь сборку Android следует запускать
с явно выбранным flavor:

```sh
source /workspace/.onboarding/android-env.sh
cd /workspace/verdict
flutter build apk --debug --no-pub --flavor staging --target-platform android-arm64
# Обычный вариант (не запускать против действующей базы ради теста):
flutter build apk --debug --no-pub --flavor production --target-platform android-arm64
```

Разные application ID позволяют поставить тестовое приложение рядом
с прежним, без его удаления и без общей локальной базы приложения.
Не считать это проверкой фактической установки на планшете.

## Проверки

```sh
flutter analyze --no-pub lib/firebase_environment.dart lib/firebase_options_test.dart lib/main.dart test/firebase_environment_test.dart
flutter test --no-pub --flavor production test/firebase_environment_test.dart
flutter test --no-pub --flavor staging test/firebase_environment_test.dart
```

Анализатор: No issues found. Staging: 2 теста прошли; production: 1 прошёл,
1 помечен пропущенным, поскольку проверяет запрет staging на другой платформе.
`FLUTTER_APP_FLAVOR` нельзя задавать напрямую через `--dart-define`:
для тестов и сборки используется поддерживаемый флаг `--flavor`.

Тестовый APK успешно собран за 88.8 секунды. Проверены подпись APK,
целостность ZIP, label `VERDICT Test`, package `com.example.verdict.test`
и скомпилированный Android-ресурс project_id `verdict-test-1471f`.
Путь: `build/app/outputs/flutter-apk/app-staging-debug.apk`.
Размер: 146 956 464 байта.
SHA-256: `99dd4fe7b17e33b9340539ef81ef37731f906bc98f9f2564aa0ce1c481903be1`.

Обычный APK `app-production-debug.apk` также собран (48.6 секунды).
Его скомпилированные ресурсы проверены: пакет `com.example.verdict`, label
`verdict`, project_id `verdict-final`. Исходные production-конфигурации не менялись.

## Что ещё не выполнено

Не подтверждены запуск на планшете, включение Anonymous Authentication,
создание тестовых Firestore/Storage, публикация проверенных правил/индексов
и Functions в новом проекте. Вход и полный сценарий дебата пока не проверены.
Для новых медиа нужны `sendDebateMessage` и `getDebateMedia` из текущей версии.

В действующий `verdict-final` ничего не публиковалось. Наличие клиентского JSON
не даёт облачной среде прав администратора Firebase. Для облачных Functions
и Storage нового проекта может потребоваться Blaze; подключение биллинга —
отдельное решение владельца после объяснения расходов.


## 21 октября: именованная база тестового проекта

По выводу gcloud у владельца база имеет ID `default` (без скобок),
регион us-central1, FIRESTORE_NATIVE. Это другая база, чем `(default)`.
Правила опубликованы владельцем; создание 17 индексов завершилось сообщением
Deploy complete, их полный список удалённо не проверен. Blaze подключён по
подтверждению владельца; бюджет в TRY является уведомлением, не лимитом.

Приложение использует общий appFirestore: staging направлен в `default`,
production остаётся в `(default)`. Все места получения клиентского Firestore
переведены на этот общий выбор. Сервер выбирает `default` только для точного
project ID verdict-test-1471f; оба Firestore-триггера используют тот же ID.
Тестовый сервер ограничен двумя экземплярами на функцию, minInstances=0;
это не ограничивает общий счёт. firebase.staging.json задаёт Node.js 22,
именованную базу и исключает Storage/Hosting/правила из публикации.

firestore.staging.indexes.json содержит также 18-й индекс status + roundEndsAt
для ежеминутного авто-рефери. Текстовый сценарий не требует Storage;
текущие Storage rules обращаются к `(default)`, поэтому запуск фото/аудио
с именованной базой пока не готов. Нельзя публиковать эти Storage rules
в тестовый проект без отдельного решения. AI-ключ в пакет не включён.

Пакет /workspace/.onboarding/verdict-test-server.tar.gz содержит только исходники Functions,
зависимости с lockfile, серверные тесты, тестовую конфигурацию и индексы.
В нём нет секретов, локальных учётных данных или node_modules.
Публикация из Cloud Shell требует загрузки этого пакета владельцем.
Сервер удалённо ещё не опубликован; работа на устройстве не проверена.


## Передача через отдельную ветку GitHub

Владелец разрешил публикацию подготовленных изменений в отдельную ветку
`codex/verdict-test-setup`, без изменения main. Для Cloud Shell используется
`scripts/deploy-test-server.sh` из этой ветки. Скрипт проверяет Node.js >=22,
наличие именованной базы, устанавливает зависимости по lockfile, собирает
сервер, выполняет тесты и публикует только Functions и индексы в
`verdict-test-1471f`. Правила, Storage, Hosting и рабочий проект не публикует.
До завершения команды удалённое развёртывание сервера не подтверждено.

Последние локальные проверки: 29 серверных тестов; 12 Flutter-тестов staging;
2 production-теста и 1 пропуск; 24 проверки медиа в эмуляторах; тестовый APK
пересобран с именованной базой. Полный flutter analyze: ошибок нет, остались
два прежних информационных предупреждения deprecated value в home_search_bar.
