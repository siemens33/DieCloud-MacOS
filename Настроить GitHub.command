#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
PLIST="$ROOT/Info.plist"
clear
echo "DieCloude — настройка GitHub"
echo "============================"
echo ""
read "OWNER?Введи GitHub username или организацию: "
read "REPO?Название репозитория [DieCloude]: "
REPO=${REPO:-DieCloude}
[[ -n "$OWNER" ]] || { echo "❌ GitHub username не указан."; read; exit 1; }
/usr/libexec/PlistBuddy -c "Set :DieCloudeGitHubOwner $OWNER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :DieCloudeGitHubRepository $REPO" "$PLIST"
echo ""
echo "✅ Автообновление настроено для github.com/$OWNER/$REPO"
echo "Теперь собери приложение заново через «Создать установщик.command»."
echo ""
read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."
