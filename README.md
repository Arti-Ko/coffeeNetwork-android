# coffeeNetwork (Android)

Личный VPN-клиент на **Flutter** с нативным движком **sing-box** (libbox).
UI повторяет десктопную версию: «посадочный талон», живая скорость, акцентный
цвет и тема, плитка в шторке рядом с Wi-Fi/Bluetooth.

## Возможности

- Реальное VPN-подключение через `VpnService` + sing-box `libbox` (gomobile).
- Протоколы: **Hysteria2, VLESS (+Reality/uTLS/ws), Trojan, VMess, Shadowsocks, TUIC**.
- Split-tunnel для России (geosite/geoip RU идут напрямую) — переключаемо.
- Per-app исключения («ИГНОР») с иконками и поиском.
- Quick Settings tile — включение/выключение из шторки, без отдельного уведомления-шума.
- Живая скорость вверх/вниз (clash_api).
- Темы (светлая/тёмная) и 8 акцентных цветов, всё сохраняется.

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

Локально: положите `android/key.properties` и `android/app/coffee.jks`
(оба в `.gitignore`).

```properties
storePassword=...
keyPassword=...
keyAlias=coffee
storeFile=coffee.jks
```

Если `key.properties` нет — сборка использует debug-ключ, чтобы CI/клон собирались.

## CI

`.github/workflows/build.yml` собирает APK на каждый push в `main` и публикует
релиз по тегу `v*`. Для подписи в CI задайте секреты репозитория:
`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`.
