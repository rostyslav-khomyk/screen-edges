#!/bin/bash
set -euo pipefail
UID_NUM="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/com.rostyslavkhomyk.screen-edges.plist"
launchctl bootout "gui/$UID_NUM/com.rostyslavkhomyk.screen-edges" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$HOME/Library/Application Support/ScreenEdges/screen-edges"
echo "Uninstalled. Config was left in ~/Library/Application Support/ScreenEdges/config.json"
