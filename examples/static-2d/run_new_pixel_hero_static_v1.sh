#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./run.sh scenes/corn_route_new_pixel_hero_static_v1.tscn "$@"
