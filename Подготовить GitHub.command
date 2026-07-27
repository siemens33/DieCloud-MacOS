#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
clear
echo "DieCloude — подготовка GitHub"
echo "=============================="
echo ""
if ! command -v git >/dev/null; then echo "❌ Git не найден. Установи Xcode Command Line Tools."; read; exit 1; fi
if [[ ! -d .git ]]; then git init; git branch -M main; fi
git add .
if git diff --cached --quiet; then echo "Изменений для коммита нет."; else git commit -m "DieCloude 3.2.0"; fi
echo ""
echo "Локальный репозиторий готов. Создай пустой репозиторий на GitHub, затем выполни:"
echo "git remote add origin https://github.com/ТВОЙ_ЛОГИН/DieCloude.git"
echo "git push -u origin main"
echo "git tag v3.2.0 && git push origin v3.2.0"
echo ""
read -k 1 "?Нажми любую клавишу, чтобы закрыть окно."
