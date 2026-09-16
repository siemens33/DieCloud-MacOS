#!/bin/zsh
set -euo pipefail

# Папка скриптов -> корень репозитория (работает и из scripts/, и из корня).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../Info.plist" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi
PLIST="$REPO_ROOT/Info.plist"
[[ -f "$PLIST" ]] || { echo "❌ Не найден Info.plist: $PLIST"; read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."; exit 1; }

clear
echo "DieCloude — настройка GitHub"
echo "============================"
echo ""

OWNER=""
REPO=""
read -r "OWNER?Введи GitHub username или организацию: "
read -r "REPO?Название репозитория [DieCloud-MacOS]: "
REPO=${REPO:-DieCloud-MacOS}
# Убираем пробелы по краям
OWNER="${OWNER//[[:space:]]/}"
REPO="${REPO//[[:space:]]/}"
[[ -n "$OWNER" ]] || { echo "❌ GitHub username не указан."; read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."; exit 1; }
[[ -n "$REPO" ]] || { echo "❌ Название репозитория не указано."; read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."; exit 1; }

/usr/libexec/PlistBuddy -c "Set :DieCloudeGitHubOwner $OWNER" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :DieCloudeGitHubOwner string $OWNER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :DieCloudeGitHubRepository $REPO" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :DieCloudeGitHubRepository string $REPO" "$PLIST"
plutil -lint "$PLIST" >/dev/null

echo ""
echo "✅ Автообновление настроено для github.com/$OWNER/$REPO"
echo "Теперь собери приложение заново через «scripts/Создать установщик.command»."
echo ""
read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."
