# lowkey для Ubuntu

Экспериментальный порт lowkey на Linux: то же ядро (`LowkeyCore`, тот же
`config.json`), тот же `lowkeyctl`, но окна и вкладки WebKit — через GTK 4 и
WebKitGTK 6.0 вместо AppKit.

> Статус: код написан, но **не собирался в авторской среде** (в ней нет ни
> Swift, ни GTK). Первую сборку на реальной Ubuntu стоит рассматривать как
> перенос: возможны мелкие правки сигнатур в `Sources/CGTK/cgtk.h` и
> `Sources/LowkeyLinux/main.swift`.

## Сборка

```sh
sudo apt install swiftlang libwebkitgtk-6.0-dev pkg-config
git clone https://github.com/bobuk-io/lowkey.git
cd lowkey
swift build
swift test            # LowkeyCoreTests, включая тесты SOCKS-прокси
.build/debug/LowkeyLinux   # запуск приложения
.build/debug/lowkeyctl HA toggle
```

Установка в PATH (опционально):

```sh
sudo cp .build/release/LowkeyLinux /usr/local/bin/lowkey
sudo cp .build/release/lowkeyctl /usr/local/bin/lowkeyctl
```

## Как это устроено

- `Sources/CGTK` — header-only мост к GTK 4 / WebKitGTK 6.0 (systemLibrary,
  ищется через pkg-config `webkitgtk-6.0`).
- `Sources/LowkeyLinux` — приложение: то же правило «сайт = окно = профиль».
  Профили сайтов — в `~/.local/share/lowkey/profiles/<uuid>`, обычные окна
  делят `~/.local/share/lowkey/default`. Конфиг — `~/.config/lowkey/config.json`
  (поддерживается `LOWKEY_CONFIG`).
- IPC между `lowkeyctl` и приложением — тот же формат `ControlRequest`, но
  через Unix-domain сокет (бэкенд BobukCore для Linux). Приложение пишет pid
  в `$TMPDIR/io.bobuk.lowkey.pid`; `lowkeyctl` находит его по pid-файлу,
  а бинарник — через `LOWKEY_BIN` или PATH.

## Паритет с macOS

Работает: сайты с алиасами из одного конфига, изолированные профили,
ordinary-окна, prompt «алиас или адрес», история ввода, команды окна
`open/toggle/hide/close/rewind/reload/back/forward/start`, `status`,
**SOCKS-прокси из конфига** (через публичный API WebKitGTK — на Linux это
работает надёжнее, чем приватный SPI на macOS).

Пока не реализовано: автоматизация страниц (`inspect/wait/fill/select/click/
upload/save-pdf` отвечают `unsupported on linux`), подсказки с перекладкой
раскладок в prompt, настройки GUI (конфиг правится файлом), Tint/Page-темы
окон, диплинки `lowkey://` (в Desktop-окружении нет аналога `open URL` —
используйте `lowkeyctl`).

## Отличия, о которых стоит знать

- Окна входа (sign-in) WebKitGTK ведёт себя иначе, чем встраенные popups
  WKWebView: проверяйте свои сайты.
- Загрузки/выгрузки файлов используют диалоги GTK автоматически.
- Один контекст WebKit на сайт = отдельный web-процесс на сайт; для слабых
  машин не держите десятки окон открытыми.
