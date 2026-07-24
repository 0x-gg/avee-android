# AVEE VPN — Internal testing release (Google Play)

Пошаговый чеклист для **Internal testing** в Google Play Console.
Package name: `com.avee.vpn`

---

## Пункт 1 — Keystore и Play AAB

### 1.1 Keystore (один раз)

Production keystore уже лежит в `android/app/keystore.jks`.
Пароли — в `android/local.properties` (не коммитить):

```properties
storePassword=...
keyAlias=AVEE
keyPassword=...
```

**Google Play Console → [App integrity](https://play.google.com/console/developers/app/keymanagement)**  
→ **App signing** → включить **Google Play App Signing**.  
Загрузите upload key (тот же `keystore.jks`) или создайте новый и сохраните backup.

### 1.2 Собрать AAB

```powershell
cd C:\Users\avedm\dev\avee-android

# Native core (если ещё не собран)
git submodule update --init core/Clash.Meta
dart setup.dart android

# Play AAB (flavor play + PLAY_BUILD)
$env:PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER = "<ваш GCP project number>"
dart setup.dart android build
```

Готовый файл: `dist/dropweb-android-play.aab`

Cloud Project Number:  
**Play Console → Release → App integrity → Play Integrity API**  
или **Google Cloud Console → Dashboard** (число вида `123456789012`).

### 1.3 Проверка на телефоне

Internal testing **не работает** через sideload APK — только через Play Store.
После загрузки AAB (п. 2) установите приложение как tester.

---

## Пункт 2 — Play Console listing

Откройте: **[Google Play Console](https://play.google.com/console)**

### 2.1 Создать приложение (если ещё нет)

1. **All apps → Create app**
2. Name: `AVEE VPN`
3. Default language: English (US) или Russian
4. App / Game: **App**
5. Free or paid: **Free** (подписка внутри)
6. Declarations: VPN app → **Yes**

### 2.2 Store listing

**Grow → Store presence → Main store listing**

| Поле | Значение |
|------|----------|
| App name | AVEE VPN |
| Short description | Fast private VPN with trial and managed profiles |
| Full description | Текст с aveevpn.com |
| App icon | 512×512 PNG |
| Feature graphic | 1024×500 |
| Phone screenshots | минимум 2 (Home + Connected) |

**Ссылки (обязательно):**

| Поле | URL |
|------|-----|
| Privacy policy | https://aveevpn.com/#privacy |
| Email | support@aveevpn.com (или ваш SUPPORT_EMAIL) |

### 2.3 App content

**Policy → App content:**

#### Data safety
**[Data safety form](https://play.google.com/console/app/app-content/data-privacy-security)**

Собирается:
- Account identifiers (anonymous account number, recovery)
- Device identifiers (installation ID, device public key — **не** Android ID / IMEI)
- Purchase history (Google Play token verification)

Не собирается:
- Browsing history, DNS, traffic contents

Encryption: in transit (HTTPS/TLS).  
Deletion: in-app Account → Delete account + https://aveevpn.com/#account-deletion

#### App access
**[App access](https://play.google.com/console/app/app-content/testing-credentials)**

Instructions for reviewers:
```
1. Install from Internal testing track.
2. Accept VPN disclosure on first connect.
3. Create account (anonymous number shown on Account screen).
4. Start 3-day / 1 GB trial.
5. Open Locations → select Denmark → Connect.
6. Account → Delete account to test deletion.
For paid flow: use license tester + subscription product 30d.
```

#### VPN / sensitive permissions
**[Sensitive app permissions](https://play.google.com/console/app/app-content/sensitive-permissions)**

Declare **VPN service** — core functionality.  
Rationale: encrypted tunnel for user-initiated connection.

#### Content rating
**[Content rating questionnaire](https://play.google.com/console/app/app-content/content-rating)** → обычно Everyone / 3+

#### Target audience
**Policy → Target audience** → 18+ (VPN + payments)

### 2.4 Загрузить Internal testing

**Release → Testing → Internal testing → Create new release**

1. Upload `dropweb-android-play.aab`
2. Release name: `0.8.5 internal 1`
3. Release notes: first internal VPN build
4. **Review release → Start rollout to Internal testing**

**Testers:** Release → Testing → Internal testing → **Testers** tab  
→ Create email list → добавьте Gmail-адреса testers.

Ссылка для testers: **Copy link** на internal testing page.

---

## Пункт 3 — GPL source release

Google Play + GPL-3.0 требуют доступ к исходникам.

```powershell
cd C:\Users\avedm\dev\avee-android
pwsh ./scripts/verify-gpl-release.ps1 -Tag HEAD -OutputDirectory ./release-source
```

1. Создайте GitHub Release на тег `v0.8.5` (или текущий)
2. Прикрепите `.tar.gz` + `.sha256` из `release-source/`
3. В Play Console → Store listing → добавьте в описание:  
   `Source code: https://github.com/0x-gg/avee-android/releases`

---

## Пункт 4 — Billing, OAuth, RTDN

### 4.1 Google Cloud + Play Console API

1. **[Google Cloud Console](https://console.cloud.google.com/)** → создайте/выберите проект (тот же, что для Integrity)
2. Enable APIs:
   - [Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com)
   - [Play Integrity API](https://console.cloud.google.com/apis/library/playintegrity.googleapis.com)
3. **APIs & Services → Credentials → OAuth client** (Desktop or Web)
4. **[Play Console → Users and permissions → API access](https://play.google.com/console/developers/api-access)**  
   → Link Cloud project → Grant access to service account / OAuth client

### 4.2 OAuth refresh token (server)

```bash
# One-time: получить refresh token для backend
# Scopes: https://www.googleapis.com/auth/androidpublisher
```

Заполните на сервере в `/opt/avee-backend/.env.production`:

```env
GOOGLE_BILLING_ENABLED=true
GOOGLE_PLAY_PACKAGE_NAME=com.avee.vpn
GOOGLE_OAUTH_CLIENT_ID=...
GOOGLE_OAUTH_CLIENT_SECRET=...
GOOGLE_OAUTH_REFRESH_TOKEN=...
```

Пересоберите backend:
```bash
cd /opt/avee-backend
docker compose --env-file .env.production -f docker-compose.production.yml up -d --build backend
```

### 4.3 Subscription product в Play Console

**[Monetize → Products → Subscriptions](https://play.google.com/console/app/subscriptions)**

| Поле | Значение |
|------|----------|
| Product ID | `30d` (**must match** backend Plan.code) |
| Name | AVEE VPN Monthly |
| Billing period | 1 month |
| Price | $2.50 (или локализованные) |
| Free trial | None (app has own 1 GB trial) |

Activate subscription.

### 4.4 Plan в Postgres

```bash
docker compose --env-file .env.production -f docker-compose.production.yml exec -T postgres \
  psql -U avee -d avee -f - < scripts/seed-play-plan.sql
```

Проверка: `GET https://api.aveevpn.app/v1/config/billing/methods`

### 4.5 License testers

**[Play Console → Settings → License testing](https://play.google.com/console/developers/license-testing)**

Добавьте Gmail testers — покупки без реального списания.

### 4.6 RTDN (Real-time developer notifications)

**[Monetize → Monetization setup](https://play.google.com/console/app/monetization-setup)**

1. Create Pub/Sub topic in GCP
2. Grant `pubsub.publisher` to `google-play-developer-notifications@system.gserviceaccount.com`
3. Create push subscription → endpoint:  
   `https://api.aveevpn.app/v1/webhooks/google:rtdn`
4. Paste topic name in Play Console

---

## Пункт 5 — Play Integrity

### 5.1 Play Console

**[Release → App integrity](https://play.google.com/console/app/app-integrity)**

1. Link Cloud project (если не linked)
2. Enable **Play Integrity API**
3. Copy **Cloud project number** → используйте в сборке AAB

### 5.2 Backend

После первой загрузки AAB в Internal testing включите:

```env
PLAY_INTEGRITY_REQUIRED=true
PLAY_INTEGRITY_VERIFIER_URL=builtin
PLAY_INTEGRITY_PACKAGE_NAME=com.avee.vpn
```

(`builtin` = decode через Google API на backend, OAuth те же что billing)

Redeploy backend.

### 5.3 Client

AAB собирается с:
```
--dart-define=PLAY_BUILD=true
--dart-define=PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>
```

Integrity token запрашивается при **Create account** / **Recover account**.

**Важно:** Integrity работает только для установок **из Play** (internal/closed/open). Sideload AAB/APK не пройдёт — это ожидаемо.

### 5.4 Порядок включения

1. Upload AAB → internal testing **без** `PLAY_INTEGRITY_REQUIRED` (trial работает)
2. Установить из Play, проверить connect + trial
3. Включить `PLAY_INTEGRITY_REQUIRED=true` + rebuild/redeploy
4. Новый AAB → internal testing → проверить create account

---

## Финальный smoke test (internal tester)

- [ ] Установка только через Play internal link
- [ ] Create account → trial → Locations → Connect → Protected
- [ ] Subscription page shows `30d` product
- [ ] Test purchase (license tester) → access active
- [ ] Restore purchases works
- [ ] Delete account works
- [ ] Privacy/Terms links open in browser

---

## Полезные ссылки

| Что | URL |
|-----|-----|
| Play Console | https://play.google.com/console |
| Internal testing | https://play.google.com/console → Release → Testing → Internal testing |
| Subscriptions | https://play.google.com/console → Monetize → Subscriptions |
| App integrity | https://play.google.com/console → Release → App integrity |
| Data safety | https://play.google.com/console → Policy → App content → Data safety |
| API access | https://play.google.com/console/developers/api-access |
| License testing | https://play.google.com/console/developers/license-testing |
| Production API | https://api.aveevpn.app/v1/health |
| Privacy policy | https://aveevpn.com/#privacy |
| Android repo | https://github.com/0x-gg/avee-android |
| Backend repo | https://github.com/0x-gg/avee-backend |
