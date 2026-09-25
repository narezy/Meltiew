# Meltiew

Платформа в духе Roblox на Godot 4.7: аккаунты, друзья, профиль с редактором аватара Melly
и мультиплеерная «Детская площадка» (до 10 игроков на сервер).

```
client/   Godot-проект (Android, пакет cat.narezany.meltiew)
server/   Node.js бэкенд: REST API + WebSocket игровые серверы, SQLite
deploy/   установщик для VPS (systemd + nginx + Let's Encrypt)
branding/ логотип и исходники иконок
```

## Сервер

Установка или обновление на VPS (Ubuntu + nginx), от root:

```bash
curl -fsSL https://raw.githubusercontent.com/narezy/Meltiew/main/deploy/install.sh | bash
```

Скрипт ставит отдельный Node.js 24 в `/opt/meltiew-node` (системный node не трогает),
код в `/opt/meltiew`, базу в `/var/lib/meltiew`, сервис `meltiew`, сайт `meltiew.narez.xyz`
с сертификатом. Повторный запуск обновляет код и сохраняет базу.
Чтобы положить APK на сайт: `APK_URL=<прямая ссылка> bash install.sh`
или скопировать файл в `/opt/meltiew/public/meltiew.apk`.

Логи: `journalctl -u meltiew -f`. Локальный запуск и тесты: `cd server && npm ci && npm start` / `npm test`.

## Клиент

Открыть `client/` в Godot 4.7.2. Для локального сервера: запустить с аргументом
`-- --server=http://127.0.0.1:7350`.

Сборка APK (ключ подписи хранится вне репозитория):

```bash
GODOT=godot KEYSTORE=/path/meltiew-release.keystore KEYSTORE_PASS=... client/build_android.sh
```

Управление: на телефоне джойстик слева, камера пальцем справа, щипок для зума.
На ПК WASD, пробел, ПКМ для камеры, колесо для зума, Enter для чата.
