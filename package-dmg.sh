#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/DieCloude.app"
VERSION="3.5.0"
DMG="$BUILD/DieCloude-$VERSION.dmg"
STAGE="$BUILD/dmg-stage"

"$ROOT/build.sh"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/DieCloude.app"
ln -s /Applications "$STAGE/Программы"
cp "$ROOT/Первый запуск DieCloude.command" "$STAGE/Первый запуск DieCloude.command"
chmod 755 "$STAGE/Первый запуск DieCloude.command"

# Создаёт стандартный установочный образ macOS.
hdiutil create \
  -volname "DieCloude" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo ""
echo "✅ Установочный образ готов:"
echo "$DMG"
echo ""
echo "Открой DMG и перетащи DieCloude.app в папку «Программы»."
open -R "$DMG"
