#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
APP_DIR="$ROOT_DIR/dist/FudanMailWidget.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.module-cache"
clang -fobjc-arc "$ROOT_DIR/Sources/main.m" \
  -o "$APP_DIR/Contents/MacOS/FudanMailWidget" \
  -framework AppKit \
  -framework Security
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/check_mail.py" "$APP_DIR/Contents/Resources/check_mail.py"
chmod +x "$APP_DIR/Contents/MacOS/FudanMailWidget" "$APP_DIR/Contents/Resources/check_mail.py"
echo "$APP_DIR"
