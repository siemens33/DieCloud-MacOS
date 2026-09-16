#!/bin/zsh
set -euo pipefail

APP="/Applications/DieCloude.app"

echo "DieCloude — подготовка к первому запуску"
echo "========================================="
echo ""

if [[ ! -d "$APP" ]]; then
  osascript -e 'display alert "DieCloude не найден" message "Сначала перетащите DieCloude.app из DMG в папку «Программы», затем снова запустите этот файл." as critical' || true
  echo "❌ Приложение не найдено: $APP"
  echo "Сначала перенесите DieCloude.app в папку «Программы»."
  echo ""
  read -k 1 "?Нажмите Enter, чтобы закрыть окно." || true
  exit 1
fi

# Отмена в диалоге — штатный выход без ошибки.
if ! osascript -e 'display dialog "Сейчас macOS запросит пароль администратора. Скрипт снимет карантин только с DieCloude.app, восстановит права запуска и выполнит локальную подпись." buttons {"Отмена", "Продолжить"} default button "Продолжить" cancel button "Отмена" with icon caution'; then
  echo "Отменено пользователем."
  exit 0
fi

echo "Запрашиваются права администратора…"
sudo -v

# Поддерживаем sudo активным, пока выполняются операции.
while true; do sudo -n true; sleep 45; kill -0 "$$" || exit; done 2>/dev/null &
KEEPALIVE_PID=$!
trap 'kill "$KEEPALIVE_PID" 2>/dev/null || true' EXIT

echo "1/4 Снимаю карантин macOS…"
sudo /usr/bin/xattr -dr com.apple.quarantine "$APP"

echo "2/4 Восстанавливаю права запуска…"
sudo /bin/chmod 755 "$APP/Contents/MacOS/DieCloude"
for binary in "$APP/Contents/Resources/xray-arm64" "$APP/Contents/Resources/xray-x86_64"; do
  [[ -f "$binary" ]] && sudo /bin/chmod 755 "$binary"
done

echo "3/4 Обновляю локальную подпись…"
sudo /usr/bin/codesign --force --deep --sign - "$APP"

echo "4/4 Проверяю приложение…"
if ! /usr/bin/codesign --verify --deep --verbose=2 "$APP"; then
  echo "⚠️ Проверка подписи показала предупреждения, но приложение обычно запускается."
fi

printf '\n✅ DieCloude подготовлен. Запускаю приложение…\n'
/usr/bin/open "$APP"

sleep 2
exit 0
