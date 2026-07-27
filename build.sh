#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/DieCloude.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$BUILD/DieCloude.iconset"

trap 'echo "\n❌ Сборка не завершена. Прочитай ошибку выше."; rm -rf "$APP"' ERR
rm -rf "$APP" "$ICONSET" "$BUILD/DieCloude-arm64" "$BUILD/DieCloude-x86_64"
mkdir -p "$MACOS" "$RESOURCES" "$ICONSET"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
SOURCES=("$ROOT/src/main.swift" "$ROOT/src/VPN.swift" "$ROOT/src/UpdateManager.swift")

COMMON=(-O -whole-module-optimization -sdk "$SDK_PATH" -framework AppKit -framework WebKit -framework QuartzCore -framework Network -framework Security)

# Универсальная сборка: Apple Silicon + Intel.
"$SWIFTC" "${COMMON[@]}" -target arm64-apple-macos12.0 "${SOURCES[@]}" -o "$BUILD/DieCloude-arm64"
"$SWIFTC" "${COMMON[@]}" -target x86_64-apple-macos12.0 "${SOURCES[@]}" -o "$BUILD/DieCloude-x86_64"
lipo -create "$BUILD/DieCloude-arm64" "$BUILD/DieCloude-x86_64" -output "$MACOS/DieCloude"
rm -f "$BUILD/DieCloude-arm64" "$BUILD/DieCloude-x86_64"

# Официальный Xray-core для локального прокси DieCloude.
XRAY_TAG="v26.7.11"
for spec in "arm64:Xray-macos-arm64-v8a.zip" "x86_64:Xray-macos-64.zip"; do
  arch="${spec%%:*}"; asset="${spec#*:}"; temp="$BUILD/xray-$arch"
  rm -rf "$temp"; mkdir -p "$temp"
  echo "Загрузка Xray-core $XRAY_TAG ($arch)…"
  curl -fL --retry 3 "https://github.com/XTLS/Xray-core/releases/download/$XRAY_TAG/$asset" -o "$temp/xray.zip"
  ditto -x -k "$temp/xray.zip" "$temp/unpacked"
  xray_path="$(find "$temp/unpacked" -type f -name xray -perm +111 | head -1)"
  [[ -n "$xray_path" ]] || { echo "❌ В архиве Xray не найден исполняемый файл"; exit 1; }
  cp "$xray_path" "$RESOURCES/xray-$arch"; chmod +x "$RESOURCES/xray-$arch"
  rm -rf "$temp"
done

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ROOT/resources/theme-engine.js" "$RESOURCES/theme-engine.js"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/resources/DieCloudeIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$ROOT/resources/DieCloudeIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/DieCloude.icns"
rm -rf "$ICONSET"

chmod 755 "$MACOS/DieCloude"
chmod 755 "$RESOURCES/xray-arm64" "$RESOURCES/xray-x86_64"

codesign --force --deep --sign - "$APP"
[[ -x "$MACOS/DieCloude" ]] || { echo "❌ Исполняемый файл не создан"; exit 1; }
file "$MACOS/DieCloude"
echo "✅ Универсальное приложение собрано: $APP"
