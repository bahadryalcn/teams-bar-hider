#!/bin/bash
set -euo pipefail
app="$HOME/Applications/Teams Bar Hider.app"
if [[ -x "$app/Contents/MacOS/TeamsBarHider" ]]; then "$app/Contents/MacOS/TeamsBarHider" --stop; fi
agent="$HOME/Library/LaunchAgents/local.teamsbarhider.agent.plist"
if [[ -f "$agent" ]]; then
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    rm -- "$agent"
fi
echo 'Stopped and removed automatic startup. App retained in ~/Applications.'
