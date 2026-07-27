#!/bin/zsh
set -euo pipefail

REPO="siemens33/DieCloud-MacOS"
REPO_URL="https://github.com/${REPO}.git"
REPO_WEB="https://github.com/${REPO}"
VERSION="3.5.0"
TAG="v${VERSION}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

pause_on_error() {
  local code=$?
  echo ""
  echo "❌ Замена релиза остановлена (код $code)."
  read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
  exit "$code"
}
trap pause_on_error ERR

clear
printf 'DieCloude — замена GitHub Release %s\n\n' "$TAG"

echo 'Эта команда заменит существующий релиз 3.5.0 исправленной сборкой 18.'
printf 'Продолжить? [y/N]: '
read ANSWER
[[ "$ANSWER" == [yYдД] ]] || { echo 'Отменено.'; exit 0; }

command -v git >/dev/null || { echo '❌ Git не найден. Выполни: xcode-select --install'; exit 1; }
command -v gh >/dev/null || { echo '❌ GitHub CLI не найден. Выполни: brew install gh'; exit 1; }
gh auth status >/dev/null 2>&1 || { echo '❌ Выполни один раз: gh auth login'; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo 'ℹ️ Восстанавливаю Git-репозиторий…'
  git init -q
  git symbolic-ref HEAD refs/heads/main
  git remote add origin "$REPO_URL"
  git fetch -q origin main --tags
  git reset --mixed origin/main >/dev/null
else
  git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
  git fetch -q origin main --tags
fi

# Убеждаемся, что публикуется именно исправленная сборка.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
PLIST_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
[[ "$PLIST_VERSION" == "$VERSION" ]] || { echo "❌ В Info.plist версия $PLIST_VERSION, ожидалась $VERSION"; exit 1; }
[[ "$PLIST_BUILD" == "18" ]] || { echo "❌ В Info.plist сборка $PLIST_BUILD, ожидалась 18"; exit 1; }
plutil -lint Info.plist >/dev/null

# Синхронизируемся с main, не стирая локальные исправления.
LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || true)
REMOTE_HEAD=$(git rev-parse origin/main)
if [[ -n "$LOCAL_HEAD" && "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  git reset --mixed origin/main >/dev/null
fi

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "Fix DieCloude 3.5.0 dark theme compatibility (build 18)"
  git push origin HEAD:main
else
  echo 'ℹ️ Код уже находится в main.'
fi

# Удаляем старый GitHub Release и старый тег, затем создаём их заново.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo '🗑 Удаляю старый GitHub Release…'
  gh release delete "$TAG" --repo "$REPO" --yes --cleanup-tag
else
  git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true
fi

git tag -d "$TAG" >/dev/null 2>&1 || true
git tag -a "$TAG" -m "DieCloude 3.5.0 — исправленная тёмная тема, сборка 18"
git push origin "$TAG" --force

echo ''
echo '⏳ GitHub Actions собирает исправленный DMG…'
RUN_ID=''
for _ in {1..18}; do
  RUN_ID=$(gh run list --repo "$REPO" --workflow release.yml --limit 20 --json databaseId,headBranch --jq ".[] | select(.headBranch == \"$TAG\") | .databaseId" | head -n1)
  [[ -n "$RUN_ID" ]] && break
  sleep 5
done

if [[ -n "$RUN_ID" ]]; then
  gh run watch "$RUN_ID" --repo "$REPO" --exit-status
else
  echo '⚠️ Запуск Actions пока не появился. Тег уже отправлен.'
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo ''
  echo '✅ Старый релиз 3.5.0 заменён исправленной сборкой 18.'
  open "$REPO_WEB/releases/tag/$TAG"
else
  echo '⚠️ Release ещё создаётся. Открываю Actions.'
  open "$REPO_WEB/actions"
fi

trap - ERR
read -k 1 '?Нажми любую клавишу, чтобы закрыть окно.'
