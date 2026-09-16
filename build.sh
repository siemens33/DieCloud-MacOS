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
SOURCES=("$ROOT/src/main.swift" "$ROOT/src/VPN.swift" "$ROOT/src/UpdateManager.swift" "$ROOT/src/AdBlockService.swift")

COMMON=(-O -whole-module-optimization -sdk "$SDK_PATH" -framework AppKit -framework WebKit -framework QuartzCore -framework Network -framework Security)

# Универсальная сборка: Apple Silicon + Intel, минимум macOS 14.
"$SWIFTC" "${COMMON[@]}" -target arm64-apple-macos14.0 "${SOURCES[@]}" -o "$BUILD/DieCloude-arm64"
"$SWIFTC" "${COMMON[@]}" -target x86_64-apple-macos14.0 "${SOURCES[@]}" -o "$BUILD/DieCloude-x86_64"
lipo -create "$BUILD/DieCloude-arm64" "$BUILD/DieCloude-x86_64" -output "$MACOS/DieCloude"
rm -f "$BUILD/DieCloude-arm64" "$BUILD/DieCloude-x86_64"

# Официальный Xray-core для локального прокси DieCloude.
XRAY_TAG="v26.3.27"
for spec in "arm64:Xray-macos-arm64-v8a.zip" "x86_64:Xray-macos-64.zip"; do
  arch="${spec%%:*}"; asset="${spec#*:}"; temp="$BUILD/xray-$arch"
  rm -rf "$temp"; mkdir -p "$temp"
  echo "Загрузка Xray-core $XRAY_TAG ($arch)…"
  curl -fL --retry 3 "https://github.com/XTLS/Xray-core/releases/download/$XRAY_TAG/$asset" -o "$temp/xray.zip"
  # Проверка контрольной суммы через .dgst если доступен.
  # Формат .dgst Xray: MD5= / SHA1= / SHA2-256= / SHA2-512= (нам нужен SHA2-256).
  if curl -fL --retry 2 "https://github.com/XTLS/Xray-core/releases/download/$XRAY_TAG/$asset.dgst" -o "$temp/xray.zip.dgst" 2>/dev/null; then
    echo "Проверка sha256 ($arch)…"
    expected="$(awk -F'= ' '/SHA2-256/{gsub(/[[:space:]]/, "", $2); print $2}' "$temp/xray.zip.dgst" | head -1)"
    [[ -n "$expected" ]] || expected="$(grep -Eo '[0-9a-fA-F]{64}' "$temp/xray.zip.dgst" | head -1)"
    actual="$(shasum -a 256 "$temp/xray.zip" | cut -d' ' -f1)"
    if [[ -z "$expected" ]]; then
      echo "⚠️  Не смог разобрать SHA2-256 из .dgst, пропускаю проверку ($arch)"
    elif [[ "$expected" != "$actual" ]]; then
      echo "❌ sha256 mismatch Xray $arch: expected $expected got $actual"
      exit 1
    fi
  else
    echo "⚠️  .dgst недоступен, пропускаю проверку sha ($arch)"
  fi
  ditto -x -k "$temp/xray.zip" "$temp/unpacked"
  xray_path="$(find "$temp/unpacked" -type f -name xray -perm +111 | head -1)"
  [[ -n "$xray_path" ]] || { echo "❌ В архиве Xray не найден исполняемый файл"; exit 1; }
  cp "$xray_path" "$RESOURCES/xray-$arch"; chmod +x "$RESOURCES/xray-$arch"
  rm -rf "$temp"
done

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ROOT/RELEASE_NOTES.md" "$RESOURCES/RELEASE_NOTES.md"
cp "$ROOT/resources/theme-engine.js" "$RESOURCES/theme-engine.js"
cp "$ROOT/resources/adblock-rules.json" "$RESOURCES/adblock-rules.json"
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
