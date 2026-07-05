# Публикация в AUR (`dropweb-bin`)

На стабильных тегах CI автоматически публикует пакет
[`dropweb-bin`](https://aur.archlinux.org/packages/dropweb-bin) в AUR —
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
   обновит пакет `dropweb-bin`.

## Как устроен пакет

`dropweb-bin` — это **репак** релизного `.deb` (`dropweb-amd64.deb`), а не сборка
из исходников. CI:

- считает `sha256` для `.deb` и лаунчера `dropweb.sh`;
- подставляет версию и контрольные суммы в `.github/aur/PKGBUILD.template`;
- отдаёт готовый `PKGBUILD` + `dropweb.sh` в
  `KSXGitHub/github-actions-deploy-aur`, который пушит их в AUR.

`PKGBUILD` распаковывает `.deb`, кладёт приложение в `/usr/lib/dropweb`, ставит
лаунчер в `/usr/bin/dropweb`, а также `.desktop`-файл и иконки (128×128, 256×256).

## Почему только `x86_64`

Мы собираем и публикуем Linux-артефакт только для `amd64` (`dropweb-amd64.deb` /
`dropweb-amd64.AppImage`); сборки под linux-arm64 нет, поэтому `arch=('x86_64')`.

## Бейдж для release notes

```
https://aur.archlinux.org/packages/dropweb-bin
```
