#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$ROOT"
APP_DIR="$HOME/Library/Application Support/ScreenEdges"
mkdir -p "$APP_DIR"
APP="$APP_DIR/ScreenEdges.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/screen-edges" "$APP/Contents/MacOS/screen-edges"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/screen-edges"
codesign --force --sign - "$APP"
CONFIG="$APP_DIR/config.json"
if [[ ! -f "$CONFIG" ]]; then
  TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  cat > "$CONFIG" <<EOF
{
  "token": "$TOKEN",
  "websocketPort": 8090,
  "jsonPort": 19444,
  "interval": 0.125
}
EOF
  echo "New token: $TOKEN"
else
  echo "Keeping existing $CONFIG"
fi
PLIST="$HOME/Library/LaunchAgents/com.rostyslavkhomyk.screen-edges.plist"
UID_NUM="$(id -u)"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.rostyslavkhomyk.screen-edges</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP/Contents/MacOS/screen-edges</string>
    <string>$CONFIG</string>
  </array>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>$APP_DIR/screen-edges.log</string>
  <key>StandardOutPath</key>
  <string>$APP_DIR/screen-edges.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges"
echo "Installed. Grant Screen Recording to screen-edges if macOS asks."
echo "WebSocket ws://127.0.0.1:8090  JSON tcp://127.0.0.1:19444"
