#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 tests/new_pixel_hero_static_v1/test_source_pixels.py
for test in test_static_atlas test_rejection test_candidate; do
 ./run.sh --headless -s "tests/new_pixel_hero_static_v1/$test.gd"
done
./run.sh --headless -s package_sample/test_resources.gd
# Compare the retained new scene against sealed source evidence.
# Do not run the absent old scene or overwrite its baseline.
for test in test_damage_trace test_gameplay_trace; do
 ./run.sh --headless --fixed-fps 60 -s "tests/new_pixel_hero_static_v1/$test.gd"
done
