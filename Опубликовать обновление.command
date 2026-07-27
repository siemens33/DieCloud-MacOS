#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OWNER="siemens33"
REPO="DieCloud-MacOS"
REMOTE="https://github.com/$OWNER/$REPO.git"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/diecloude-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pause_on_error() {
  local code=$?
  echo ""
  echo "❌ Публикация остановлена. Код ошибки: $code"
  echo "Проверь сообщение выше. Исходная папка не повреждена."
  read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
  exit $code
}
trap pause_on_error ZERR

clear
cat <<'BANNER'
╭──────────────────────────────────────────────╮
│        DieCloude — публикация в GitHub       │
│  Версия, commit, tag, Actions, Release, DMG  │
╰──────────────────────────────────────────────╯
BANNER

echo ""
command -v git >/dev/null || { echo '❌ Git не найден.'; exit 1; }
command -v gh >/dev/null || { echo '❌ GitHub CLI не найден. Установи: brew install gh'; exit 1; }
command -v rsync >/dev/null || { echo '❌ rsync не найден.'; exit 1; }
command -v python3 >/dev/null || { echo '❌ Python 3 не найден.'; exit 1; }
gh auth status >/dev/null 2>&1 || { echo '❌ Выполни один раз: gh auth login'; exit 1; }

[[ -f "$ROOT/Info.plist" && -f "$ROOT/src/main.swift" ]] || {
  echo '❌ Скрипт должен находиться в корне проекта DieCloude.'
  exit 1
}

echo "1/8  Получаю актуальный репозиторий…"
git clone --quiet "$REMOTE" "$WORK/repo"
REMOTE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WORK/repo/Info.plist")

rsync -a --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '.DS_Store' \
  --exclude '*.zip' \
  "$ROOT/" "$WORK/repo/"
cd "$WORK/repo"

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
VERSION=$(python3 - "$CURRENT" "$REMOTE_VERSION" <<'PY'
import sys

def parse(value):
    parts = value.split('.')
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise SystemExit(f'Некорректная версия: {value}')
    return tuple(map(int, parts))

local = parse(sys.argv[1])
remote = parse(sys.argv[2])
if local > remote:
    print('.'.join(map(str, local)))
else:
    major, minor, patch = local
    print(f'{major}.{minor}.{patch + 1}')
PY
)
NEW_BUILD=$((BUILD + 1))

if [[ "$VERSION" == "$CURRENT" ]]; then
  echo "2/8  Публикую подготовленную версию $VERSION (сборка $NEW_BUILD)…"
else
  echo "2/8  Повышаю версию: $CURRENT → $VERSION (сборка $NEW_BUILD)…"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" Info.plist

python3 - "$VERSION" <<'PY'
from pathlib import Path
import re, sys, datetime, subprocess
version = sys.argv[1]

def replace(path, pattern, replacement, flags=0):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Не удалось обновить версию в {path}')
    p.write_text(text, encoding='utf-8')

replace('src/main.swift', r'static let version = "[0-9]+\.[0-9]+\.[0-9]+"', f'static let version = "{version}"')
replace('package-dmg.sh', r'^VERSION="[0-9]+\.[0-9]+\.[0-9]+"$', f'VERSION="{version}"', re.M)

result = subprocess.run(['git', 'diff', '--name-only'], capture_output=True, text=True, check=True)
changed = [line for line in result.stdout.splitlines() if line and line not in {'CHANGELOG.md', 'RELEASE_NOTES.md'}]
if changed:
    bullets = '\n'.join(f'- Обновлён `{name}`.' for name in changed[:25])
else:
    bullets = '- Техническое обновление и синхронизация проекта.'

date = datetime.date.today().isoformat()
entry = f'## {version} — {date}\n\n{bullets}\n\n'
path = Path('CHANGELOG.md')
old = path.read_text(encoding='utf-8') if path.exists() else '# История изменений DieCloude\n\n'
if old.startswith('# История изменений DieCloude'):
    head, rest = old.split('\n', 1)
    path.write_text(head + '\n\n' + entry + rest.lstrip('\n'), encoding='utf-8')
else:
    path.write_text('# История изменений DieCloude\n\n' + entry + old, encoding='utf-8')

Path('RELEASE_NOTES.md').write_text(
    f'# DieCloude {version}\n\n{bullets}\n\n'
    'Скачай `DieCloude.dmg`, открой образ и перенеси приложение в папку «Программы».\n',
    encoding='utf-8'
)
PY

echo "3/8  Проверяю проект…"
plutil -lint Info.plist >/dev/null
zsh -n build.sh package-dmg.sh "Опубликовать обновление.command" "Создать установщик.command"

if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
  echo "❌ Тег v$VERSION уже существует на GitHub."
  exit 1
fi

if [[ -z "$(git status --porcelain)" ]]; then
  echo '❌ Нет изменений для публикации.'
  exit 1
fi

echo "4/8  Создаю commit…"
git config user.name "${GIT_AUTHOR_NAME:-siemens33}"
git config user.email "${GIT_AUTHOR_EMAIL:-siemens33@users.noreply.github.com}"
git add -A
git commit -m "Release DieCloude $VERSION" >/dev/null

echo "5/8  Отправляю main и тег v$VERSION…"
git push origin HEAD:main
git tag -a "v$VERSION" -m "DieCloude $VERSION"
git push origin "v$VERSION"

echo "6/8  Ожидаю запуск GitHub Actions…"
RUN_ID=""
for attempt in {1..30}; do
  RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow release.yml --branch "v$VERSION" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)
  [[ -n "$RUN_ID" ]] && break
  sleep 2
done
[[ -n "$RUN_ID" ]] || { echo '❌ GitHub Actions не запустился в течение минуты.'; exit 1; }

echo "7/8  GitHub собирает приложение и DMG…"
gh run watch "$RUN_ID" --repo "$OWNER/$REPO" --exit-status

echo "8/8  Проверяю опубликованный Release…"
gh release view "v$VERSION" --repo "$OWNER/$REPO" >/dev/null

rsync -a \
  Info.plist src/main.swift package-dmg.sh README.md CHANGELOG.md RELEASE_NOTES.md \
  "$ROOT/"

RELEASE_URL="https://github.com/$OWNER/$REPO/releases/tag/v$VERSION"
DOWNLOAD_URL="https://github.com/$OWNER/$REPO/releases/latest/download/DieCloude.dmg"

echo ""
echo "✅ DieCloude $VERSION полностью опубликован."
echo "Release: $RELEASE_URL"
echo "DMG:     $DOWNLOAD_URL"
open "$RELEASE_URL"
read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
