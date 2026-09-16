#!/bin/zsh
set -euo pipefail

# Папка скриптов -> корень репозитория (работает и из scripts/, и из корня).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../package-dmg.sh" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi
cd "$REPO_ROOT"

clear
echo "DieCloude — создание установщика macOS"
echo "========================================"
echo ""

[[ -f "./package-dmg.sh" ]] || { echo "❌ Не найден package-dmg.sh в $REPO_ROOT"; read -k 1 "?Нажми Enter, чтобы закрыть окно."; exit 1; }
command -v xcrun >/dev/null || { echo "❌ Нужны Xcode Command Line Tools: xcode-select --install"; read -k 1 "?Нажми Enter, чтобы закрыть окно."; exit 1; }
chmod +x ./build.sh ./package-dmg.sh

STATUS=0
if ./package-dmg.sh; then
  STATUS=0
else
  STATUS=$?
fi

echo ""
if [[ $STATUS -eq 0 ]]; then
  echo "Готово."
else
  echo "Произошла ошибка (код $STATUS)."
fi
read -k 1 "?Нажми Enter, чтобы закрыть окно." || true
exit $STATUS
