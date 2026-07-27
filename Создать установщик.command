#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
clear
echo "DieCloude — создание установщика macOS"
echo "========================================"
echo ""
./package-dmg.sh
STATUS=$?
echo ""
if [[ $STATUS -eq 0 ]]; then
  echo "Готово. Нажми Enter, чтобы закрыть окно."
else
  echo "Произошла ошибка. Нажми Enter, чтобы закрыть окно."
fi
read
exit $STATUS
