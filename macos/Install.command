#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
app="$script_root/Teams Bar Hider.app"
if [[ ! -d "$app" ]]; then
    bash "$script_root/build.sh"
    app="$script_root/../dist/macos/Teams Bar Hider.app"
fi
target="$HOME/Applications/Teams Bar Hider.app"
if [[ -x "$target/Contents/MacOS/TeamsBarHider" ]]; then
    "$target/Contents/MacOS/TeamsBarHider" --stop
    sleep 2
fi
mkdir -p "$HOME/Applications"
ditto "$app" "$target"
open "$target" --args --install
echo 'Installed. Allow Teams Bar Hider in System Settings > Privacy & Security > Accessibility.'
