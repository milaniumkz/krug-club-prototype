# QAZAQMETAL KÁSIPODAǴY · клиент 2.1.0

Нативное Flutter-приложение для Android/iOS и веб-версия с общим API. Исходный светлый дизайн с фиолетовыми акцентами. Внутри нет WebView. Роли участника, партнёра и администратора определяются сервером после входа.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Для локальной проверки APK: запустите API на компьютере на порту 8000, подключите Android по USB с отладкой, выполните `adb reverse tcp:8000 tcp:8000` и `adb install -r build/app/outputs/flutter-apk/app-debug.apk`. Если тестовый сервер работает на порту 8018, используйте `adb reverse tcp:8000 tcp:8018`.

Production-сборки используют `--dart-define=API_BASE_URL=https://ВАШ-ДОМЕН`. Release Android требует своего upload keystore; iOS — macOS/Xcode, Apple Developer и provisioning. Веб использует API того же origin, не требует адреса при сборке. Адрес API и секреты не зашиваются в исходники.

Камера и геолокация запрашиваются при открытии соответствующего раздела. При отказе доступны ручной ввод QR и перемещение карты. QR не открывает произвольные ссылки. Карта использует OpenStreetMap с атрибуцией. Сессия Android/iOS — защищённое хранилище платформы, браузера — HttpOnly cookie. Увольнение/блокировка проверяются сервером.

Партнёр выдаёт QR для опубликованного заведения, сохраняет PNG для печати или вызывает системную панель передачи. Экспорт PNG в браузере проверяется `scripts/browser_partner_content.py`; нативная системная панель требует физического устройства.

Полная установка сервера, управление данными и публикация: `../README.md`, `../docs/PUBLISHING.md`, `../docs/WORKFLOWS.md`.
