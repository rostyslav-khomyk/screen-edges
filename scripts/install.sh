#!/bin/bash
set -euo pipefail

ensure_signing_identity() {
  local name="Screen Edges Local"
  if security find-identity -v -p codesigning | grep -q "$name"; then
    echo "$name"
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  cat > "$tmp/cert.cfg" << 'EOF'
[ req ]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_req

[ req_dn ]
CN = Screen Edges Local
O = Rostyslav Khomyk

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = 1.3.6.1.5.5.7.3.3
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cfg" >/dev/null 2>&1
  openssl pkcs12 -export -legacy -out "$tmp/cert.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$name" -passout pass:screen-edges >/dev/null
  security import "$tmp/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P screen-edges -A >&2
  rm -rf "$tmp"
  echo "$name"
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$ROOT"
APP_DIR="$HOME/Library/Application Support/ScreenEdges"
mkdir -p "$APP_DIR"
APP="/Applications/ScreenEdges.app"
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges" 2>/dev/null || true
pkill -f "ScreenEdges.app/Contents/MacOS/screen-edges" 2>/dev/null || true
rm -rf "$APP" "$APP_DIR/ScreenEdges.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/screen-edges" "$APP/Contents/MacOS/screen-edges"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/screen-edges"
SIGN_ID="$(ensure_signing_identity)"
codesign --force --sign "$SIGN_ID" --identifier "com.rostyslavkhomyk.screen-edges" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
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
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>com.rostyslavkhomyk.screen-edges</string>
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
sleep 1
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges"
echo "Installed. Grant Screen Recording to screen-edges if macOS asks."
echo "WebSocket ws://127.0.0.1:8090  JSON tcp://127.0.0.1:19444"
