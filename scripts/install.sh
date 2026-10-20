#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$ROOT"
APP_DIR="$HOME/Library/Application Support/ScreenEdges"
mkdir -p "$APP_DIR"
cp "$ROOT/.build/release/screen-edges" "$APP_DIR/screen-edges"
chmod 755 "$APP_DIR/screen-edges"
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
    <string>$APP_DIR/screen-edges</string>
    <string>$CONFIG</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges"
echo "Installed. Grant Screen Recording to screen-edges if macOS asks."
echo "WebSocket ws://127.0.0.1:8090  JSON tcp://127.0.0.1:19444"
