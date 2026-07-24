# Публикация в AUR (`avee-bin`)

На стабильных тегах CI автоматически публикует пакет
[`avee-bin`](https://aur.archlinux.org/packages/avee-bin) в AUR —
репозиторий пользовательских сборок Arch Linux. Пока секреты AUR не заданы,
job `publish-aur` пропускается и релиз проходит как обычно.

## Разовая настройка владельцем

1. Создать аккаунт на <https://aur.archlinux.org> и добавить в профиле свой
   **публичный** SSH-ключ (Account → My Account → SSH Public Key).
2. Добавить в GitHub Secrets репозитория (`Settings → Secrets and variables →
   Actions`):
   - `AUR_SSH_PRIVATE_KEY` — соответствующий **приватный** SSH-ключ;
   - `AUR_USERNAME` — имя для git-коммитов в AUR;
   - `AUR_EMAIL` — email для git-коммитов в AUR.
3. Первый же стабильный тег (`vX.Y.Z`, без дефиса) после этого сам создаст или
   обновит пакет `avee-bin`.

## Как устроен пакет

`avee-bin` — это **репак** релизного `.deb` (`avee-amd64.deb`), а не сборка
из исходников. CI:

- считает `sha256` для `.deb` и лаунчера `avee.sh`;
- подставляет версию и контрольные суммы в `.github/aur/PKGBUILD.template`;
- отдаёт готовый `PKGBUILD` + `avee.sh` в
  `KSXGitHub/github-actions-deploy-aur`, который пушит их в AUR.

`PKGBUILD` распаковывает `.deb`, кладёт приложение в `/usr/lib/avee`, ставит
лаунчер в `/usr/bin/avee`, а также `.desktop`-файл и иконки (128×128, 256×256).

## Почему только `x86_64`

Мы собираем и публикуем Linux-артефакт только для `amd64` (`avee-amd64.deb` /
`avee-amd64.AppImage`); сборки под linux-arm64 нет, поэтому `arch=('x86_64')`.

## Бейдж для release notes

```
https://aur.archlinux.org/packages/avee-bin
```
