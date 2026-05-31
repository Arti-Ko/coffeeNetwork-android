<div align="center">

<img src=".github/assets/icon.png" width="120" alt="coffeeNetwork" />

# coffeeNetwork — Android

**Личный VPN-клиент для Android с нативным движком sing-box.**
Тот же «посадочный талон», что и на десктопе: живая скорость, акцентный цвет,
плитка в шторке рядом с Wi-Fi и Bluetooth.

<sub>Российские домены и IP идут напрямую — весь остальной трафик через VPN. Одним тумблером.</sub>

![Flutter](https://img.shields.io/badge/Flutter-UI-02569B?logo=flutter&logoColor=white)
![sing-box](https://img.shields.io/badge/core-sing--box%20(libbox)-1a1a1a)
![Android](https://img.shields.io/badge/Android-VpnService-3DDC84?logo=android&logoColor=white)
![Protocols](https://img.shields.io/badge/Hysteria2%20·%20VLESS%20·%20Trojan%20·%20VMess%20·%20SS%20·%20TUIC-6d4aff)

</div>

---

## Скриншоты

<!--
  Сними экраны на устройстве/эмуляторе, положи PNG в .github/assets/
  и раскомментируй блок ниже.
-->
<div align="center">
<!--
<img src=".github/assets/screen-home.png"   width="32%" alt="Главный экран" />
<img src=".github/assets/screen-import.png" width="32%" alt="Импорт ссылки" />
<img src=".github/assets/screen-apps.png"   width="32%" alt="Per-app ИГНОР" />
-->
<i>Скриншоты появятся здесь.</i>
</div>

---

## Возможности

- 🔌 **Реальный VPN** — `VpnService` + sing-box `libbox` (gomobile). Не прокси, а
  полноценный туннель на уровне системы.
- 🌐 **Протоколы** — **Hysteria2, VLESS** (+Reality / uTLS / ws)**, Trojan, VMess,
  Shadowsocks, TUIC**.
- 🇷🇺 **Умный обход РФ** — `geosite`/`geoip` RU идут напрямую, остальное через VPN.
  Переключается одним тумблером.
- 🚫 **Per-app исключения** — список «ИГНОР» с иконками и поиском: выбранные
  приложения ходят мимо туннеля.
- ⚡ **Quick Settings tile** — вкл/выкл из шторки рядом с Wi-Fi, без шумного
  постоянного уведомления.
- 📊 **Живая скорость** вверх/вниз через `clash_api`.
- 🎨 **Темы и акценты** — светлая/тёмная + 8 акцентных цветов, всё сохраняется.

## Как это работает

```
┌────────────────────┐   VpnService    ┌──────────────────────────┐
│   coffeeNetwork     │ ──── TUN ─────▶ │  sing-box libbox (gomobile)│
│  (Flutter UI)       │  clash_api      │  outbound: hy2 / vless / … │
└────────────────────┘ ◀── скорость ── └──────────────────────────┘
        │ ссылки серверов + настройки                 │ роутинг: RU → direct
        ▼                                             ▼  остальное → proxy
  локальное хранилище                          geosite-ru / geoip-ru
```

UI повторяет десктопную версию — метафора посадочного талона, крупная
типографика, настраиваемый акцент.

## Стек

| Слой | Технология |
|------|-----------|
| UI | Flutter |
| VPN-движок | sing-box `libbox` (gomobile, форк SagerNet) |
| Системный туннель | Android `VpnService` |
| Управление ядром | `clash_api` (скорость, статус) |

## Сборка

Требуется Flutter, JDK 17, Android SDK + NDK.

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=$HOME/Library/Android/sdk
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.

### Движок sing-box (libbox)

`android/app/libs/libbox.aar` собран из `sing-box` (ветка `main`) через gomobile
(форк SagerNet). Тег `with_naive_outbound` исключён — cronet-go не линкуется на NDK r27.

## Подпись релиза

Локально положи `android/key.properties` и `android/app/coffee.jks`
(оба в `.gitignore`):

```properties
storePassword=...
keyPassword=...
keyAlias=coffee
storeFile=coffee.jks
```

Если `key.properties` нет — сборка использует debug-ключ, чтобы CI/клон собирались.

## CI

`.github/workflows/build.yml` собирает APK на каждый push в `main` и публикует
релиз по тегу `v*`. Для подписи в CI задай секреты репозитория:
`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`.

## Семейство coffeeNetwork

- [**coffeeNetwork**](https://github.com/Arti-Ko/coffeeNetwork) — десктопный
  клиент (macOS / Windows / Linux) на Tauri. Тот же дизайн и логика роутинга.
- [**NetForge**](https://github.com/Arti-Ko/netforge) — фабрика конфигов Hysteria2:
  заводит пользователей на сервере по SSH и выдаёт готовые ссылки.

> **Почему отдельное приложение, а не общий код с десктопом?** На Android sing-box
> работает только через `VpnService` + `libbox`, поэтому клиент здесь нативный
> (Flutter), а не Tauri-сборка.
