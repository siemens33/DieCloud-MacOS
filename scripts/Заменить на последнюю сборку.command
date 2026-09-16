#!/bin/zsh
set -euo pipefail

# Замена установленной программы на последнюю локальную сборку.
# Версию не трогает — только копирует build/DieCloude.app в /Applications.
# Папка скриптов -> корень репозитория (работает и из scripts/, и из корня).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../package-dmg.sh" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi
cd "$REPO_ROOT"

APP_NAME="DieCloude.app"
BUILT_APP="$REPO_ROOT/build/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

clear
echo "DieCloude — замена на последнюю сборку (без смены версии)"
echo "=========================================================="
echo ""

[[ -d "$BUILT_APP" ]] || {
  echo "❌ Нет собранной программы: $BUILT_APP"
  echo "Сначала запусти «scripts/Создать установщик.command»."
  read -k 1 "?Нажми Enter, чтобы закрыть окно." || true
  exit 1
}

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || echo "?")
BUILT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || echo "?")
echo "Сборка из проекта: $BUILT_VERSION ($BUILT_BUILD) — версия не меняется."
if [[ -d "$TARGET_APP" ]]; then
  INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo "?")
  echo "Установлено сейчас:  $INSTALLED_VERSION"
else
  echo "В «Программах» приложения пока нет — будет чистая установка."
fi
echo ""
echo "Приложение будет закрыто и заменено."
read -k 1 "ANSWER?Продолжить? (y/n) " || true
echo ""
[[ "$ANSWER" == [yYдД] ]] || { echo "Отменено."; exit 0; }

echo "Закрываю DieCloude…"
osascript -e 'tell application "DieCloude" to quit' 2>/dev/null || true
sleep 1
pkill -x DieCloude 2>/dev/null || true
sleep 1

echo "Запрашиваются права администратора…"
sudo -v

echo "Копирую новую сборку в «Программы»…"
sudo rm -rf "$TARGET_APP"
sudo cp -R "$BUILT_APP" "$TARGET_APP"
sudo /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
sudo /bin/chmod 755 "$TARGET_APP/Contents/MacOS/DieCloude"
for binary in "$TARGET_APP/Contents/Resources/xray-arm64" "$TARGET_APP/Contents/Resources/xray-x86_64"; do
  [[ -f "$binary" ]] && sudo /bin/chmod 755 "$binary"
done
sudo /usr/bin/codesign --force --deep --sign - "$TARGET_APP"

echo "Проверяю…"
if ! /usr/bin/codesign --verify --deep --verbose=1 "$TARGET_APP" 2>&1 | tail -1; then
  echo "⚠️ Проверка подписи показала предупреждения, но приложение обычно запускается."
fi

echo ""
echo "✅ Заменено на последнюю сборку. Запускаю…"
/usr/bin/open "$TARGET_APP"
sleep 2
exit 0
