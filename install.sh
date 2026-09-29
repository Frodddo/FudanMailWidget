#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
SOURCE_APP="$ROOT_DIR/dist/FudanMailWidget.app"
INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/FudanMailWidget.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_FILE="$AGENT_DIR/com.openai.fudan-mail-widget.plist"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/build.sh"
fi

mkdir -p "$INSTALL_DIR" "$AGENT_DIR"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"

/usr/libexec/PlistBuddy -c "Clear dict" "$AGENT_FILE" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :Label string com.openai.fudan-mail-widget" "$AGENT_FILE"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$AGENT_FILE"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $TARGET_APP/Contents/MacOS/FudanMailWidget" "$AGENT_FILE"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$AGENT_FILE"

launchctl bootout "gui/$(id -u)/com.openai.fudan-mail-widget" 2>/dev/null || true
launchctl enable "gui/$(id -u)/com.openai.fudan-mail-widget"
launchctl bootstrap "gui/$(id -u)" "$AGENT_FILE"
launchctl kickstart -k "gui/$(id -u)/com.openai.fudan-mail-widget"

echo "已安装并启动：$TARGET_APP"
