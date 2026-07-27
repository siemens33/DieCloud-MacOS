#!/bin/zsh
set -euo pipefail

REPO_URL="https://github.com/siemens33/DieCloud-MacOS.git"
REPO_WEB="https://github.com/siemens33/DieCloud-MacOS"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

pause_on_error() {
  local code=$?
  echo ""
  echo "❌ Публикация остановлена (код $code)."
  echo "Окно не закроется автоматически — текст ошибки можно скопировать."
  read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
  exit "$code"
}
trap pause_on_error ERR

clear
printf 'DieCloude — автоматическая публикация обновления\n\n'

command -v git >/dev/null || { echo '❌ Git не найден. Установи Xcode Command Line Tools: xcode-select --install'; exit 1; }
command -v gh >/dev/null || { echo '❌ GitHub CLI не найден. Установи: brew install gh'; exit 1; }
gh auth status >/dev/null 2>&1 || { echo '❌ GitHub CLI не авторизован. Один раз выполни: gh auth login'; exit 1; }

# Архив может быть распакован без скрытой папки .git. В этом случае
# автоматически восстанавливаем связь с GitHub, не удаляя локальные файлы.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo 'ℹ️ Git-репозиторий не найден. Восстанавливаю автоматически…'
  git init -q
  git symbolic-ref HEAD refs/heads/main
  git remote add origin "$REPO_URL"
  git fetch -q origin main --tags
  git reset --mixed origin/main >/dev/null
else
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$REPO_URL"
  else
    git remote set-url origin "$REPO_URL"
  fi
  git fetch -q origin main --tags
fi

# Не публикуем поверх чужих удалённых изменений.
LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || true)
REMOTE_HEAD=$(git rev-parse origin/main)
if [[ -n "$LOCAL_HEAD" && "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  if git merge-base --is-ancestor "$LOCAL_HEAD" "$REMOTE_HEAD" 2>/dev/null; then
    echo 'ℹ️ В GitHub появились новые изменения. Подтягиваю их…'
    git rebase --autostash origin/main
  elif ! git merge-base --is-ancestor "$REMOTE_HEAD" "$LOCAL_HEAD" 2>/dev/null; then
    echo '❌ Локальная и удалённая история разошлись. Автоматическая публикация отменена, чтобы не потерять код.'
    exit 1
  fi
fi

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
VERSION="$CURRENT"

# Если текущая версия уже опубликована, автоматически повышаем patch: X.Y.Z → X.Y.(Z+1).
if git show-ref --verify --quiet "refs/tags/v$VERSION" || gh release view "v$VERSION" --repo siemens33/DieCloud-MacOS >/dev/null 2>&1; then
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
  VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi
NEW_BUILD=$((BUILD + 1))

echo "Текущая версия проекта: $CURRENT (сборка $BUILD)"
echo "Будет опубликована:      $VERSION (сборка $NEW_BUILD)"
printf 'Описание изменений (Enter — «Оптимизация и исправления»): '
read NOTES
[[ -n "$NOTES" ]] || NOTES='Оптимизация и исправления'

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" Info.plist

python3 - "$VERSION" "$NOTES" <<'PY'
from datetime import date
from pathlib import Path
import re
import sys

version, notes = sys.argv[1], sys.argv[2]

replacements = [
    (Path('src/main.swift'), r'static let version = "[0-9]+\.[0-9]+\.[0-9]+"', f'static let version = "{version}"'),
    (Path('package-dmg.sh'), r'^VERSION="[0-9]+\.[0-9]+\.[0-9]+"$', f'VERSION="{version}"'),
]
for path, pattern, replacement in replacements:
    text = path.read_text(encoding='utf-8')
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
    if count != 1:
        raise SystemExit(f'Не удалось обновить версию в {path}')
    path.write_text(text, encoding='utf-8')

changelog = Path('CHANGELOG.md')
old = changelog.read_text(encoding='utf-8') if changelog.exists() else '# История изменений\n'
entry = f'\n## {version} — {date.today().isoformat()}\n\n- {notes.strip()}\n'
if f'## {version} ' not in old:
    if old.startswith('#'):
        first_line, _, rest = old.partition('\n')
        old = first_line + '\n' + entry + rest.lstrip('\n')
    else:
        old = '# История изменений\n' + entry + old
    changelog.write_text(old, encoding='utf-8')

readme = Path('README.md')
if readme.exists():
    text = readme.read_text(encoding='utf-8')
    text = re.sub(
        r'\*\*Текущая версия: [0-9]+\.[0-9]+\.[0-9]+ \(сборка [0-9]+\)\*\*',
        f'**Текущая версия: {version} (сборка {int(Path("Info.plist").read_text(encoding="utf-8").split("<key>CFBundleVersion</key>",1)[1].split("<string>",1)[1].split("</string>",1)[0])})**',
        text,
        count=1,
    )
    whats_new = f'## Что нового в версии {version}\n\n- {notes.strip()}\n\n'
    text, count = re.subn(
        r'## Что нового в версии [0-9]+\.[0-9]+\.[0-9]+\n.*?(?=\n## )',
        whats_new.rstrip(),
        text,
        count=1,
        flags=re.S,
    )
    if count == 0:
        marker = '## О приложении\n'
        text = text.replace(marker, whats_new + marker, 1)
    readme.write_text(text, encoding='utf-8')

Path('RELEASE_NOTES.md').write_text(
    f'# DieCloude {version}\n\n## Что изменилось\n\n- {notes.strip()}\n\n'
    '## Скачать\n\nИспользуй файл `DieCloude.dmg` из раздела Assets.\n',
    encoding='utf-8',
)
PY

plutil -lint Info.plist >/dev/null
zsh -n build.sh package-dmg.sh "Опубликовать обновление.command"

# Не создаём пустой релиз.
if [[ -z "$(git status --porcelain)" ]]; then
  echo '❌ Изменений для публикации нет.'
  exit 1
fi

git add -A
git commit -m "Release DieCloude $VERSION: $NOTES"
git push origin HEAD:main
git tag -a "v$VERSION" -m "$NOTES"
git push origin "v$VERSION"

echo ''
echo '⏳ GitHub Actions собирает DMG. Ожидаю завершения…'
RUN_ID=$(gh run list --repo siemens33/DieCloud-MacOS --workflow release.yml --branch "v$VERSION" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)

# Иногда запуск появляется не мгновенно.
for _ in {1..12}; do
  [[ -n "$RUN_ID" ]] && break
  sleep 5
  RUN_ID=$(gh run list --repo siemens33/DieCloud-MacOS --workflow release.yml --limit 10 --json databaseId,headBranch --jq ".[] | select(.headBranch == \"v$VERSION\") | .databaseId" | head -n1)
done

if [[ -n "$RUN_ID" ]]; then
  gh run watch "$RUN_ID" --repo siemens33/DieCloud-MacOS --exit-status
else
  echo '⚠️ Запуск Actions пока не найден. Код и тег уже отправлены.'
fi

if gh release view "v$VERSION" --repo siemens33/DieCloud-MacOS >/dev/null 2>&1; then
  echo ''
  echo "✅ DieCloude $VERSION опубликован."
  echo "$REPO_WEB/releases/tag/v$VERSION"
  open "$REPO_WEB/releases/tag/v$VERSION"
else
  echo ''
  echo '⚠️ Код отправлен, но Release ещё не появился. Открываю GitHub Actions.'
  open "$REPO_WEB/actions"
fi

trap - ERR
read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
