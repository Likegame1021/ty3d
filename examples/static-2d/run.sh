#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -w "${XDG_DATA_HOME:-$HOME/.local/share}" ]; then
 export XDG_DATA_HOME=/tmp/hd2d-trial-data
 export XDG_CONFIG_HOME=/tmp/hd2d-trial-config
 export XDG_CACHE_HOME=/tmp/hd2d-trial-cache
 mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
fi
if [ ! -d .godot/imported ]; then
 godot --headless --path . --editor --import --quit
fi
exec godot --path . "$@"
